# Project: Solar Soil IoT Dashboard

## Overview
Full-stack IoT monitoring system for a solar-powered agricultural sensor network. College project, May 2026.

## Credentials
- **InfluxDB**: http://localhost:8086 | admin / adminpassword123 | org: college | bucket: solarsoil | token: solarsoil_secret_token_12345
- **Web App Login**: username / password
- **MQTT**: broker.emqx.io:1883 | topic: solarsoil/# (wildcard for multi-node)

## ESP32 Firmware
- **Sensor Node**: lora/node.ino — DHT22, soil moisture, INA219, LoRa TX, deep sleep 15min
- **Gateway Node**: lora/gateway.ino — LoRa RX, WiFi, MQTT publish, OLED display (U8g2 lib)

## Backend
- Node.js Express, WebSocket, MQTT subscriber, InfluxDB writer
- Default port: 5000
- Auth: bcryptjs, lowdb (users.db.json)

## Frontend
- Flutter Web (main) + Vanilla HTML/Tailwind fallback (index.html)

## Build & Deploy
- Flutter web: `puro flutter build web --release --no-tree-shake-icons --base-href=/dashboard/`
- Podman image: `podman build --no-cache -t localhost/solarsoil-app:latest -f Dockerfile .`
- Pod bundle: `build_pod_bundle.ps1` (Flutter → Docker → InfluxDB → single tar)
- Kube yaml: `backend/solarsoil-kube.yaml` — env var `MQTT_TOPIC: solarsoil/#`
- VPS: SCP tar → `podman load` → `podman kube play` → `systemctl restart caddy`
- GitHub zip: solar-soil-github.zip (created by make_github_zip.ps1)
