# Resolve podman executable path dynamically (handles environment variable lag on new installs)
$podmanCmd = "podman"
if (-not (Get-Command "podman" -ErrorAction SilentlyContinue)) {
    $fallbackPath = "C:\Program Files\RedHat\Podman\podman.exe"
    if (Test-Path $fallbackPath) {
        $podmanCmd = $fallbackPath
    }
}

Write-Host "Using Podman CLI path: $podmanCmd" -ForegroundColor Gray

# Create persistent Podman volumes if they do not already exist
& $podmanCmd volume create influxdb-data
& $podmanCmd volume create influxdb-config

# Run InfluxDB 2.7 Container using Podman CLI (drop-in Docker replacement)
& $podmanCmd run -d `
  --name solarsoil_influxdb `
  -p 8086:8086 `
  -v influxdb-data:/var/lib/influxdb2 `
  -v influxdb-config:/etc/influxdb2 `
  -e DOCKER_INFLUXDB_INIT_MODE=setup `
  -e DOCKER_INFLUXDB_INIT_USERNAME=admin `
  -e DOCKER_INFLUXDB_INIT_PASSWORD=adminpassword123 `
  -e DOCKER_INFLUXDB_INIT_ORG=college `
  -e DOCKER_INFLUXDB_INIT_BUCKET=solarsoil `
  -e DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=solarsoil_secret_token_12345 `
  --restart unless-stopped `
  influxdb:2.7

Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "InfluxDB has been deployed on http://localhost:8086 via Podman!" -ForegroundColor Green
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
