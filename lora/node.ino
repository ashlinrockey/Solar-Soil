#include <SPI.h>
#include <LoRa.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <Wire.h>
#include <Adafruit_INA219.h>

// Pin definitions for LoRa (e.g., TTGO LoRa32 or similar)
#define SCK 5
#define MISO 19
#define MOSI 27
#define SS 18
#define RST 14
#define DIO0 26

// Sensor Pin Definitions
#define DHTPIN 4
#define DHTTYPE DHT22
#define SOIL_PIN 36

DHT dht(DHTPIN, DHTTYPE);
Adafruit_INA219 ina219;

void setup() {
  Serial.begin(115200);
  
  // Initialize Sensors & I2C
  dht.begin();
  Wire.begin(21, 22); // SDA on GPIO 21, SCL on GPIO 22
  if (!ina219.begin()) {
    Serial.println("Failed to find INA219 chip");
  }
  
  // Initialize LoRa
  SPI.begin(SCK, MISO, MOSI, SS);
  LoRa.setPins(SS, RST, DIO0);
  
  if (!LoRa.begin(868E6)) { // Set frequency (868 or 915 MHz)
    Serial.println("LoRa init failed!");
    while (1);
  }

  // 1. Read Physical Sensors
  float temp = dht.readTemperature();
  float humidity = dht.readHumidity();
  
  // Capacitive Moisture Sensor Calibration mapping
  int rawAnalog = analogRead(SOIL_PIN);
  int soil = map(rawAnalog, 3200, 1100, 0, 100);
  soil = constrain(soil, 0, 100);

  // Read INA219 Current and Bus Voltage
  float voltage = ina219.getBusVoltage_V();
  float current = ina219.getCurrent_mA();

  // Guard against NaN from failed sensor reads
  if (isnan(temp)) { temp = 24.0; }
  if (isnan(humidity)) { humidity = 55.0; }
  if (isnan(voltage)) { voltage = 0.0; }
  if (isnan(current)) { current = 0.0; }

  temp = constrain(temp, -10, 60);
  humidity = constrain(humidity, 0, 100);

  // 2. Package in JSON
  StaticJsonDocument<256> doc;
  doc["temp"] = temp;
  doc["humidity"] = humidity;
  doc["soil"] = soil;
  doc["v"] = voltage;
  doc["current"] = current;
  
  String output;
  serializeJson(doc, output);

  // 3. Send via LoRa
  Serial.print("Sending packet: ");
  Serial.println(output);
  LoRa.beginPacket();
  LoRa.print(output);
  LoRa.endPacket();

  // 4. Go to Deep Sleep (15 minutes)
  Serial.println("Going to sleep...");
  esp_sleep_enable_timer_wakeup(15 * 60 * 1000000ULL);
  esp_deep_sleep_start();
}

void loop() {}
