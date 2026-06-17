#!/usr/bin/env bash
set -e

# ================================================================
#  Solar Soil IoT Dashboard — Lightweight Ubuntu Setup Script
#  Stack     : Podman + InfluxDB 2.7 + Node.js 20 + PM2 + Caddy
# ================================================================

DOMAIN=$1
if [ -z "$DOMAIN" ]; then
    echo "Usage: ./setup-ubuntu.sh yourdomain.com"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "[!] This script must be run as root. Use: sudo ./setup-ubuntu.sh <domain>"
  exit 1
fi

cd /var/www/solarsoil-app

# 1. Generate secure InfluxDB token
INFLUX_TOKEN=$(openssl rand -hex 48)

echo "=== 1. Installing Podman & Starting InfluxDB (Secured) ==="
apt update && apt install -y podman curl gnupg gnupg2 apt-transport-https ca-certificates

podman rm -f influxdb-production 2>/dev/null || true
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

# Wait for InfluxDB to start up
echo -n "Waiting for InfluxDB to initialize"
for i in {1..10}; do
  if curl -s http://localhost:8086/health | grep -q '"status":"pass"'; then
    echo " ✓"
    break
  fi
  echo -n "."
  sleep 2
done

# Enable systemd autostart for InfluxDB
podman generate systemd --name influxdb-production --restart-policy=always \
  > /etc/systemd/system/container-influxdb.service
systemctl daemon-reload
systemctl enable container-influxdb.service

echo "=== 2. Installing Node.js 20 & PM2 ==="
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
fi
npm install pm2 -g

echo "=== 3. Configuring Production Environment & Starting Backend ==="
cat > backend/.env <<EOT
PORT=5000
INFLUX_URL=http://localhost:8086
INFLUX_TOKEN=$INFLUX_TOKEN
INFLUX_ORG=college
INFLUX_BUCKET=solarsoil
MQTT_BROKER=mqtt://broker.emqx.io:1883
MQTT_TOPIC=solarsoil/nodeA
NODE_ENV=production
EOT
chmod 600 backend/.env

cd backend
npm ci --only=production
pm2 delete solarsoil-backend 2>/dev/null || true
pm2 start server.js --name "solarsoil-backend" --env production
pm2 save
env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root
pm2 save
cd ..

echo "=== 4. Verifying Flutter Web Static Assets ==="
if [ -d "frontend/build/web" ]; then
    echo "  [✓] Flutter web static build found."
else
    echo "  [!] WARNING: frontend/build/web not found. Please compile and transfer assets!"
fi

echo "=== 5. Installing & Configuring Caddy HTTPS Proxy ==="
if ! command -v caddy &>/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | \
    gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | \
    tee /etc/apt/sources.list.d/caddy-stable.list
  apt update
  apt install caddy -y
fi

cat > /etc/caddy/Caddyfile <<EOT
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
}
EOT

systemctl restart caddy
systemctl enable caddy

# Save credentials
cat > /root/solarsoil-credentials.txt <<EOT
======================================================
  Solar Soil IoT Dashboard — Deployment Credentials
======================================================
Domain       : https://$DOMAIN
InfluxDB Org : college
InfluxDB Bucket: solarsoil
InfluxDB Token : $INFLUX_TOKEN
Default Auth : username / password (auto-seeded)
======================================================
EOT
chmod 600 /root/solarsoil-credentials.txt

echo ""
echo "======================================================="
echo "  🎉 SETUP SUCCESSFUL!"
echo "  Backend is active on http://localhost:5000"
echo "  InfluxDB (secured local bind) is on http://localhost:8086"
echo "  Caddy reverse proxy configured for HTTPS on: https://$DOMAIN"
echo "  Credentials file: /root/solarsoil-credentials.txt"
echo "======================================================="
echo ""
