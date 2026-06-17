#!/usr/bin/env bash

# ================================================================
#  Solar Soil IoT Dashboard — Automated VPS Deployment Script
#  Target OS : Ubuntu 22.04 LTS / 24.04 LTS (IONOS VPS)
#  Stack     : Podman + InfluxDB 2.7 + Node.js 20 + PM2 + Caddy
# ================================================================
# Usage:
#   chmod +x deploy_vps.sh
#   ./deploy_vps.sh solar.yourdomain.com
# ================================================================

set -e

# ----------------------------------------------------------------
# 0. Require root
# ----------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "[!] This script must be run as root. Use: sudo ./deploy_vps.sh <domain>"
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

# App directory — must match where you uploaded via SCP
APP_DIR="/var/www/solarsoil-app"
BACKEND_DIR="$APP_DIR/backend"
WEB_DIR="$APP_DIR/frontend/build/web"

# ----------------------------------------------------------------
# 2. Generate a strong InfluxDB token
# ----------------------------------------------------------------
INFLUX_TOKEN=$(openssl rand -hex 48)

clear
echo -e "\033[36m================================================================="
echo -e "     🚀 SOLAR SOIL IOT DASHBOARD — VPS DEPLOYMENT"
echo -e "=================================================================\033[0m"
echo -e "\033[32m  Domain   : $DOMAIN"
echo -e "  App Dir  : $APP_DIR"
echo -e "\033[0m"

# ----------------------------------------------------------------
# 3. System update
# ----------------------------------------------------------------
echo -e "\033[32m[1/9] Updating system packages...\033[0m"
apt update -qq && apt upgrade -y -qq
apt install -y -qq curl git build-essential gnupg2 apt-transport-https ca-certificates

# ----------------------------------------------------------------
# 4. Verify uploaded files exist
# ----------------------------------------------------------------
echo -e "\033[32m[2/9] Verifying uploaded project files...\033[0m"

if [ ! -d "$BACKEND_DIR" ]; then
  echo -e "\033[31m[!] Backend not found at $BACKEND_DIR. Upload your project first (see Step 1.3 in ionos_production_deploy.md).\033[0m"
  exit 1
fi

if [ ! -f "$BACKEND_DIR/server.js" ]; then
  echo -e "\033[31m[!] server.js missing from $BACKEND_DIR\033[0m"
  exit 1
fi

if [ ! -d "$WEB_DIR" ]; then
  echo -e "\033[33m[!] WARNING: Flutter web build not found at $WEB_DIR"
  echo -e "    The backend will start but the frontend will show a 404 until you upload it.\033[0m"
fi

if [ ! -f "$BACKEND_DIR/users.db.json" ]; then
  echo -e "\033[32m[i] users.db.json not found — the Node.js backend will automatically seed the default administrator credentials (username: 'username', password: 'password') on startup.\033[0m"
fi

# ----------------------------------------------------------------
# 5. Install Node.js 20 + PM2
# ----------------------------------------------------------------
echo -e "\033[32m[3/9] Installing Node.js 20 LTS...\033[0m"
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
  apt install -y -qq nodejs
fi
echo "  Node.js $(node --version), npm $(npm --version)"

echo -e "\033[32m[4/9] Installing PM2 process manager...\033[0m"
npm install pm2 -g -q

# ----------------------------------------------------------------
# 6. Install Podman + Start InfluxDB
# ----------------------------------------------------------------
echo -e "\033[32m[5/9] Installing Podman and starting InfluxDB 2.7...\033[0m"
if ! command -v podman &>/dev/null; then
  apt install -y -qq podman
fi

# Remove any stale container
podman rm -f influxdb-production 2>/dev/null || true

# Start InfluxDB with generated token
podman run -d \
  --name influxdb-production \
  -p 127.0.0.1:8086:8086 \
  --restart unless-stopped \
  -v influxdb-storage:/var/lib/influxdb2 \
  -v influxdb-config:/etc/influxdb2 \
  -e DOCKER_INFLUXDB_INIT_MODE=setup \
  -e DOCKER_INFLUXDB_INIT_USERNAME=admin \
  -e DOCKER_INFLUXDB_INIT_PASSWORD=adminpassword123 \
  -e DOCKER_INFLUXDB_INIT_ORG=college \
  -e DOCKER_INFLUXDB_INIT_BUCKET=solarsoil \
  -e "DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=$INFLUX_TOKEN" \
  influxdb:2.7

