# Build Ham Net Manager MSIX package
# Prerequisites: Run create_msix_certificate.ps1 first (once)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PfxPath = Join-Path $ProjectRoot "certs\ham_net_manager.pfx"
$DistDir = Join-Path $ProjectRoot "dist"

# Read version from pubspec.yaml
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$VersionLine = Select-String -Path $PubspecPath -Pattern "^version:" | Select-Object -First 1
$Version = ($VersionLine.Line -split ":")[1].Trim() -replace "\+.*", ""

Write-Host "Building Ham Net Manager MSIX (v$Version)"
Write-Host "============================================"

# Check certificate exists
if (-not (Test-Path $PfxPath)) {
    Write-Error @"
Certificate not found at: $PfxPath
Run this first: .\scripts\create_msix_certificate.ps1
"@
    exit 1
}

# Prompt for certificate password
$securePassword = Read-Host -Prompt "Enter the PFX certificate password" -AsSecureString
$PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))

# Sync version to Dart source
Write-Host "Step 1: Syncing version..."
$AppVersionFile = Join-Path $ProjectRoot "lib\app_version.dart"
if (Test-Path $AppVersionFile) {
    (Get-Content $AppVersionFile) -replace "const kAppVersion = '.*'", "const kAppVersion = '$Version'" |
        Set-Content $AppVersionFile
}

# Update MSIX version in pubspec (MSIX needs 4-part version)
$MsixVersion = "$Version.0"
$PubspecContent = Get-Content $PubspecPath -Raw
$PubspecContent = $PubspecContent -replace "msix_version: .*", "msix_version: $MsixVersion"
Set-Content -Path $PubspecPath -Value $PubspecContent -NoNewline

# Build MSIX
Write-Host "Step 2: Building Flutter Windows release and MSIX..."
Push-Location $ProjectRoot
flutter pub run msix:create --certificate-password $PlainPassword
Pop-Location

# Copy MSIX to dist
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$MsixSource = Join-Path $ProjectRoot "build\windows\x64\runner\Release\ham_net_manager.msix"
$MsixDest = Join-Path $DistDir "Ham_Net_Manager-$Version.msix"
Copy-Item $MsixSource $MsixDest -Force

# Also copy the .cer for distribution
$CerSource = Join-Path $ProjectRoot "certs\ham_net_manager.cer"
$CerDest = Join-Path $DistDir "ham_net_manager.cer"
if (Test-Path $CerSource) {
    Copy-Item $CerSource $CerDest -Force
}

Write-Host ""
Write-Host "Build complete!"
Write-Host "  MSIX:         $MsixDest"
Write-Host "  Certificate:  $CerDest"
Write-Host ""
Write-Host "Distribute BOTH files to users. They must install the .cer first."
