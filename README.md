# ☀️ Solar Soil — AI-Powered Agricultural Intelligence Platform

> **2050-Grade Precision Agriculture.** Real-time sensor fusion, holographic 3D plant visualization, and AI-driven crop diagnostics — all running in your browser.

[![Live Demo](https://img.shields.io/badge/LIVE-DEMO-00E5FF?style=for-the-badge)](https://solarsoil.ashlin.rocks/dashboard)
[![Flutter](https://img.shields.io/badge/Flutter-Web-02569B?style=flat&logo=flutter)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Node.js-20-339933?style=flat&logo=nodedotjs)](https://nodejs.org)
[![InfluxDB](https://img.shields.io/badge/InfluxDB-2.7-22ADF6?style=flat&logo=influxdb)](https://www.influxdata.com)
[![MQTT](https://img.shields.io/badge/MQTT-EMQX-660066?style=flat&logo=mqtt)](https://www.emqx.io)
[![AI](https://img.shields.io/badge/AI-Gemini_•_OpenRouter_•_Ollama-4285F4?style=flat&logo=googlegemini)](https://deepmind.google/gemini)

---

## 🔥 The Future of Farming, Today

Solar Soil transforms a mesh of humble ESP32 sensors into a **living digital twin of your crop**. Every leaf transpiration, every soil moisture gradient, every solar watt — visualized, analyzed, and acted upon in real-time.

```
┌─────────────────────────────────────────────────────┐
│  ☀️ Solar Panel  →  ⚡ INA219  →  📡 LoRa / MQTT     │
│  🌱 Soil Probe   →  Capacitive  →     ↕              │
│  🌡️ DHT22        →  Temp/Humid  →  🖥️ DASHBOARD     │
│  💧 Irrigation   ←  Relay       ←  WebSocket         │
└─────────────────────────────────────────────────────┘
```

---

## 🚀 Next-Gen Capabilities

### 🧬 Multi-Provider AI Crop Diagnostics
Snap a photo of your plant — the system instantly analyzes leaf morphology, detects early stress patterns, and prescribes remedial actions. No PhD in agronomy required.

**Choose your AI engine:**
- ☁️ **Google Gemini 2.5 Flash** — cloud vision API, zero setup
- 🌐 **OpenRouter** — unified gateway to 200+ models (Claude, GPT, Gemini, etc.)
- 🏠 **Ollama** — fully local, run Llama 3 / Mistral on your own hardware
- 🔌 **NVIDIA NVCF** — enterprise-grade inference

### 🌿 Interactive Holographic 3D Plant
A procedurally-generated spinach plant rendered in real-time with:
- **Depth-sorted perspective projection** — true 3D with parallax
- **Live sensor node overlays** — soil moisture, temperature, humidity mapped to visual hotspots
- **Drag-to-rotate** — inspect from any angle with auto-rotation when idle
- **Holographic scanline animation** — sci-fi aesthetic meets functional visualization

### 📊 Real-Time Sensor Fusion
Live telemetry from your sensor mesh:
- **WebSocket push** — sub-second updates with zero polling
- **Multi-metric charts** — soil moisture, temperature, humidity, solar irradiance
- **Historical InfluxDB queries** — 24h, 7d, custom range analysis

### 💧 Smart Irrigation Control
Toggle irrigation remotely with visual feedback. The pump status, flow metrics, and soil response curves are displayed instantly.

### 🛡️ Military-Grade Security
- CSRF token protection on every mutation
- bcrypt-hashed credentials with session persistence
- All backend ports locked to loopback — only Caddy faces the internet

---

## 🎨 Design Philosophy

| Element | Technology |
|---------|-----------|
| UI Framework | Flutter Web (Dart) — pixel-perfect, 60fps |
| Design System | Glassmorphism + dark/light adaptive |
| 3D Engine | Custom CanvasKit painter — no WebGL dependency |
| Typography | Inter (Google Fonts) |
| Animations | Flutter animation controllers — buttery 60fps transitions |

Every card is a **GlassCard** — frosted glass effect with animated cyan-teal gradients that pulse with live telemetry data.

---

## 🏗️ Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────┐
│  ESP32 Node  │────▶│  MQTT Broker     │────▶│  InfluxDB   │
│  (LoRa + DHT)│     │  (EMQX Cloud)    │     │  (Timeseries)│
└──────────────┘     └──────────────────┘     └─────────────┘
                            │                        │
                            ▼                        ▼
                     ┌──────────────────────────────────┐
                     │  Node.js Express Gateway          │
                     │  • MQTT Subscriber                │
                     │  • WebSocket Broadcaster          │
                     │  • REST API                       │
                     │  • Gemini AI Integration          │
                     └──────────────────────────────────┘
                            │
                            ▼
                     ┌──────────────────────────────────┐
                     │  Flutter Web Dashboard            │
                     │  • 3D Plant Viewer                │
                     │  • Telemetry Charts (fl_chart)    │
                     │  • AI Diagnostics Panel           │
                     │  • Leaf Scanner (camera upload)   │
                     └──────────────────────────────────┘
```

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Flutter 3.x / Dart — compiled to WASM-ready JavaScript |
| **Backend** | Node.js 20 / Express — async I/O, WebSocket, MQTT client |
| **Database** | InfluxDB 2.7 — purpose-built time-series engine |
| **Messaging** | MQTT over EMQX — lightweight IoT protocol |
| **AI Engine** | Gemini 2.5 Flash / OpenRouter / Ollama / NVIDIA — switchable at runtime |
| **Container** | Podman / Docker — OCI-compatible, rootless |
| **Reverse Proxy** | Caddy — automatic HTTPS via Let's Encrypt |
| **Hardware** | ESP32 + LoRa + DHT22 + Capacitive Soil + INA219 |

---

## 🔌 API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Backend health check |
| `POST` | `/api/auth/login` | Authenticate session |
| `POST` | `/api/auth/logout` | Destroy session |
| `GET` | `/api/telemetry/live` | Latest sensor snapshot |
| `GET` | `/api/telemetry/history?range=24h` | Time-series query |
| `POST` | `/api/ai/diagnose` | Gemini-powered leaf analysis |
| `POST` | `/api/pump/toggle` | Remote irrigation control |
| `WS` | `/` | Real-time WebSocket telemetry stream |

---

---

## 🐳 Podman Build Details

Full end-to-end build pipeline, bundle contents, VPS deployment, frontend-only hot-redeploy, and pod architecture documented in:

➡️ **[PODMAN_BUILD.md](PODMAN_BUILD.md)**

---

## 🚀 Quick Start

```bash
# Start InfluxDB
podman run -d --name influxdb -p 127.0.0.1:8086:8086 \
  -e DOCKER_INFLUXDB_INIT_MODE=setup \
  -e DOCKER_INFLUXDB_INIT_USERNAME=admin \
  -e DOCKER_INFLUXDB_INIT_PASSWORD=adminpassword123 \
  -e DOCKER_INFLUXDB_INIT_ORG=college \
  -e DOCKER_INFLUXDB_INIT_BUCKET=solarsoil \
  -e DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=my-dev-token \
  docker.io/library/influxdb:2.7

# Start backend
cd backend && cp .env.example .env && npm install && npm start

# Start frontend (dev mode)
cd frontend && flutter pub get && flutter run -d chrome

# Simulate sensor data
cd lora && pip install paho-mqtt && python simulator.py
```

---

## 🌐 Production Deployment (Podman Pod)

```bash
# Build bundle locally
./instructions/build-bundle.ps1

# Deploy to VPS
scp -P 2222 solarsoil-pod-bundle.tar solarsoil-kube.yaml user@vps:/home/user/solar/

# On VPS
sudo podman load -i solarsoil-pod-bundle.tar
sudo podman kube play solarsoil-kube.yaml
sudo systemctl restart caddy
```

Zero-downtime, fully containerized, auto-start on boot.

---

## 🔐 Credentials

| Role | Username | Password |
|------|----------|----------|
| Admin | `username` | `password` |

*Change immediately in production using bcrypt.*

---

## 📡 Telemetry Schema

```json
{
  "temp": 28.0,       "soil": 42.0,
  "v": 5.2,           "humidity": 65.0,
  "current": 410.0
}
```

---

## 👨‍💻 Contributing

Fork → branch → commit → PR. All sensor protocols, UI enhancements, and AI pipeline improvements welcome.

---

## 📄 License

**Solar Soil IoT Dashboard** — Developed by **Ashlin Rockey**  
IoT & Precision Agriculture Project — **West Saxon University of Zwickau (WHZ)** — May 2026

*Built with curiosity, caffeine, and the conviction that the future of food grows on code.*  
*Open-source for academic and educational purposes.* 🌱☀️