# Wait for InfluxDB to become ready
echo -n "  Waiting for InfluxDB to be ready"
for i in {1..15}; do
  if curl -s http://localhost:8086/health | grep -q '"status":"pass"'; then
    echo -e " ✓"
    break
  fi
  echo -n "."
  sleep 2
done

# Generate systemd auto-start unit
podman generate systemd --name influxdb-production --restart-policy=always \
  > /etc/systemd/system/container-influxdb.service
systemctl daemon-reload
systemctl enable container-influxdb.service

# ----------------------------------------------------------------
# 7. Write production .env
# ----------------------------------------------------------------
echo -e "\033[32m[6/9] Writing production environment configuration...\033[0m"

cat > "$BACKEND_DIR/.env" << EOF
PORT=5000
INFLUX_URL=http://localhost:8086
INFLUX_TOKEN=$INFLUX_TOKEN
INFLUX_ORG=college
INFLUX_BUCKET=solarsoil
MQTT_BROKER=mqtt://broker.emqx.io:1883
MQTT_TOPIC=solarsoil/nodeA
NODE_ENV=production
EOF

chmod 600 "$BACKEND_DIR/.env"
echo "  Production .env written and secured."

# ----------------------------------------------------------------
# 8. Install backend deps + launch with PM2
# ----------------------------------------------------------------
echo -e "\033[32m[7/9] Installing Node.js backend dependencies...\033[0m"
cd "$BACKEND_DIR"
npm ci --only=production

echo -e "\033[32m[8/9] Starting backend with PM2...\033[0m"
pm2 delete solarsoil-backend 2>/dev/null || true
pm2 start server.js --name "solarsoil-backend" --env production
pm2 save

# Configure PM2 to start on reboot
env PATH="$PATH:/usr/bin" pm2 startup systemd -u root --hp /root
pm2 save

# Verify backend health
sleep 3
if curl -sf http://localhost:5000/health > /dev/null; then
  echo "  Backend responding at http://localhost:5000 ✓"
else
  echo -e "\033[31m  [!] Backend health check failed — check: pm2 logs solarsoil-backend\033[0m"
fi

# ----------------------------------------------------------------
# 9. Install Caddy + Configure HTTPS Reverse Proxy
# ----------------------------------------------------------------
echo -e "\033[32m[9/9] Installing Caddy and configuring HTTPS reverse proxy...\033[0m"

if ! command -v caddy &>/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | \
    gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | \
    tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
  apt update -qq
  apt install caddy -y -qq
fi

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

caddy validate --config /etc/caddy/Caddyfile
systemctl restart caddy
systemctl enable caddy

# ----------------------------------------------------------------
# 10. Save deployed token to a reference file
# ----------------------------------------------------------------
cat > /root/solarsoil-credentials.txt << EOF
======================================================
  Solar Soil IoT Dashboard — Deployment Credentials
======================================================
Domain       : https://$DOMAIN
App Dir      : $APP_DIR
InfluxDB     : http://localhost:8086  (localhost only)
InfluxDB Org : college
InfluxDB Bucket: solarsoil
InfluxDB Token : $INFLUX_TOKEN

IMPORTANT: Keep this file secure. Delete after noting values.
======================================================
EOF
chmod 600 /root/solarsoil-credentials.txt

# ----------------------------------------------------------------
# 11. Print success summary
# ----------------------------------------------------------------
echo -e "\n\033[36m================================================================="
echo -e "     🎉 DEPLOYMENT COMPLETE!"
echo -e "=================================================================\033[0m"
echo -e "\033[32m"
echo -e "  🌐 Live URL     : https://$DOMAIN"
echo -e "  ⚙️  PM2 Status  : pm2 status"
echo -e "  📋 App Logs    : pm2 logs solarsoil-backend"
echo -e "  🗄️  InfluxDB    : podman ps"
echo -e "  🔐 Credentials : cat /root/solarsoil-credentials.txt"
echo -e "\033[0m"
echo -e "\033[33m  NOTE: SSL certificate may take 30-60 seconds to activate."
echo -e "  If the site shows 'Not Secure', wait a moment and refresh.\033[0m"
echo -e "\033[36m=================================================================\033[0m"
