# 🐳 Podman Build & Deploy Guide

## 🔨 Local Build Pipeline

```powershell
# 1. Build Flutter Web
cd frontend
puro flutter build web --release --no-tree-shake-icons --base-href=/dashboard/

# 2. Build App Container Image
cd ..
podman build --no-cache -t localhost/solarsoil-app:latest -f Dockerfile .

# 3. Pull InfluxDB
podman pull docker.io/library/influxdb:2.7

# 4. Save Pod Bundle (single tar for offline deploy)
podman save -o instructions/solarsoil-pod-bundle.tar `
  localhost/solarsoil-app:latest `
  docker.io/library/influxdb:2.7
```

## 📦 Bundle Contents

| Image | Source | Size |
|-------|--------|------|
| `localhost/solarsoil-app:latest` | Built locally via `Dockerfile` | ~180 MB |
| `docker.io/library/influxdb:2.7` | Official InfluxDB image | ~410 MB |
| **Total** | | **~590 MB** |

## 🚀 Deploy to VPS

```bash
# Upload bundle + kube config
scp -P 2222 instructions/solarsoil-pod-bundle.tar sysadmin@<VPS_IP>:/home/sysadmin/solar/
scp -P 2222 backend/solarsoil-kube.yaml sysadmin@<VPS_IP>:/home/sysadmin/solar/

# SSH into VPS
ssh -p 2222 sysadmin@<VPS_IP>

# Load images
sudo podman load -i /home/sysadmin/solar/solarsoil-pod-bundle.tar

# Deploy pod
sudo podman pod rm -f solarsoil-pod   # clean up previous
sudo podman kube play /home/sysadmin/solar/backend/solarsoil-kube.yaml

# Restart reverse proxy
sudo systemctl restart caddy
```

## ⚡ Quick Redeploy (frontend-only change)

```bash
# Rebuild Flutter
cd frontend && puro flutter build web --release --no-tree-shake-icons --base-href=/dashboard/

# SCP updated web build
scp -P 2222 -r build/web sysadmin@<VPS_IP>:/home/sysadmin/solar/web-new

# On VPS — hot-replace assets in running container (no restart needed)
sudo podman exec solarsoil-app rm -rf /app/frontend/build/web
sudo podman cp /home/sysadmin/solar/web-new/. solarsoil-app:/app/frontend/build/web/
sudo podman cp /home/sysadmin/solar/web-new/index.html solarsoil-app:/app/index.html
rm -rf /home/sysadmin/solar/web-new
```

## 🐙 Pod Structure

The `solarsoil-kube.yaml` defines a single pod with two containers:

```
┌──────────────────────────────────┐
│         solarsoil-pod            │
│  ┌────────────┐  ┌────────────┐  │
│  │ InfluxDB   │  │ App        │  │
│  │ :8086      │  │ :5000      │  │
│  └────────────┘  └────────────┘  │
│         │              │         │
│         └──────┬───────┘         │
│                ▼                 │
│          localhost:5000          │
│                │                 │
└────────────────┼─────────────────┘
                 ▼
          Caddy Reverse Proxy
          (HTTPS :443 → :5000)
```

## 🗂️ Related Files

| File | Purpose |
|------|---------|
| `Dockerfile` | App container image definition |
| `backend/solarsoil-kube.yaml` | Podman Kube Play descriptor |
| `instructions/build-bundle.ps1` | Automated bundle builder |
| `instructions/deploy_vps_podman.sh` | Full VPS deploy automation |
