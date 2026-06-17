# Solar Soil IoT Dashboard — Podman Container Backup & Deployment Guide

This guide details how to build, archive, restore, and run the self-contained full-stack **Solar Soil IoT Dashboard** container using Podman.

---

## Prerequisites
Ensure that **Podman** is installed and running on your system.
* On Windows, if the Podman engine is offline, run:
  ```powershell
  podman machine start
  ```

---

## 1. Building the Container Image
The container packages the Node.js API gateway backend along with your pre-compiled Flutter web dashboard assets.

Run the following command from the project root directory (`c:\axxo\college\ui`):
```powershell
podman build -t solarsoil-app:latest .
```

*Note: The `.dockerignore` file in the root directory automatically filters out local folders like `node_modules` and `.dart_tool` to keep the container build extremely lightweight and fast.*

---

## 2. Exporting/Backing Up the Container Image
To create a portable `.tar` file that you can save to an external drive, upload to cloud storage, or share with other systems:

```powershell
podman save -o solarsoil-app-backup.tar localhost/solarsoil-app:latest
```

*This will generate a **`solarsoil-app-backup.tar`** file (~254 MB) in the folder.*

---

## 3. Importing/Restoring the Backup File
To restore the container on any other system or after a machine migration:

Copy the `solarsoil-app-backup.tar` file to the target machine and run:
```powershell
podman load -i solarsoil-app-backup.tar
```

Verify that the image has loaded successfully:
```powershell
podman images
```

---

## 4. Running the Dashboard Container
Once the image is loaded, start the container on port `5000`:

```powershell
podman run -d -p 5000:5000 --name solarsoil-dashboard localhost/solarsoil-app:latest
```

### Accessing the Dashboard
- **Web Frontend & API Server:** Open [http://localhost:5000](http://localhost:5000) in your browser.
- **WebSocket Gateway:** Operates automatically on `ws://localhost:5000`.

---

## 5. Container Management & Useful Commands

| Command | Purpose |
|---------|---------|
| `podman ps` | View all running containers |
| `podman logs -f solarsoil-dashboard` | Stream the container's application logs |
| `podman stop solarsoil-dashboard` | Stop the active container |
| `podman start solarsoil-dashboard` | Start the stopped container |
| `podman rm -f solarsoil-dashboard` | Force delete the container |
