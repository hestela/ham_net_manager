# Build Ham Net Manager Windows installer using Inno Setup
# Run this script from the project root on a Windows machine.
# NOTE: this app does not have a proper code signing cert at the moment, so if you build an exe for this project, you likely can only use it on your machines as antivirus software may generate false-positives.

param(
    [string]$InnoSetupPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$InstallerScript = Join-Path $ProjectRoot "windows\installer.iss"
$DistDir = Join-Path $ProjectRoot "dist"

# Read version from pubspec.yaml
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$VersionLine = Select-String -Path $PubspecPath -Pattern "^version:" | Select-Object -First 1
$Version = ($VersionLine.Line -split ":")[1].Trim() -replace "\+.*", ""

Write-Host "Building Ham Net Manager Windows Installer (v$Version)"
Write-Host "======================================================="

# Step 0: Sync version constant into Dart source
Write-Host "Step 0: Syncing version to lib/app_version.dart..."
$AppVersionFile = Join-Path $ProjectRoot "lib\app_version.dart"
(Get-Content $AppVersionFile) -replace "const kAppVersion = '.*'", "const kAppVersion = '$Version'" |
    Set-Content $AppVersionFile

# Step 1: Build Flutter Windows release
Push-Location $ProjectRoot
flutter build windows --release
Pop-Location

# Step 2: Verify Inno Setup is available
Write-Host "Step 2: Checking for Inno Setup..."
if (-not (Test-Path $InnoSetupPath)) {
    # Try to find ISCC in PATH
    $IsccInPath = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($IsccInPath) {
        $InnoSetupPath = $IsccInPath.Source
    } else {
        Write-Error @"
Inno Setup not found at: $InnoSetupPath
Download and install from: https://jrsoftware.org/isdl.php
Or specify the path: .\scripts\build_windows_installer.ps1 -InnoSetupPath "C:\path\to\ISCC.exe"
"@
        exit 1
    }
}
Write-Host "  Found: $InnoSetupPath"

# Step 3: Update version in installer script (override via ISCC define)
Write-Host "Step 3: Building installer..."
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

& $InnoSetupPath `
    /DMyAppVersion=$Version `
    $InstallerScript

if ($LASTEXITCODE -ne 0) {
    Write-Error "Inno Setup failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

$InstallerPath = Join-Path $DistDir "Ham_Net_Manager-$Version-Windows-Setup.exe"
Write-Host ""
Write-Host "  Installer created successfully!"
Write-Host "  Location: $InstallerPath"
