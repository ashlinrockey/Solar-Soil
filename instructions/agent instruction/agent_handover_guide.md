# AI Agent Handover Guide: Solar Soil IoT Dashboard

> **Welcome, Agent!** This document serves as your operational blueprint to take over, understand, and safely develop the **Solar Soil IoT Dashboard** system.
> Read this file in full before editing the codebase. It details the system architecture, component dependencies, key environment configurations, compilation procedures, and recent developmental fixes.

---

## 1. Project Overview

The **Solar Soil IoT Dashboard** is a smart telemetry system designed to ingest, persistent-store, and visualize real-time agricultural metrics (temperature, soil moisture, battery voltage, relative humidity, and current draw) received from ESP32 LoRa field nodes.

```
[ ESP32 Field Nodes ] --(LoRa)--> [ Gateway Node ]
                                         │ (WiFi / MQTT)
                                         ▼
                               [ EMQX Public Broker ]
                                         │
                                         ▼
                            [ Node.js API Gateway ] <==(WS/HTTP)==> [ Flutter Web UI ]
                                    │
                                    ▼
                             [ InfluxDB 2.7 ]
```

---

## 2. Technical Stack & Directories

The repository is structured into two main sub-projects and a set of operational instructions:

```
c:\axxo\college\ui\
├── backend/                  # Node.js API & Gateway
│   ├── server.js             # Core App & Websocket/MQTT loop
│   ├── authService.js        # User authentication (Lowdb + bcryptjs)
│   ├── influxService.js      # InfluxDB telemetry read/write client
│   ├── users.db.json         # Lowdb active JSON database
│   └── package.json          # Express, WS, MQTT, InfluxDB clients
├── frontend/                 # Flutter Web UI
│   ├── lib/
│   │   ├── main.dart         # App bootstrap & routing
│   │   ├── providers/        # State Management (Provider package)
│   │   │   └── telemetry_provider.dart  # WebSocket & API bridge
│   │   └── screens/          # Screen widgets
│   │       ├── login_screen.dart
│   │       ├── dashboard_screen.dart
│   │       └── spinach_garden_detail_screen.dart (3D 3-tier visuals)
│   └── pubspec.yaml          # Flutter dependencies
├── instructions/             # Deployment & Admin manuals
│   ├── agent instruction/    # You are here!
│   ├── ionos_production_deploy.md # Caddy + Podman Pod setup
│   └── deploy_vps_podman.sh  # Automated VPS installer
└── Dockerfile                # Production single-stage build definition
```

---

## 3. Core Component Deep Dive

### 3.1. Node.js Backend Gateway (`/backend`)
- **Server File**: `server.js` (written as a modern ES Module).
- **MQTT Listener**: Subscribes to the EMQX public broker at `mqtt://broker.emqx.io:1883` on topic `solarsoil/nodeA`. Incoming telemetry is parsed, cached, written to InfluxDB, and broadcasted to WebSocket clients.
- **WebSocket Gateway**: Serves active WebSockets on the same port at the root path (`/`). It broadcasts telemetries to the Flutter client instantly using the format: `{ type: 'telemetry', data: { ... } }`.
- **Database (Auth)**: Powered by `lowdb` (stored in `users.db.json`). Seeding is handled dynamically at startup in `authService.js` if the database is empty (creates default `username` with password `password`).
- **Database (Telemetry)**: Time-series metrics are persisted to InfluxDB 2.7. The service client is in `influxService.js`.

### 3.2. Flutter Web Frontend (`/frontend`)
- **State Management**: Orchestrated via `lib/providers/telemetry_provider.dart` using the `Provider` pattern.
- **Dynamic Networking**: Resolves connection strings dynamically using browser contexts to support local and production addresses flawlessly:
  - WebSocket uses `wss://` on HTTPS, falling back to `ws://`.
  - HTTP endpoints are determined by `Uri.base.host`.
- **Key Viewpoints**:
  - `login_screen.dart`: Custom styled panel for dashboard security.
  - `dashboard_screen.dart`: Visualizes real-time metrics with custom gauge progress arc widgets, interactive status indicators, and an interactive system log terminal showing websocket status.
  - `spinach_garden_detail_screen.dart`: A gorgeous sub-dashboard that simulates a interactive 3D spinach garden visualization with custom lighting, interactive nodes, and historical spline metrics charts.

---

## 4. Operational Commands & Tools

When pair programming or executing fixes, use these tools and guidelines:

### 4.1. Flutter Management (Local Development)
- This project uses **`puro`** (a highly optimized Flutter engine manager).
- To run commands, prefix with `puro` instead of raw `flutter` if puro is installed locally:
  ```powershell
  # Compile Web Assets
  cd c:\axxo\college\ui\frontend
  puro flutter build web --release
  ```

### 4.2. Running Backend (Local Development)
Ensure a local configuration is present inside `backend/.env` before launching:
```bash
cd c:\axxo\college\ui\backend
npm install
node server.js
```

### 4.3. Docker & Podman Builds
The project includes a single-stage production `Dockerfile` in the root folder.
```bash
# Build the container locally
podman build -t solarsoil-app:latest .

# Run the container locally (port 5000)
podman run -d -p 5000:5000 --name solarsoil localhost/solarsoil-app:latest
```

For multi-container orchestration, the project includes:
- `backend/docker-compose.yml`: For deploying the complete stack (InfluxDB + App) via Docker Compose or `podman-compose`.
- `backend/solarsoil-kube.yaml`: For native Kubernetes-style deployment on Podman (`podman play kube`).

*Refer to the complete GitHub & Compose Deployment guide in [github_and_compose_deploy.md](file:///c:/axxo/college/ui/instructions/github_and_compose_deploy.md) for full instructions on repository synchronization and compose commands.*

---

## 5. Security & Deployment Standards

This system is configured to run in production under **Podman Pods** and a **Caddy Reverse Proxy** on an **Ubuntu VPS**:
- InfluxDB is restricted to binding on the pod loopback network (`127.0.0.1:8086`), making it physically inaccessible from the internet.
- Node.js is bound to `127.0.0.1:5000`.
- Caddy provides absolute HTTPS/SSL coverage and routes incoming requests seamlessly (supporting WebSocket upgrades).
- Deployment scripting and systemd unit generation are pre-baked in `instructions/deploy_vps_podman.sh`.

---

## 6. Development Rules & Safeguards for Future Agents

When modifying this repository, you **MUST** adhere to the following rules:

1. **Do Not Poll WebSockets**: The Flutter client (`telemetry_provider.dart`) relies on true push notifications over WS. Never implement polling fallbacks that overwhelm the server.
2. **Bcrypt Security**: Never write unhashed password strings into the JSON database file (`users.db.json`). Let `authService.js` handle hashing and seeding.
3. **No Placeholders in UI**: If you design or refine widgets in the frontend, do not use visual placeholders. Keep the aesthetics extremely premium, utilising modern harmonious color themes, glassmorphism, responsive grids, and subtle animations.
4. **Preserve Dynamic Web URL Handlers**: When editing API integration patterns inside the frontend, do not hardcode local addresses like `localhost:5000`. Always respect and maintain the dynamic hostname resolver getters (`_baseHttpUrl` and `_baseWsUrl`) in `telemetry_provider.dart`.
5. **No Local Compilation on VPS**: Never direct users to compile Flutter builds or build massive Docker images directly on their low-RAM VPS instances. Instruct them to perform `puro flutter build` and `podman build` locally, and upload the container archive via SCP.

Good luck coding! Check `instructions/ionos_production_deploy.md` if you need detailed server network configuration context.
