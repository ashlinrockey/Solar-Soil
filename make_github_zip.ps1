# ================================================================
#  Solar Soil — GitHub Clean Zip Packager
#  Creates a clean solar-soil-github.zip excluding binaries,
#  secrets, node_modules, build artifacts, and IDE files.
# ================================================================

$ErrorActionPreference = "Stop"

$SourceDir = "C:\axxo\college\ui"
$OutputZip = "C:\axxo\college\ui\solar-soil-github.zip"

# Remove old zip
if (Test-Path $OutputZip) {
    Write-Host "  Removing existing zip..." -ForegroundColor Gray
    Remove-Item $OutputZip -Force
}

# Directories to completely skip
$ExcludeDirs = @(
    "node_modules",
    ".dart_tool",
    ".idea",
    "build",
    "production",
    ".pub-cache",
    ".pub"
)

# File name patterns to skip
$ExcludeFiles = @(
    "*.tar",
    "*.rar",
    "*.gz",
    "solar-soil-github.zip",
    "solar-source.zip",
    "solarsoil-github.zip",
    ".env",
    "analysis_output.txt",
    "solarsoil_dashboard.iml",
    ".puro.json",
    ".flutter-plugins-dependencies",
    ".flutter-plugins"
)

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "     SOLAR SOIL - GITHUB CLEAN ZIP PACKAGER" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Source : $SourceDir" -ForegroundColor Yellow
Write-Host "  Output : $OutputZip" -ForegroundColor Yellow
Write-Host ""

Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::Open($OutputZip, "Create")
$fileCount = 0

$allFiles = Get-ChildItem -Path $SourceDir -Recurse -File

foreach ($file in $allFiles) {
    $relPath = $file.FullName.Substring($SourceDir.Length + 1)
    
    # Check if any segment of the path is an excluded directory
    $skipDir = $false
    foreach ($ex in $ExcludeDirs) {
        if ($relPath -like "*\$ex\*" -or $relPath -like "$ex\*" -or $relPath -like "*\$ex") {
            $skipDir = $true
            break
        }
    }
    if ($skipDir) { continue }

    # Check if filename matches any excluded pattern
    $skipFile = $false
    foreach ($pat in $ExcludeFiles) {
        if ($file.Name -like $pat) {
            $skipFile = $true
            break
        }
    }
    if ($skipFile) { continue }

    # Add to zip using forward slashes for cross-platform compatibility
    $entryName = $relPath.Replace("\", "/")
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip, $file.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal
    ) | Out-Null
    $fileCount++
}

$zip.Dispose()

$sizeMB = [Math]::Round((Get-Item $OutputZip).Length / 1MB, 2)

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "     ZIP PACKAGE COMPLETE!" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ("  Files packed : " + $fileCount) -ForegroundColor Green
Write-Host ("  Output size  : " + $sizeMB + " MB") -ForegroundColor Green
Write-Host ("  Output file  : " + $OutputZip) -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""
