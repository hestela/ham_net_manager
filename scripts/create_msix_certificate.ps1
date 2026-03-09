# Create a self-signed certificate for MSIX signing
# Run this ONCE on your build machine (as Administrator).
# The certificate is saved to certs/ham_net_manager.pfx
# Share the .cer file with users so they can install it to trust your app.

param(
    [string]$Publisher = "CN=HamNetManager"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$CertsDir = Join-Path $ProjectRoot "certs"

New-Item -ItemType Directory -Force -Path $CertsDir | Out-Null

$PfxPath = Join-Path $CertsDir "ham_net_manager.pfx"
$CerPath = Join-Path $CertsDir "ham_net_manager.cer"

# Prompt for certificate password
$securePassword = Read-Host -Prompt "Enter a password for the PFX certificate" -AsSecureString
$confirmPassword = Read-Host -Prompt "Confirm password" -AsSecureString

# Compare passwords
$plain1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
$plain2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword))
if ($plain1 -ne $plain2) {
    Write-Error "Passwords do not match."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($plain1)) {
    Write-Error "Password cannot be empty."
    exit 1
}

# Create self-signed certificate (valid for 5 years)
$cert = New-SelfSignedCertificate `
    -Type Custom `
    -Subject $Publisher `
    -KeyUsage DigitalSignature `
    -FriendlyName "Ham Net Manager" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}") `
    -NotAfter (Get-Date).AddYears(10)

# Export as PFX (for signing — keep this private)
Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $securePassword | Out-Null

# Export as CER (for distribution — share this with users)
Export-Certificate -Cert $cert -FilePath $CerPath | Out-Null

# Clean up from certificate store
Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Certificate created successfully!"
Write-Host "  PFX (for signing):       $PfxPath"
Write-Host "  CER (for users):         $CerPath"
Write-Host "  Publisher:               $Publisher"
Write-Host "  Expires:                 $((Get-Date).AddYears(10).ToString('yyyy-MM-dd'))"
Write-Host ""
Write-Host "IMPORTANT:"
Write-Host "  - Keep the .pfx file private (do NOT commit it to git)"
Write-Host "  - Share the .cer file with users for installation"
Write-Host "  - Users install the .cer by:"
Write-Host "    1. Double-click ham_net_manager.cer"
Write-Host "    2. Click 'Install Certificate'"
Write-Host "    3. Select 'Local Machine'"
Write-Host "    4. Choose 'Place all certificates in the following store'"
Write-Host "    5. Browse -> 'Trusted People' -> OK -> Next -> Finish"
