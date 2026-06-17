# 🌱 Solar Soil IoT Dashboard

A real-time IoT monitoring and control dashboard for a solar-powered agricultural sensor network. Built with **Flutter Web** (frontend) + **Node.js/Express** (backend) + **InfluxDB** (time-series database) + **MQTT** (sensor messaging).

---

## ✨ Features

- 📊 **Live Telemetry Dashboard** — Real-time charts and metric cards for soil moisture, air temperature, humidity, solar voltage and current
- 🌿 **Interactive 3D Plant View** — Drag-to-rotate 3D procedural spinach plant with live sensor node overlays (depth-sorted, auto-spin)
- 💧 **Remote Irrigation Control** — Toggle the water pump relay via WebSocket directly from the dashboard
- 🔐 **Authentication** — Login screen with bcrypt-verified credentials
- 📡 **MQTT Integration** — Subscribes to sensor payloads from ESP32 gateway nodes via EMQX public broker
- 🗄️ **InfluxDB History** — Time-series data persistence with historical chart support
- 🐳 **Container-Ready** — Fully Dockerized/Podman-compatible with production `Dockerfile` and compose files
- 📱 **Responsive** — Works on both desktop and mobile browsers

---

## 🗂️ Project Structure

```
solar-soil-iot/
├── backend/                  # Node.js Express backend
│   ├── server.js             # Main API + WebSocket + MQTT gateway
│   ├── influxService.js      # InfluxDB time-series read/write
│   ├── authService.js        # Login authentication (bcrypt)
│   ├── users.db.json         # Default user database (template)
│   ├── package.json          # Node.js dependencies
│   ├── docker-compose.yml    # Docker Compose stack (app + InfluxDB)
│   └── solarsoil-kube.yaml   # Native Podman Kube Play descriptor
│
├── frontend/                 # Flutter Web frontend
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── login_screen.dart
│   │   │   ├── dashboard_screen.dart
│   │   │   └── spinach_garden_detail_screen.dart
│   │   ├── providers/
│   │   │   └── telemetry_provider.dart
│   │   └── widgets/
│   │       ├── glass_card.dart
│   │       ├── metric_card.dart
│   │       ├── telemetry_chart.dart
│   │       └── terminal_monitor.dart
│   ├── pubspec.yaml
│   └── assets/
│
├── lora/                     # ESP32 firmware & testing tools
│   ├── node.ino              # Sensor node (DHT11, soil probe, LoRa TX)
│   ├── gateway.ino           # LoRa gateway → MQTT publisher
│   └── simulator.py          # Python MQTT simulator (no hardware needed)
│
├── instructions/             # Deployment guides
│   ├── deploy_vps_podman.sh  # Fully-automated Ubuntu VPS + Podman Pod deploy
│   ├── deploy_vps.sh         # Bare-metal Ubuntu deploy (PM2 + Podman InfluxDB)
│   ├── github_and_compose_deploy.md
│   └── ionos_production_deploy.md
│
├── Dockerfile                # Production single-stage container image
└── .dockerignore
```

---

## 🚀 Getting Started (Local Development)

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Flutter](https://flutter.dev) | ≥ 3.22 | Frontend framework |
| [Node.js](https://nodejs.org) | ≥ 20 LTS | Backend server |
| [Podman](https://podman.io) or [Docker](https://docker.com) | any | Run InfluxDB locally |

### 1. Start InfluxDB (Database)

```bash
# Using Podman
podman run -d \
  --name influxdb-dev \
  -p 127.0.0.1:8086:8086 \
  -e DOCKER_INFLUXDB_INIT_MODE=setup \
  -e DOCKER_INFLUXDB_INIT_USERNAME=admin \
  -e DOCKER_INFLUXDB_INIT_PASSWORD=adminpassword123 \
  -e DOCKER_INFLUXDB_INIT_ORG=college \
  -e DOCKER_INFLUXDB_INIT_BUCKET=solarsoil \
  -e DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=my-dev-token \
  docker.io/library/influxdb:2.7
```

### 2. Configure Backend

```bash
cd backend/

# Copy the example env and edit your token
cp .env.example .env

# Install dependencies
npm install

# Start the backend
npm start
# Server starts at: http://localhost:5000
```

### 3. Build & Run Flutter Frontend

```bash
cd frontend/

# Install Flutter packages
flutter pub get

# Run in Chrome (dev mode — hot reload works)
flutter run -d chrome
```

### 4. (Optional) Start Data Simulator

If you don't have physical ESP32 hardware, simulate sensor readings:

```bash
cd lora/
pip install paho-mqtt
python simulator.py
```

The simulator publishes random telemetry data to the MQTT topic `solarsoil/nodeA` every 5 seconds.

---

## 🐳 Production Deployment

### Option A — Fully Automated Podman Pod (Recommended)

Uses the pre-built offline bundle or pulls images from a registry. Run on your Ubuntu 22.04/24.04 VPS:

```bash
# 1. Upload the pod bundle to your server (built locally)
scp -P [PORT] solarsoil-pod-bundle.tar root@[VPS_IP]:/root/

# 2. Clone the repository
git clone https://github.com/YOUR_USERNAME/solar-soil-iot.git /var/www/solarsoil-app

# 3. Run the automated install script
cd /var/www/solarsoil-app/instructions/
sudo ./deploy_vps_podman.sh solar.yourdomain.com
```

This script automatically:
- Installs Podman & Caddy
- Loads the offline container images (no Docker Hub needed on VPS)
- Creates the `solarsoil-pod` (App + InfluxDB in one isolated pod)
- Configures systemd autostart + Caddy HTTPS reverse proxy with Let's Encrypt

### Option B — Docker Compose

```bash
cd backend/
cp .env.example .env  # Edit your INFLUX_TOKEN
docker compose up -d --build
```

---

## ⚙️ Environment Variables

Create a `backend/.env` file (never commit this file!):

```env
PORT=5000
INFLUX_URL=http://localhost:8086
INFLUX_TOKEN=your-influxdb-admin-token
INFLUX_ORG=college
INFLUX_BUCKET=solarsoil
MQTT_BROKER=mqtt://broker.emqx.io:1883
MQTT_TOPIC=solarsoil/nodeA
NODE_ENV=production
```

---

## 📡 Telemetry Data Model

```json
{
  "temp": 28.0,       // °C  — ambient temperature (DHT22)
  "soil": 42.0,       // %   — soil moisture (capacitive sensor)
  "v": 5.2,           // V   — solar panel voltage (INA219)
  "humidity": 65.0,   // %   — air humidity (DHT22)
  "current": 410.0    // mA  — solar panel current (INA219)
}
```

---

## 🔌 API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Backend health check |
| `POST` | `/api/auth/login` | Login with username/password |
| `GET` | `/api/telemetry/live` | Latest cached telemetry reading |
| `GET` | `/api/telemetry/history?range=24h` | Historical data from InfluxDB |
| `WS` | `/` | WebSocket — real-time telemetry broadcast |

---

## 📜 Default Login Credentials

| Username | Password |
|----------|----------|
| `username` | `password` |

> **Change these immediately in production!** Edit `backend/users.db.json` and hash your new password with bcrypt before deploying.

---

## 🤝 Contributing

1. **Fork** this repository
2. Create your feature branch: `git checkout -b feature/my-new-sensor`
3. Commit your changes: `git commit -m "feat: add pH sensor support"`
4. Push to your branch: `git push origin feature/my-new-sensor`
5. Open a **Pull Request** against `main`

---

## 📄 License

This project is for academic/educational purposes. Solar Soil IoT Dashboard — College Project, May 2026.
