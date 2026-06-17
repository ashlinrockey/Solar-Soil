# Solar Soil IoT Dashboard — Ubuntu Server Production Deployment Guide

> **Architecture**: Fully Containerized Podman Pod (Node.js API/WebSocket Gateway + InfluxDB 2.7) + Caddy reverse proxy with automatic HTTPS  
> **Target OS**: IONOS VPS — Ubuntu Server (22.04 LTS or 24.04 LTS)  
> **Method**: Direct image compilation and archiving via Podman Pods for flawless host isolation and security.

---

## Architecture Overview

Instead of polluting your production host with node modules, specific Node runtimes, and process managers like PM2, this deployment utilizes **Podman's native Kubernetes-style Pods**.

```mermaid
graph TD
    subgraph Host ["IONOS Ubuntu VPS Host"]
        Caddy["Caddy Web Server (Port 80 / 443)"]
        
        subgraph Pod ["Podman Pod (solarsoil-pod)"]
            App["Solar Soil App Container (Port 5000)"]
            Influx["InfluxDB Container (Port 8086)"]
        end
    end
    
    Internet(["Internet Traffic"]) -->|HTTPS:443| Caddy
    Caddy -->|Reverse Proxy| App
    App <-->|localhost:8086 (Isolated inside Pod)| Influx
```

- **Security**: Port `8086` (InfluxDB) is *never* exposed to the host machine or public internet. It remains internal to the pod's network namespace.
- **Port 5000**: Exposed only to the local loopback interface (`127.0.0.1:5000`) so that only Caddy can reverse proxy to it.
- **Auto-Start**: Native `systemd` handles starting and restarting the pod and its constituent containers automatically on boot or failure.

---

## Part 1 — Local Preparation (Windows Machine)

Always build your assets and compile containers on your local workstation. Attempting builds on low-RAM VPS servers can lead to resource exhaustion and server hangs.

### Step 1.1 — Build the Flutter Web Assets
```powershell
# 1. Navigate to the frontend directory
cd c:\axxo\college\ui\frontend

# 2. Compile the production web release
puro flutter build web --release

# 3. Verify output files
dir build\web\
```

### Step 1.2 — Build the Production Podman Image
Build the container image which packages the Node.js API Gateway, `authService`, and the precompiled Flutter Web static assets:

```powershell
# 1. Return to the root folder
cd c:\axxo\college\ui

# 2. Build the Podman image
podman build -t solarsoil-app:latest .
```

### Step 1.3 — Export the Image to a Tar Archive
Create a portable backup tarball of the image to easily transfer it to the VPS:

```powershell
podman save -o solarsoil-app-backup.tar localhost/solarsoil-app:latest
```
*This generates a `solarsoil-app-backup.tar` (~254MB) in your root directory.*

### Step 1.4 — Upload to the Ubuntu VPS
Use SCP (using uppercase `-P` for custom port if you configured one) to upload the tarball to your home directory:

```powershell
# Replace [PORT] and [VPS_IP] with your actual server configuration
scp -P [PORT] solarsoil-app-backup.tar root@[VPS_IP]:/root/
```

---

## Part 2 — VPS Initialization (SSH into VPS)

SSH into your Ubuntu server to set up the container runtime and reverse proxy.

```powershell
ssh -p [PORT] root@[VPS_IP]
```

### Step 2.1 — Install Caddy and Podman
Execute the following to update your server and install the stack:

```bash
# 1. Update APT packages
apt update && apt upgrade -y
apt install -y curl gnupg2 apt-transport-https ca-certificates

# 2. Install Podman
apt install -y podman

# 3. Install Caddy stable repository and package
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | \
  gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | \
  tee /etc/apt/sources.list.d/caddy-stable.list

apt update && apt install caddy -y
```

### Step 2.2 — Load the App Image
Import the precompiled dashboard image into your local Podman repository:

```bash
podman load -i /root/solarsoil-app-backup.tar

# Verify the image is present
podman images
# Should list: localhost/solarsoil-app  latest
```

---

## Part 3 — Run the Podman Pod

