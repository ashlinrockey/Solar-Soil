# Solar Soil — GitHub Upload & Containerized Deployment Manual

> **Scope**: Standardizing the Git workflow, securing secrets, uploading the codebase to **GitHub**, and orchestrating the multi-container production deployment using **Docker Compose** or native **Podman (via Podman Compose and Podman Kube Play)**.

---

## Part 1 — Preparing & Uploading to GitHub

To safely upload your project to GitHub, you must ensure that **secrets, credentials, local environment files, and large binary backup archives** are excluded. Uploading these is a major security risk and bloats your repository size.

### Step 1.1 — Create a Robust `.gitignore` File
Create a `.gitignore` file at the root of your project (`c:\axxo\college\ui\.gitignore`) to filter out temporary folders and binaries. 

Here is the production-grade `.gitignore` template for this project:

```gitignore
# --- IDEs & OS Files ---
.idea/
.vscode/
.DS_Store
Thumbs.db
*.log

# --- Large Database & Archive Backups (Crucial!) ---
*.tar
*.zip
*.rar
solarsoil-app-backup.tar
solarsoil-github.zip
solar2.tar
solartd.tar
yuga.tar

# --- Node.js Backend ---
backend/node_modules/
backend/users.db.json       # Exclude the actual local user DB
backend/.env                # Exclude local environmental secret tokens

# --- Flutter Frontend ---
frontend/.dart_tool/
frontend/.flutter-plugins
frontend/.flutter-plugins-dependencies
frontend/.packages
frontend/build/             # Exclude local Flutter compilation build outputs
frontend/pubspec.lock       # (Optional: keep if you want strict lock alignment)
```

### Step 1.2 — Initialize Git & Commit
Open PowerShell on your local Windows machine and run:

```powershell
# 1. Navigate to the project root
cd c:\axxo\college\ui

# 2. Initialize Git
git init

# 3. Add all files (Git will automatically respect your .gitignore)
git add .

# 4. Create the initial commit
git commit -m "feat: complete telemetry dashboard with secure Podman Pod deployment"
```

