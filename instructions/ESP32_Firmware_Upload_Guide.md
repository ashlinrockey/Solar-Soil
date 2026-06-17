# ESP32 Firmware Upload Guide — Solar Soil IoT

## Overview

Two ESP32 boards need firmware:

| Board | File | Role |
|-------|------|------|
| **Sensor Node** | `lora/node.ino` | Reads sensors, sends data via LoRa, deep sleeps |
| **Gateway Node** | `lora/gateway.ino` | Receives LoRa, forwards to MQTT over WiFi |

---

## 1. Required Arduino Libraries

Install these in Arduino IDE (Sketch → Include Library → Manage Libraries):

| Library | Used By |
|---------|---------|
| `LoRa` by Sandeep Mistry | Both |
| `ArduinoJson` by Benoit Blanchon | node.ino |
| `DHT sensor library` by Adafruit | node.ino |
| `Adafruit INA219` by Adafruit | node.ino |
| `PubSubClient` by Nick O'Leary | gateway.ino |
| `WiFi` (built-in ESP32 core) | gateway.ino |

Also install **ESP32 board support**:
- File → Preferences → Additional Boards Manager URLs:
  `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
- Tools → Board → Boards Manager → search "ESP32" → install

---

## 2. Wiring — Sensor Node (node.ino)

| ESP32 Pin | Connected To |
|-----------|-------------|
| GPIO 4 | DHT22 Data |
| GPIO 36 (ADC0) | Soil Moisture Sensor (analog out) |
| GPIO 21 (SDA) | INA219 SDA |
| GPIO 22 (SCL) | INA219 SCL |
| GPIO 5 (SCK) | LoRa Module SCK |
| GPIO 19 (MISO) | LoRa Module MISO |
| GPIO 27 (MOSI) | LoRa Module MOSI |
| GPIO 18 (SS) | LoRa Module NSS |
| GPIO 14 (RST) | LoRa Module RST |
| GPIO 26 (DIO0) | LoRa Module DIO0 |

---

## 3. Wiring — Gateway Node (gateway.ino)

Same LoRa pin connections as node above. Additionally:

| ESP32 Pin | Connected To |
|-----------|-------------|
| No extra sensors needed | WiFi handles internet |

---

## 4. Configure Before Uploading

### node.ino
- **Line 38**: Change frequency if needed:
  - `868E6` for Europe/India
  - `915E6` for US/Americas

### gateway.ino
- **Line 5**: Set your WiFi SSID
  ```cpp
  const char* ssid = "YourWiFiName";
  ```
- **Line 6**: Set your WiFi password
  ```cpp
  const char* password = "YourWiFiPassword";
  ```
- **Line 18**: Change LoRa frequency if needed (same as node)

---

## 5. Upload Steps

### Sensor Node (node.ino)
1. Open `lora/node.ino` in Arduino IDE
2. Tools → Board → ESP32 Arduino → select your ESP32 model
3. Tools → Port → select the COM port
4. Click **Upload** (→ button)
5. Open Serial Monitor (Tools → Serial Monitor, 115200 baud) to verify

### Gateway Node (gateway.ino)
1. Open `lora/gateway.ino` in Arduino IDE
2. Same board/port selection as above
3. Click **Upload**
4. Open Serial Monitor to verify WiFi connection and LoRa reception

---

## 6. Verification

After both boards are running:

1. **Node** should print to Serial Monitor:
   ```
   Sending packet: {"temp":28,"humidity":65,"soil":42,"v":5.2,"current":410}
   Going to sleep...
   ```
   Then wakes every 15 minutes to send again.

2. **Gateway** should print:
   ```
   Connected to MQTT Broker
   Forwarding to MQTT: {"temp":28,"humidity":65,"soil":42,"v":5.2,"current":410}
   ```

3. Check the web dashboard — data should appear in real time.

---

## 7. Troubleshooting

| Problem | Fix |
|---------|-----|
| LoRa init failed | Check wiring, frequency matching between node & gateway |
| DHT sensor failed | Check GPIO 4 wiring, try DHT11 instead of DHT22 |
| WiFi not connecting | Verify SSID/password, check 2.4 GHz band |
| MQTT not connecting | Gateway needs internet access via WiFi |
| No data on dashboard | Start `lora/simulator.py` to test without hardware |

---

*Solar Soil IoT — College Project, May 2026*