### Step 3.1 — Setup the Automated Deployment Script
We have created a helper script [deploy_vps_podman.sh](file:///c:/axxo/college/ui/instructions/deploy_vps_podman.sh) that automates the pod setup, generates systemd services, and configures Caddy. 

You can upload or run it directly on the server. If doing it manually, follow the step-by-step breakdown below:

```bash
# Generate a strong admin token for InfluxDB
INFLUX_TOKEN=$(openssl rand -hex 48)

# 1. Create the Podman Pod (forwarding 127.0.0.1:5000)
podman pod create --name solarsoil-pod -p 127.0.0.1:5000:5000

# 2. Run InfluxDB 2.7 in the Pod
podman run -d \
  --pod solarsoil-pod \
  --name solarsoil-influxdb \
  --restart unless-stopped \
  -v solarsoil-influxdb-data:/var/lib/influxdb2:Z \
  -v solarsoil-influxdb-config:/etc/influxdb2:Z \
  -e DOCKER_INFLUXDB_INIT_MODE=setup \
  -e DOCKER_INFLUXDB_INIT_USERNAME=admin \
  -e DOCKER_INFLUXDB_INIT_PASSWORD=adminpassword123 \
  -e DOCKER_INFLUXDB_INIT_ORG=college \
  -e DOCKER_INFLUXDB_INIT_BUCKET=solarsoil \
  -e "DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=$INFLUX_TOKEN" \
  influxdb:2.7

# 3. Run the App Container in the Pod
podman run -d \
  --pod solarsoil-pod \
  --name solarsoil-app \
  --restart unless-stopped \
  -e NODE_ENV=production \
  -e PORT=5000 \
  -e INFLUX_URL=http://localhost:8086 \
  -e "INFLUX_TOKEN=$INFLUX_TOKEN" \
  -e INFLUX_ORG=college \
  -e INFLUX_BUCKET=solarsoil \
  -e MQTT_BROKER=mqtt://broker.emqx.io:1883 \
  -e MQTT_TOPIC=solarsoil/nodeA \
  localhost/solarsoil-app:latest
```

---

## Part 4 — Systemd Integration (Auto-Start)

Podman can generate standard `systemd` files for pods so they are integrated directly into the OS lifecycle.

```bash
# 1. Navigate to the systemd directory
cd /etc/systemd/system/

# 2. Generate the unit files (--new creates clean dynamic units)
podman generate systemd --files --name solarsoil-pod --new

# 3. Reload systemd daemon
systemctl daemon-reload

# 4. Enable and start the pod service
systemctl enable --now pod-solarsoil-pod.service
```

*This will automatically load, execute, and monitor the dependent container services (`container-solarsoil-influxdb.service` and `container-solarsoil-app.service`).*

---

## Part 5 — Configure Caddy HTTPS Reverse Proxy

Configure Caddy to reverse proxy your domain with automatic Let's Encrypt SSL and full WebSocket upgrade support.

```bash
# 1. Edit the Caddyfile
cat > /etc/caddy/Caddyfile << 'EOF'
solar.yourdomain.com {
    # Proxy to Node.js inside Podman Pod
    reverse_proxy localhost:5000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

    encode gzip

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
    }

    log {
        output file /var/log/caddy/solarsoil-access.log
        format json
    }
}
EOF

# 2. Validate Caddyfile and reload
caddy validate --config /etc/caddy/Caddyfile
systemctl restart caddy
```

---

## Part 6 — Management & Diagnostics

Because everything is containerized, administration is incredibly clean:

### Pod and Container Health Checks
```bash
# Check status of the Pod
podman pod ps

# Check status of all containers
podman ps

# View Node.js logs in real-time
podman logs -f solarsoil-app

# View InfluxDB logs in real-time
podman logs -f solarsoil-influxdb
```

### Systemd Lifecycle Management
```bash
# Stop the entire stack
systemctl stop pod-solarsoil-pod.service

# Start the entire stack
systemctl start pod-solarsoil-pod.service

# Check systemd status
systemctl status pod-solarsoil-pod.service
```

### Quick Reference — Troubleshoot Checklist
- **Caddy returns a 502**: Ensure the pod is active (`podman pod ps`) and port 5000 is open in the pod definition.
- **WebSocket connection drops**: Double check Caddy reverse proxy headers. Caddy's websocket upgrade is automatic, but headers help pass accurate client IP addresses to the Express gateway.
- **History not showing**: InfluxDB token might be mismatched. Run `cat /root/solarsoil-credentials.txt` to verify credentials.

---

*Guide version: May 2026 | Ubuntu Server deployment with Podman Pods & Caddy*
