# =================================================================
#  Solar Soil IoT Dashboard - Local Full Pod Bundle Builder
#  Target Platform : Windows (PowerShell)
#  Actions         : Builds App -> Pulls InfluxDB 2.7 -> Archives BOTH to a Single Tar
# =================================================================

$ErrorActionPreference = "Stop"

# Clear screen and display banner
Clear-Host
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "    📦 SOLAR SOIL IOT DASHBOARD - POD BUNDLE BUILDER"
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# Define paths relative to this script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir "..\.."))
$FrontendDir = Join-Path $ProjectRoot "frontend"
$Dockerfile = Join-Path $ProjectRoot "Dockerfile"
$OutputFile = Join-Path $ScriptDir "solarsoil-pod-bundle.tar"

Write-Host "Project Root : $ProjectRoot" -ForegroundColor Yellow
Write-Host "Output Bundle: $OutputFile" -ForegroundColor Yellow
Write-Host ""

# -----------------------------------------------------------------
# 1. Compile Flutter Web Assets
# -----------------------------------------------------------------
Write-Host "=== [Step 1/4] Compiling Flutter Web Assets ===" -ForegroundColor Green

# Determine whether to use 'puro' or standard 'flutter'
$FlutterCmd = "flutter"
if (Get-Command "puro" -ErrorAction SilentlyContinue) {
    Write-Host "  Puro detected! Using puro engine manager." -ForegroundColor Gray
    $FlutterCmd = "puro"
}

# Run Flutter/Puro build web
Push-Location $FrontendDir
try {
    Write-Host "  Running: $FlutterCmd flutter build web --release"
    if ($FlutterCmd -eq "puro") {
        & puro flutter build web --release
    } else {
        & flutter build web --release
    }
    Write-Host "  [OK] Flutter Web assets compiled successfully." -ForegroundColor Green
} catch {
    Write-Host "  [!] Error: Flutter compilation failed!" -ForegroundColor Red
    Pop-Location
    Exit 1
}
Pop-Location
Write-Host ""

# -----------------------------------------------------------------
# 2. Build App Container Image
# -----------------------------------------------------------------
Write-Host "=== [Step 2/4] Building App Container Image ===" -ForegroundColor Green

if (-not (Get-Command "podman" -ErrorAction SilentlyContinue)) {
    Write-Host "  [!] Error: Podman CLI is not installed or not in your PATH!" -ForegroundColor Red
    Exit 1
}

# Check if Podman machine is running
$MachineStatus = & podman machine list 2>$null | Out-String
if ($MachineStatus) {
    Write-Host "  Podman Machines:" -ForegroundColor Gray
    Write-Host "  $MachineStatus" -ForegroundColor Gray
}

try {
    Write-Host "  Running: podman build -t localhost/solarsoil-app:latest -f $Dockerfile $ProjectRoot"
    & podman build -t localhost/solarsoil-app:latest -f $Dockerfile $ProjectRoot
    Write-Host "  [OK] App container image built successfully." -ForegroundColor Green
} catch {
    Write-Host "  [!] Error: Podman build failed!" -ForegroundColor Red
    Exit 1
}
Write-Host ""

# -----------------------------------------------------------------
# 3. Cache / Pull Official InfluxDB 2.7 Image Locally
# -----------------------------------------------------------------
Write-Host "=== [Step 3/4] Pulling Official InfluxDB 2.7 Image Locally ===" -ForegroundColor Green
try {
    Write-Host "  Running: podman pull docker.io/library/influxdb:2.7"
    & podman pull docker.io/library/influxdb:2.7
    Write-Host "  [OK] InfluxDB 2.7 pulled successfully." -ForegroundColor Green
} catch {
    Write-Host "  [!] Error: Failed to pull InfluxDB image!" -ForegroundColor Red
    Exit 1
}
Write-Host ""

# -----------------------------------------------------------------
# 4. Save Both Images to a Single Tar Archive
# -----------------------------------------------------------------
Write-Host "=== [Step 4/4] Archiving Both Images to Single Tar ===" -ForegroundColor Green

try {
    if (Test-Path $OutputFile) {
        Write-Host "  Removing existing tar bundle..." -ForegroundColor Gray
        Remove-Item $OutputFile -Force
    }
    
    Write-Host "  Saving: localhost/solarsoil-app:latest AND docker.io/library/influxdb:2.7"
    & podman save -o $OutputFile localhost/solarsoil-app:latest docker.io/library/influxdb:2.7
    
    $FileSizeMB = [Math]::Round(((Get-Item $OutputFile).Length / 1MB), 2)
    Write-Host ("  [OK] Multi-image tar bundle created successfully (" + $FileSizeMB + " MB).") -ForegroundColor Green
} catch {
    Write-Host "  [!] Error: Image bundle export failed!" -ForegroundColor Red
    Exit 1
}
Write-Host ""

# -----------------------------------------------------------------
# Success Summary
# -----------------------------------------------------------------
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "     🎉 FULL POD BUNDLE BUILD COMPLETE!"
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Included Images: 1. localhost/solarsoil-app:latest" -ForegroundColor Green
Write-Host "                   2. docker.io/library/influxdb:2.7" -ForegroundColor Green
Write-Host "  Archive Path   : $OutputFile" -ForegroundColor Green
Write-Host ("  File Size      : " + $FileSizeMB + " MB") -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  To transfer to server: scp -P [PORT] `"$OutputFile`" root@[VPS_IP]:/root/" -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""
