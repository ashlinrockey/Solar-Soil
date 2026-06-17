# Project: Solar Soil IoT Dashboard

## Overview
Full-stack IoT monitoring system for a solar-powered agricultural sensor network. College project, May 2026.

## Credentials
- **InfluxDB**: http://localhost:8086 | admin / adminpassword123 | org: college | bucket: solarsoil | token: solarsoil_secret_token_12345
- **Web App Login**: username / password
- **MQTT**: broker.emqx.io:1883 | topic: solarsoil/nodeA

## ESP32 Firmware
- **Sensor Node**: lora/node.ino — DHT22, soil moisture, INA219, LoRa TX, deep sleep 15min
- **Gateway Node**: lora/gateway.ino — LoRa RX, WiFi, MQTT publish, OLED display (U8g2 lib)

## Backend
- Node.js Express, WebSocket, MQTT subscriber, InfluxDB writer
- Default port: 5000
- Auth: bcryptjs, lowdb (users.db.json)

## Frontend
- Flutter Web (main) + Vanilla HTML/Tailwind fallback (index.html)

## Deploy
- GitHub zip: solar-soil-github.zip (created by make_github_zip.ps1)
- Production: Podman pods, Docker Compose, automated VPS scripts
