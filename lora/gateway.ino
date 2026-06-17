#include <WiFi.h>
#include <PubSubClient.h>
#include <LoRa.h>
#include <U8g2lib.h>
#include <Wire.h>
#include <ArduinoJson.h>

// WiFi
const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";

// MQTT
const char* mqtt_server = "broker.emqx.io";
const char* mqtt_topic = "solarsoil/nodeA";

// OLED pins (TTGO LoRa32 V1: SDA=4, SCL=15 | V2: SDA=21, SCL=22)
#define OLED_SDA 4
#define OLED_SCL 15
#define OLED_RST 16

// LoRa pins
#define LORA_SS 18
#define LORA_RST 14
#define LORA_DIO0 26

U8G2_SSD1306_128X64_NONAME_1_SW_I2C display(U8G2_R0, OLED_SCL, OLED_SDA, OLED_RST);

WiFiClient espClient;
PubSubClient client(espClient);

int packetCount = 0;
String lastPayload = "Waiting...";
String lastTemp = "--";
String lastSoil = "--";
String lastVolt = "--";

void setup() {
  Serial.begin(115200);

  // Reset OLED
  pinMode(OLED_RST, OUTPUT);
  digitalWrite(OLED_RST, LOW);
  delay(10);
  digitalWrite(OLED_RST, HIGH);
  delay(10);

  display.begin();
  display.clearBuffer();
  display.setFont(u8g2_font_6x10_tf);
  display.drawStr(0, 12, "Solar Soil IoT");
  display.drawStr(0, 26, "Gateway Node");
  display.sendBuffer();

  SPI.begin(5, 19, 27, LORA_SS);
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

  if (!LoRa.begin(868E6)) {
    display.drawStr(0, 40, "LoRa FAILED!");
    display.sendBuffer();
    while (1);
  }

  display.drawStr(0, 40, "LoRa OK");
  display.sendBuffer();

  setup_wifi();
  client.setServer(mqtt_server, 1883);
}

void setup_wifi() {
  display.drawStr(0, 54, "Connecting WiFi...");
  display.sendBuffer();

  WiFi.begin(ssid, password);
  int dots = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    dots = (dots + 1) % 4;
  }
  display.clearBuffer();
  display.setFont(u8g2_font_6x10_tf);
  display.drawStr(0, 12, "WiFi Connected");
  display.setFont(u8g2_font_5x7_tf);
  display.drawStr(0, 24, WiFi.localIP().toString().c_str());
  display.sendBuffer();
  delay(1500);
}

void updateDisplay() {
  display.firstPage();
  do {
    display.setFont(u8g2_font_5x7_tf);
    display.drawStr(0, 8, "WiFi: ");
    display.drawStr(30, 8, WiFi.localIP().toString().c_str());

    display.drawStr(0, 18, "MQTT: ");
    display.drawStr(30, 18, client.connected() ? "Connected" : "Disconnected");

    display.drawStr(0, 28, "LoRa Pkts: ");
    display.drawStr(60, 28, String(packetCount).c_str());

    display.drawStr(0, 42, "Temp: ");
    display.drawStr(30, 42, (lastTemp + " C").c_str());

    display.drawStr(0, 52, "Soil: ");
    display.drawStr(30, 52, (lastSoil + " %").c_str());

    display.drawStr(0, 62, "Solar: ");
    display.drawStr(30, 62, (lastVolt + " V").c_str());
  } while (display.nextPage());
}

void loop() {
  if (!client.connected()) { reconnect(); }
  client.loop();

  int packetSize = LoRa.parsePacket();
  if (packetSize) {
    String incoming = "";
    while (LoRa.available()) {
      incoming += (char)LoRa.read();
    }

    packetCount++;
    lastPayload = incoming;
    Serial.print("Forwarding: ");
    Serial.println(incoming);

    // Parse JSON to update display
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, incoming);
    if (!err) {
      lastTemp = doc["temp"].as<String>();
      lastSoil = doc["soil"].as<String>();
      lastVolt = doc["v"].as<String>();
    }

    client.publish(mqtt_topic, incoming.c_str());
    updateDisplay();
  }
}

void reconnect() {
  display.firstPage();
  do {
    display.setFont(u8g2_font_5x7_tf);
    display.drawStr(0, 12, "MQTT Reconnecting...");
    display.drawStr(0, 26, mqtt_server);
  } while (display.nextPage());

  while (!client.connected()) {
    if (client.connect("SolarGateway")) {
      updateDisplay();
    } else {
      delay(5000);
    }
  }
}
