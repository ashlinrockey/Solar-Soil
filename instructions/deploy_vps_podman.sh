#!/usr/bin/env bash

# ================================================================
#  Solar Soil IoT Dashboard — Fully Containerized Podman Pod Deploy
#  Target OS : Ubuntu 22.04 LTS / 24.04 LTS (IONOS VPS)
#  Stack     : Podman Pods + InfluxDB 2.7 + Node.js 20 App + Caddy
# ================================================================

set -e

# ----------------------------------------------------------------
# 0. Require root
# ----------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[31m[!] This script must be run as root. Use: sudo ./deploy_vps_podman.sh <domain>\033[0m"
  exit 1
fi

# ----------------------------------------------------------------
# 1. Read domain argument
# ----------------------------------------------------------------
DOMAIN=$1
if [ -z "$DOMAIN" ]; then
  echo -e "\033[33m[?] Enter your domain (e.g. solar.yourdomain.com):\033[0m"
  read -r DOMAIN
fi

if [ -z "$DOMAIN" ]; then
  echo -e "\033[31m[!] Error: Domain name is required.\033[0m"
  exit 1
fi

clear
echo -e "\033[36m================================================================="
echo -e "     🚀 SOLAR SOIL IOT DASHBOARD — PODMAN POD DEPLOYMENT"
echo -e "=================================================================\033[0m"
echo -e "  Domain   : $DOMAIN"
echo -e "  OS       : Ubuntu Server"
echo -e "  Engine   : Podman (Fully Containerized)"
echo -e "\033[36m=================================================================\033[0m\n"

# ----------------------------------------------------------------
# 2. Update System Packages
# ----------------------------------------------------------------
echo -e "\033[32m[1/6] Updating system packages...\033[0m"
apt update -qq && apt upgrade -y -qq
apt install -y -qq curl gnupg2 apt-transport-https ca-certificates

# ----------------------------------------------------------------
# 3. Install Podman & Caddy
# ----------------------------------------------------------------
echo -e "\033[32m[2/6] Installing Podman and Caddy...\033[0m"

# Install Podman
if ! command -v podman &>/dev/null; then
  apt install -y -qq podman
fi
echo "  [✓] Podman version: $(podman --version)"

# Install Caddy
if ! command -v caddy &>/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | \
    gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | \
    tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
  apt update -qq
  apt install caddy -y -qq
fi
echo "  [✓] Caddy version: $(caddy version)"

# ----------------------------------------------------------------
# 4. Import / Load the Pre-compiled App Image
# ----------------------------------------------------------------
echo -e "\033[32m[3/6] Loading container images from tar archive...\033[0m"

# Look for pod-bundle first (contains both app and InfluxDB for offline setup)
BACKUP_TAR="/root/solarsoil-pod-bundle.tar"
if [ ! -f "$BACKUP_TAR" ] && [ -f "/var/www/solarsoil-app/solarsoil-pod-bundle.tar" ]; then
  BACKUP_TAR="/var/www/solarsoil-app/solarsoil-pod-bundle.tar"
fi

# Fallback to single app-backup image
if [ ! -f "$BACKUP_TAR" ]; then
  BACKUP_TAR="/root/solarsoil-app-backup.tar"
  if [ ! -f "$BACKUP_TAR" ] && [ -f "/var/www/solarsoil-app/solarsoil-app-backup.tar" ]; then
    BACKUP_TAR="/var/www/solarsoil-app/solarsoil-app-backup.tar"
  fi
fi

if [ -f "$BACKUP_TAR" ]; then
  echo "  Loading image(s) from $BACKUP_TAR..."
  podman load -i "$BACKUP_TAR"
else
  echo -e "\033[31m[!] Error: No image archive found! (Checked solarsoil-pod-bundle.tar and solarsoil-app-backup.tar at /root/ or app folder).\033[0m"
  echo "    Please compile locally, save the image archive, and SCP it to the server."
  exit 1
fi