### Step 1.3 — Create Repository & Push to GitHub
1. Log in to [GitHub](https://github.com/) and click **New Repository**.
2. Name it (e.g., `solar-soil-iot`) and keep it **Private** (recommended since it's a college project).
3. Do **NOT** initialize it with a README, `.gitignore`, or license (since we already created them).
4. Run the following commands to link and upload your code:

```powershell
# Link your local folder to your remote GitHub repository
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/solar-soil-iot.git

# Set your default branch to main
git branch -M main

# Push the code
git push -u origin main
```

---

## Part 2 — Production Deployment via Git Pull (VPS)

Once your code is on GitHub, you no longer need to upload huge folders via SCP. You can simply clone the repository directly on your IONOS VPS:

```bash
# 1. SSH into the VPS
ssh -p [PORT] root@[VPS_IP]

# 2. Create the target app directory
mkdir -p /var/www/solarsoil-app
cd /var/www/

# 3. Clone the private repository
git clone https://github.com/YOUR_GITHUB_USERNAME/solar-soil-iot.git solarsoil-app

# 4. In the future, when you update local code and push to GitHub, update the VPS with:
cd /var/www/solarsoil-app
git pull origin main
```

> **Note**: For private repositories, authenticate using a **GitHub Personal Access Token (PAT)** or configure an **SSH Deploy Key** on the VPS.

---

## Part 3 — Containerized Deployment (Docker Compose & Podman)

This project has a production-ready `Dockerfile` at the root and a multi-container `backend/docker-compose.yml` that pulls together **InfluxDB** and your **Solar Soil Node.js/Flutter App**.

### Option A — Using Docker Compose (Standard Docker Engine)
If your VPS has the standard Docker Engine and Docker Compose installed:

```bash
cd /var/www/solarsoil-app/backend/

# 1. Create your production environment file (this is NOT uploaded to GitHub)
cat > .env << EOF
INFLUX_TOKEN=$(openssl rand -hex 48)
MQTT_BROKER=mqtt://broker.emqx.io:1883
MQTT_TOPIC=solarsoil/nodeA
EOF

# 2. Build the app container image locally on the VPS
docker compose build

# 3. Spin up the entire multi-container stack in the background
docker compose up -d

# 4. View active running services
docker compose ps
```

---

### Option B — Using Podman Compose (Podman Engine)
If your VPS is running **Podman** and you want to use the Docker Compose syntax, you can install **Podman Compose** (a python-based driver for podman):

```bash
# 1. Install Podman Compose on Ubuntu
apt update && apt install -y podman-compose

cd /var/www/solarsoil-app/backend/

# 2. Create the .env credentials file
cat > .env << EOF
INFLUX_TOKEN=$(openssl rand -hex 48)
MQTT_BROKER=mqtt://broker.emqx.io:1883
MQTT_TOPIC=solarsoil/nodeA
EOF

# 3. Run the stack using Podman Compose
podman-compose up -d

# 4. Verify containers
podman ps
```

---

### Option C — Native Podman Kube Play (Recommended for Podman)
Rather than relying on external tools like `podman-compose`, **Podman has native Kubernetes orchestration support built-in**. 

You can define your entire multi-container stack in a Kubernetes YAML file and deploy it instantly inside Podman using `podman play kube`!

We have pre-configured a native Kubernetes-style deployment file for your Podman stack:

#### 1. The Podman Kubernetes Descriptor (`solarsoil-kube.yaml`)
Create this file inside `/var/www/solarsoil-app/backend/solarsoil-kube.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: solarsoil-pod
spec:
  containers:
    # ----------------------------------------------------------
    # 1. InfluxDB Time-Series Database
    # ----------------------------------------------------------
    - name: solarsoil-influxdb
      image: docker.io/library/influxdb:2.7
      volumeMounts:
        - mountPath: /var/lib/influxdb2
          name: influxdb-data
        - mountPath: /etc/influxdb2
          name: influxdb-config
      env:
        - name: DOCKER_INFLUXDB_INIT_MODE
          value: "setup"
        - name: DOCKER_INFLUXDB_INIT_USERNAME
          value: "admin"
        - name: DOCKER_INFLUXDB_INIT_PASSWORD
          value: "adminpassword123"
        - name: DOCKER_INFLUXDB_INIT_ORG
          value: "college"
        - name: DOCKER_INFLUXDB_INIT_BUCKET
          value: "solarsoil"
        - name: DOCKER_INFLUXDB_INIT_ADMIN_TOKEN
          # Replace with your secure token or map via secret
          value: "solarsoil_secret_production_token_987654321"

    # ----------------------------------------------------------
    # 2. Solar Soil Dashboard App (Node.js + Flutter Web)
    # ----------------------------------------------------------
    - name: solarsoil-app
      image: localhost/solarsoil-app:latest
      env:
        - name: NODE_ENV
          value: "production"
        - name: PORT
          value: "5000"
        - name: INFLUX_URL
          value: "http://localhost:8086"
        - name: INFLUX_TOKEN
          value: "solarsoil_secret_production_token_987654321"
        - name: INFLUX_ORG
          value: "college"
        - name: INFLUX_BUCKET
          value: "solarsoil"
        - name: MQTT_BROKER
          value: "mqtt://broker.emqx.io:1883"
        - name: MQTT_TOPIC
          value: "solarsoil/nodeA"
      ports:
        - containerPort: 5000
          hostPort: 5000
          hostIP: 127.0.0.1

  # Persistent volumes declaration
  volumes:
    - name: influxdb-data
      hostPath:
        path: /var/lib/solarsoil/influxdb-data
        type: DirectoryOrCreate
    - name: influxdb-config
      hostPath:
        path: /etc/solarsoil/influxdb-config
        type: DirectoryOrCreate
```

#### 2. How to deploy using Kube Play on Podman:
To spin up this entire secure Kubernetes-style Podman deployment on your Ubuntu server in one command:

```bash
cd /var/www/solarsoil-app/backend/

# 1. Compile the app image locally
podman build -t solarsoil-app:latest -f ../Dockerfile ..

# 2. Run the Kubernetes definition file directly
podman play kube solarsoil-kube.yaml

# 3. Check running pods and active logs
podman pod ps
podman ps
podman logs -f solarsoil-pod-solarsoil-app
```

This is the absolute peak of modern container management under Podman! It matches Ubuntu Server, Caddy, and Podman perfectly, allowing you to use native system resources cleanly and securely.
