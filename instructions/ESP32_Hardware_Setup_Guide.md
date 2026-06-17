# 🌱 ESP32 Hardware Connection & Setup Guide (Solar Soil IoT)

This guide provides a comprehensive hardware inventory and step-by-step wiring instructions for both the **Main Sensor Node (Node A)** and the **Gateway Node (Node B)** in the Solar Soil IoT system.

---

## 📅 Table of Contents
1. [Parts Inventory (BOM)](#1-parts-inventory-bom)
2. [Power System Regulation & Wiring](#2-power-system-regulation--wiring)
3. [Main Sensor Node Connection Pinout](#3-main-sensor-node-connection-pinout)
4. [Gateway Node Connection Pinout](#4-gateway-node-connection-pinout)
5. [Passive Electronics & Noise Suppression](#5-passive-electronics--noise-suppression)
6. [Quick Breadboard Wiring Visualizer](#6-quick-breadboard-wiring-visualizer)

---

## 1. Parts Inventory (BOM)

The components listed below are sourced from the project's hardware sheets (`hardwarlist2.0.xlsx`).

### Node A: Main Sensor Node Components
| Component | Purpose | Priority | Reichelt Part No. |
| :--- | :--- | :--- | :--- |
| **ESP32-C6 DevKit N8** | Main RISC-V microcontroller with deep sleep | **Essential** | `esp32-c6 n8` |
| **SX1276 LoRa Module (868 MHz)** | SPI wireless radio transceiver module | **Essential** | - |
| **LoRa Antenna 868MHz (SMA)** | High-gain rubber duck antenna | **Essential** | `ora_868_mhz_antenna_sma_plug` |
| **Capacitive Soil Moisture v1.2** | Soil moisture analog sensor | **Essential** | `sensor_bodenfeuchte_-223620` |
| **DHT22 Temperature & Humidity** | Air environmental sensor | **Essential** | `dht22` |
| **INA219 Power Monitor** | I2C High-side voltage/current monitor | **Optional** | `ina219` |
| **Solar Panel 6V 2W** | Solar charging energy source | **Essential** | - |
| **4x AA NiMH Batteries (2100mAh)** | Rechargeable battery storage pack (4.8V) | **Essential** | `recyko_nimh-akku_aa_mignon_2100_mah` |
| **4x AA Battery Holder** | Holds and connects cells in series | **Essential** | `holder AA` |
| **LM2596 Buck Converter** | Regulates voltage to constant 5.0V | **Essential** | `2596-buvk-convtr` |
| **Schottky Diode 1N5819** | Prevents reverse battery discharge | **Essential** | `in5819` |
| **Passives & Connectors** | Breadboard, jumpers, headers, resistors, capacitors | **Essential** | - |

### Node B: Gateway Node Components
| Component | Qty | Purpose | Priority | Reichelt Part No. |
| :--- | :--- | :--- | :--- | :--- |
| **ESP32-C6 DevKit N8** | 1 | Bridge controller (WiFi + LoRa client) | **Essential** | `esp32-c6 n8` |
| **LoRa Module 868MHz** | 1 | Receives packet frames from field nodes | **Essential** | - |
| **LoRa Antenna 868MHz SMA** | 1 | Gateway receiving antenna | **Essential** | `ora_868_mhz_antenna_sma_plug` |
| **OLED Display 0.96" SSD1306** | 1 | Status monitor display screen | **Optional** | `oled_display_0_96_128x64_pixels_` |
| **USB 5V/2A Adapter** | 1 | Powers gateway from AC mains outlet | **Essential** | - |
| **USB-C Cable (1m)** | 1 | USB-C connection to Gateway ESP32 | **Essential** | `usb-a_connector_to_usb-c_connector_1m-` |
| **Breadboard & Wires** | 1 | Interconnects LoRa and OLED modules | **Essential** | - |

---

## 2. Power System Regulation & Wiring

The field-deployed Main Sensor Node operates off battery buffers. A dedicated power path adjusts solar input voltage levels and isolates charging nodes.

> ⚠️ **IMPORTANT (Diode Protection):** You must install the **1N5819 Schottky Diode** in series between the Solar Panel (+) and the Battery pack to prevent the batteries from discharging back into the solar cells during dark conditions.

### Power Wiring Diagram
```
  [ SOLAR PANEL ]
    (+) ──────► [ 1N5819 DIODE (Anode) ] ── [ (Cathode) ] ──┐
    (-) ───────────────────────────────────────────────────┼──┐
                                                           │  │
                                                           ▼  ▼
                                                   [ BATTERY PACK (4.8V) ]
                                                           │  │
                                   ┌───────────────────────┘  │
                                   │   ┌──────────────────────┘
                                   ▼   ▼
                          [ LM2596 BUCK CONVERTER ]
                            IN(+) ─── IN(-)
                            OUT(+) ── OUT(-)
                              │         │
                              ▼         ▼
                        [ BREADBOARD POWER RAILS ]
                              (+) ────── (-)
                              (5V)     (GND)
```

### Power Calibration & Hookup Checklist:
1. Connect the **Solar Panel Positive (+)** wire to the Anode (unmarked side) of the **1N5819 Schottky Diode**.
2. Connect the Cathode (striped side) of the diode to the **Battery Holder Positive (+)** lead.
3. Connect the **Solar Panel Negative (-)** wire directly to the **Battery Holder Negative (-)** lead.
4. Wire the battery pack leads directly to the **LM2596 Buck Converter Input** (`IN+` and `IN-`).
5. **Adjust Output:** Before connecting the ESP32, power the LM2596 and use a multimeter to measure voltage on `OUT+` and `OUT-`. Turn the brass potentiometer screw counter-clockwise until output voltage measures exactly **5.0V**.
6. Connect the adjusted buck converter outputs (`OUT+` and `OUT-`) to the breadboard power distribution rails.
7. *(Optional)* Run the Battery Holder (+) positive lead through the high-side shunt inputs `VIN+` and `VIN-` of the **INA219 Power Monitor** to trace power draw levels.

---

## 3. Main Sensor Node Connection Pinout

Below is the connection layout mapping the components to the **ESP32-C6 DevKit** on the breadboard.

| ESP32-C6 Pin | Component Pin | Connection Description | Signal Type |
| :--- | :--- | :--- | :--- |
| **5V (VIN)** | LM2596 OUT(+) | Main system power supply input | 5.0V DC Input |
| **GND** | LM2596 OUT(-) | Common ground reference line | Ground |
| **3.3V** | Sensors & LoRa VCC | Low-power module VCC rail | 3.3V DC Output |
| **GPIO 5** | LoRa SCK | SPI Serial Clock | Output |
| **GPIO 19** | LoRa MISO | SPI Master In Slave Out | Input |
| **GPIO 27** | LoRa MOSI | SPI Master Out Slave In | Output |
| **GPIO 18** | LoRa SS (NSS) | SPI Chip Select | Output |
| **GPIO 14** | LoRa RST | LoRa Module Hardware Reset | Output |
| **GPIO 26** | LoRa DIO0 | LoRa Transmission Interrupt (TxDone) | Input |
| **GPIO 4** | DHT22 DATA | Ambient Temp & Humidity Data | Digital I/O |
| **GPIO 36** | Soil moisture AOUT | Capacitive Moisture Sensor output | Analog Input |
| **GPIO 21** | INA219 SDA | I2C Serial Data line | Digital I/O |
| **GPIO 22** | INA219 SCL | I2C Serial Clock line | Output |

---

## 4. Gateway Node Connection Pinout

The Gateway Node runs on external mains power from the USB adapter and translates radio packages to the MQTT broker.

| ESP32-C6 Pin | Component Pin | Connection Description | Signal Type |
| :--- | :--- | :--- | :--- |
| **USB 5V** | USB-C Port | Power input from 5V/2A mains wall adapter | 5.0V DC Input |
| **3.3V** | LoRa & OLED VCC | Low-power distribution line | 3.3V DC Output |
| **GND** | LoRa & OLED GND | Ground reference loop | Ground |
| **GPIO 5** | LoRa SCK | SPI Serial Clock | Output |
| **GPIO 19** | LoRa MISO | SPI Master In Slave Out | Input |
| **GPIO 27** | LoRa MOSI | SPI Master Out Slave In | Output |
| **GPIO 18** | LoRa SS (NSS) | SPI Chip Select | Output |
| **GPIO 14** | LoRa RST | LoRa Module Hardware Reset | Output |
| **GPIO 26** | LoRa DIO0 | LoRa Receive Interrupt (RxDone) | Input |
| **GPIO 4** | OLED SDA | I2C Display Serial Data | Digital I/O |
| **GPIO 15** | OLED SCL | I2C Display Serial Clock | Output |
| **GPIO 16** | OLED RST | SSD1306 Display Hardware Reset | Output |

---

## 5. Passive Electronics & Noise Suppression

To optimize measurement accuracy and prevent LoRa transmitter spikes from causing system reboots or analog sensor noise, install these passives:

1. **Power Rail Smoothing (10µF Capacitor):**
   * Place the **10µF Electrolytic Capacitor** across the breadboard's 5V power rails (`+` to `-`).
   * *Caution:* Pay attention to polarity. The negative leg is marked with a gray stripe and must connect to GND (`-`).
2. **High-Frequency Decoupling (100nF Capacitor):**
   * Place the **100nF Ceramic Capacitor** directly between the VCC and GND pins of the LoRa module. This handles rapid load fluctuations during LoRa transmit spikes.
3. **DHT22 Pull-Up Resistor (4.7kΩ):**
   * Place the **4.7kΩ resistor** between the DHT22 VCC (3.3V) pin and the DHT22 DATA pin. This keeps the single-wire data line high by default to prevent communication failures.

---

## 6. Quick Breadboard Wiring Visualizer

Use these visual connection maps to complete your breadboard hookups quickly.

### Main Sensor Node (Node A) Quick Diagram

```
           +---------------------------------------------+
           |          BREADBOARD POWER RAILS             |
           | [RED RAIL (+)] ◄─── LM2596 OUT(+) 5V        |
           | [BLK RAIL (-)] ◄─── LM2596 OUT(-) GND       |
           +---------------------------------------------+
              ▲   ▲
              │   │  (Passive Smoothing: 10µF Cap [+-] across Rails)
              │   │
           +──┴───┴──────────────────────────────────────+
           |             ESP32-C6 DEV KIT                |
           |                                             |
           |  (L) Pins                      (R) Pins     |
           |  [  RST  ]                    [  3.3V ] ────┼──► [To Sensors/LoRa VCC]
           |  [  3.3V ]                    [  GND  ] ────┼──► [To GND Rail]
           |  [GPIO 36] ◄── Soil (AOUT)    [  5VIN ] ◄───┼──► [From RED Rail +5V]
           |  [GPIO  0]                    [GPIO 22] ────┼──► INA219 SCL
           |  [GPIO  1]                    [GPIO 21] ────┼──► INA219 SDA
           |  [GPIO  4] ◄── DHT22 DATA     [GPIO 20]     |
           |  [GPIO  5] ───► LoRa SCK      [GPIO 19] ◄───┼──► LoRa MISO
           |  [GPIO 18] ───► LoRa CS/NSS   [GPIO 27] ────┼──► LoRa MOSI
           |  [GPIO 14] ───► LoRa RST      [GPIO 26] ◄───┼──► LoRa DIO0
           +---------------------------------------------+
```

#### Sensor & Module Quick Pin Hookups (Node A)
* **LoRa SX1276 Module:**
  * `VCC` ──► `3.3V`
  * `GND` ──► `GND`
  * `SCK` ──► `GPIO 5`
  * `MISO` ──► `GPIO 19`
  * `MOSI` ──► `GPIO 27`
  * `CS/NSS` ──► `GPIO 18`
  * `RST` ──► `GPIO 14`
  * `DIO0` ──► `GPIO 26`
  * *(Decoupling: 100nF Ceramic capacitor directly across LoRa VCC & GND)*
* **DHT22 Temperature & Humidity Sensor:**
  * `1. VCC` ──► `3.3V`
  * `2. DATA` ──► `GPIO 4`
  * `3. NC` (Leave disconnected)
  * `4. GND` ──► `GND`
  * *(Pull-Up: Connect a 4.7kΩ resistor between VCC and DATA)*
* **Capacitive Soil Moisture Sensor v1.2:**
  * `VCC` ──► `3.3V`
  * `GND` ──► `GND`
  * `AOUT` ──► `GPIO 36`
* **INA219 Power Monitor:**
  * `VCC` ──► `3.3V`
  * `GND` ──► `GND`
  * `SDA` ──► `GPIO 21`
  * `SCL` ──► `GPIO 22`
  * `VIN(+)` ──► Battery Holder (+)
  * `VIN(-)` ──► LM2596 IN(+)

---

### Gateway Node (Node B) Quick Diagram

```
           +---------------------------------------------+
           |          GATEWAY BREADBOARD POWER           |
           | [VCC RAIL (+)] ◄─── ESP32 3.3V OUT          |
           | [GND RAIL (-)] ◄─── ESP32 GND OUT           |
           +---------------------------------------------+
              ▲   ▲
              │   │
           +──┴───┴──────────────────────────────────────+
           |             ESP32-C6 GATEWAY                |
           |                                             |
           |  (L) Pins                      (R) Pins     |
           |  [  RST  ]                    [  3.3V ] ────┼──► [VCC RAIL (+)]
           |  [  3.3V ]                    [  GND  ] ────┼──► [GND RAIL (-)]
           |  [GPIO 36]                    [  5VIN ] ◄───┼──► [5V USB Power Input]
           |  [GPIO  4] ───► OLED SDA      [GPIO 22]     |
           |  [GPIO  5] ───► LoRa SCK      [GPIO 21]     |
           |  [GPIO 18] ───► LoRa CS/NSS   [GPIO 19] ◄───┼──► LoRa MISO
           |  [GPIO 14] ───► LoRa RST      [GPIO 27] ────┼──► LoRa MOSI
           |  [GPIO 15] ───► OLED SCL      [GPIO 26] ◄───┼──► LoRa DIO0
           |  [GPIO 16] ───► OLED RST      [GPIO 20]     |
           +---------------------------------------------+
```

#### Module Quick Pin Hookups (Node B)
* **LoRa RX Transceiver:**
  * `VCC` ──► `3.3V`
  * `GND` ──► `GND`
  * `SCK` ──► `GPIO 5`
  * `MISO` ──► `GPIO 19`
  * `MOSI` ──► `GPIO 27`
  * `CS/NSS` ──► `GPIO 18`
  * `RST` ──► `GPIO 14`
  * `DIO0` ──► `GPIO 26`
  * *(Decoupling: 100nF Ceramic capacitor directly across LoRa VCC & GND)*
* **SSD1306 OLED Display (0.96"):**
  * `VCC` ──► `3.3V`
  * `GND` ──► `GND`
  * `SDA` ──► `GPIO 4`
  * `SCL` ──► `GPIO 15`
  * `RST` ──► `GPIO 16`
* **USB Power Supply Adapter:**
  * Hook up the USB-C cable to the Gateway ESP32 USB port and plug it into a 5V/2A power supply adapter connected to AC mains.