# ----------------------------------------------------------------
# 5. Initialize the Secure Podman Pod
# ----------------------------------------------------------------
echo -e "\033[32m[4/6] Configuring isolated Podman Pod network...\033[0m"

# Generate secure random token for InfluxDB
INFLUX_TOKEN=$(openssl rand -hex 48)

# Tear down any existing pod
echo "  Cleaning up previous deployment..."
podman pod rm -f solarsoil-pod 2>/dev/null || true
podman rm -f solarsoil-influxdb solarsoil-app 2>/dev/null || true

# 1. Create the Pod
# We only expose Node's port 5000 to the loopback interface on the host (127.0.0.1)
podman pod create \
  --name solarsoil-pod \
  -p 127.0.0.1:5000:5000

# 2. Run InfluxDB 2.7 inside the Pod
echo "  Starting InfluxDB container inside the pod..."
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
  docker.io/library/influxdb:2.7

# Wait for InfluxDB to initialize
echo -n "  Waiting for InfluxDB database setup"
for i in {1..15}; do
  if podman exec solarsoil-influxdb curl -s http://localhost:8086/health | grep -q '"status":"pass"'; then
    echo " ✓"
    break
  fi
  echo -n "."
  sleep 2
done

# 3. Run the App Container inside the Pod
echo "  Starting Solar Soil backend + frontend container inside the pod..."
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

# ----------------------------------------------------------------
# 6. Configure Systemd Auto-Start
# ----------------------------------------------------------------
echo -e "\033[32m[5/6] Setting up systemd autostart services...\033[0m"

# Generate systemd files in the system systemd directory
cd /etc/systemd/system/
podman generate systemd --files --name solarsoil-pod --new

# Enable and start the generated pod systemd service
systemctl daemon-reload
systemctl enable --now pod-solarsoil-pod.service

# ----------------------------------------------------------------
# 7. Configure Caddy Reverse Proxy with SSL
# ----------------------------------------------------------------
echo -e "\033[32m[6/6] Writing Caddyfile reverse proxy configurations...\033[0m"

mkdir -p /var/log/caddy
chown caddy:caddy /var/log/caddy 2>/dev/null || true

cat > /etc/caddy/Caddyfile << EOF
$DOMAIN {
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

# Validate and reload Caddy
caddy validate --config /etc/caddy/Caddyfile
systemctl restart caddy
systemctl enable caddy

# ----------------------------------------------------------------
# 8. Save Credentials
# ----------------------------------------------------------------
cat > /root/solarsoil-credentials.txt << EOF
======================================================
  Solar Soil IoT Dashboard — Deployment Credentials
======================================================
Domain       : https://$DOMAIN
InfluxDB     : accessible via: podman exec -it solarsoil-influxdb influx
InfluxDB Org : college
InfluxDB Bucket: solarsoil
InfluxDB Token : $INFLUX_TOKEN
Default Auth : username / password (auto-seeded)
======================================================
EOF
chmod 600 /root/solarsoil-credentials.txt

# ----------------------------------------------------------------
# 9. Print success summary
# ----------------------------------------------------------------
echo -e "\n\033[36m================================================================="
echo -e "     🎉 CONTAINERIZED PODMAN DEPLOYMENT COMPLETE!"
echo -e "=================================================================\033[0m"
echo -e "\033[32m"
echo -e "  🌐 Live URL     : https://$DOMAIN"
echo -e "  📦 Pod Status   : podman pod ps"
echo -e "  ⚙️  Containers   : podman ps"
echo -e "  📋 App Logs    : podman logs -f solarsoil-app"
echo -e "  📋 DB Logs     : podman logs -f solarsoil-influxdb"
echo -e "  🔐 Credentials : cat /root/solarsoil-credentials.txt"
echo -e "\033[0m"
echo -e "\033[33m  NOTE: SSL certificate may take 30-60 seconds to activate.\033[0m"
echo -e "\033[36m=================================================================\033[0m"
