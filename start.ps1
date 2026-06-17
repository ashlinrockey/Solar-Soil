# Solar Soil IoT Dashboard - Full Stack Startup Script
# Starts: Podman VM + InfluxDB container + Node.js backend
# Usage: .\start.ps1

$ErrorActionPreference = "Continue"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Solar Soil IoT Dashboard - Starting Up" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# ── Step 1: Ensure Podman machine is running ──────────────────────────────────
Write-Host "`n[1/4] Starting Podman machine..." -ForegroundColor Yellow
$machineState = (podman machine list --format json 2>$null | ConvertFrom-Json)
if ($machineState -and $machineState[0].Running) {
    Write-Host "      Podman machine already running." -ForegroundColor Green
} else {
    podman machine start 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    Write-Host "      Podman machine started." -ForegroundColor Green
}

# ── Step 2: Keep the Podman WSL VM alive with a background sleep ─────────────
# WSL2 terminates idle VM instances. This hidden background process prevents that.
Write-Host "`n[2/4] Pinning Podman WSL VM to stay alive..." -ForegroundColor Yellow
$keepAliveJob = Start-Process -FilePath "wsl" `
    -ArgumentList "-d", "podman-machine-default", "-u", "user", "--", "sleep", "86400" `
    -WindowStyle Hidden -PassThru
Write-Host "      VM keep-alive process started (PID: $($keepAliveJob.Id))." -ForegroundColor Green
Start-Sleep -Seconds 2

# ── Step 3: Start InfluxDB container ──────────────────────────────────────────
Write-Host "`n[3/4] Starting InfluxDB container..." -ForegroundColor Yellow
$influxStatus = podman ps --filter "name=solarsoil_influxdb" --format "{{.Status}}" 2>&1
if ($influxStatus -match "^Up") {
    Write-Host "      InfluxDB already running: $influxStatus" -ForegroundColor Green
} else {
    $result = podman start solarsoil_influxdb 2>&1
    if ($LASTEXITCODE -eq 0) {
        Start-Sleep -Seconds 3
        # Verify it's actually up
        $health = Invoke-RestMethod -Uri "http://[::1]:8086/health" -ErrorAction SilentlyContinue
        if ($health.status -eq "pass") {
            Write-Host "      InfluxDB is up and healthy (v$($health.version))." -ForegroundColor Green
        } else {
            Write-Host "      InfluxDB started (health check pending)." -ForegroundColor Yellow
        }
    } else {
        Write-Host "      WARNING: Could not start InfluxDB: $result" -ForegroundColor Red
        Write-Host "      Run .\backend\run_db_podman.ps1 to create the container first." -ForegroundColor Red
    }
}

# ── Step 4: Start Node.js backend ─────────────────────────────────────────────
Write-Host "`n[4/4] Starting Node.js backend on port 5000..." -ForegroundColor Yellow
$backendPath = Join-Path $PSScriptRoot "backend"

# Check if port 5000 is already in use
$port5000 = netstat -ano | Select-String ":5000 " | Select-String "LISTENING"
if ($port5000) {
    Write-Host "      Port 5000 already in use. Server may already be running." -ForegroundColor Yellow
} else {
    Start-Process -FilePath "powershell" `
        -ArgumentList "-NoExit", "-Command", "cd '$backendPath'; npm start" `
        -WindowStyle Normal
    Start-Sleep -Seconds 3
    Write-Host "      Backend server launched in new window." -ForegroundColor Green
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  All services started!" -ForegroundColor Green
Write-Host "  Dashboard:  http://localhost:5000" -ForegroundColor White
Write-Host "  InfluxDB:   http://localhost:8086" -ForegroundColor White
Write-Host "  Login:      username / password" -ForegroundColor White
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "`nNote: The VM keep-alive job will run until this window is closed." -ForegroundColor Gray
Write-Host "Press Ctrl+C to stop the keep-alive (containers will keep running)." -ForegroundColor Gray

# Keep the VM alive by waiting (the sleep 86400 inside WSL handles the actual pinning)
Write-Host "`nMonitoring... (Ctrl+C to exit)" -ForegroundColor Gray
try {
    while ($true) {
        Start-Sleep -Seconds 30
        # Re-check and restart keep-alive if WSL VM stopped
        $vmState = wsl -l -v 2>&1 | Select-String "podman-machine-default"
        if ($vmState -notmatch "Running") {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') VM stopped — restarting keep-alive..." -ForegroundColor Yellow
            podman machine start 2>&1 | Out-Null
            Start-Sleep -Seconds 3
            Start-Process -FilePath "wsl" `
                -ArgumentList "-d", "podman-machine-default", "-u", "user", "--", "sleep", "86400" `
                -WindowStyle Hidden
        }
    }
} catch {
    Write-Host "`nKeep-alive stopped. Containers will continue running." -ForegroundColor Gray
}
