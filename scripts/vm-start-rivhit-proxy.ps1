# Start Rivhit via Proxy (runs ON THE VM)
# Starts the ProxiFyre per-app SOCKS5 proxifier service (installed separately via
# scripts/deploy-proxifyre.ps1) which transparently routes ONLY rivhit125.exe's
# traffic through the reverse SOCKS tunnel (localhost:1080) created by
# enable-proxy-point.ps1 running on your PC. Then launches Rivhit.
#
# Unlike the browser shortcut, this does NOT need any special launch arguments -
# ProxiFyre intercepts rivhit125.exe's traffic at the network driver level, so
# Rivhit is started completely normally.
#
# The ProxiFyre service is intentionally left on Manual startup (never starts on
# its own / on boot) - only this script (or Stop-RivhitProxy) toggles it.

param(
    [int]$SocksPort = 1080,
    [string]$RivhitPath = "C:\Rivhit\rivhit125.exe",
    [string]$ServiceName = "ProxiFyreService"
)

$ErrorActionPreference = "Stop"

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host " This must run elevated (starting a Windows service requires admin)." -ForegroundColor Red
    Write-Host " Use the 'Start Rivhit via Proxy' desktop shortcut (already set to Run as administrator)." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Verify the Proxy Point tunnel is up (something must be listening on the SOCKS port)
$listening = Get-NetTCPConnection -LocalPort $SocksPort -State Listen -ErrorAction SilentlyContinue
if (-not $listening) {
    Write-Host " No Proxy Point tunnel detected on localhost:$SocksPort" -ForegroundColor Red
    Write-Host " Run scripts\enable-proxy-point.ps1 on your PC first (or reconnect via connect-vm-rdp.ps1)." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host " $ServiceName is not installed. Run scripts\deploy-proxifyre.ps1 first." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if ($svc.Status -ne "Running") {
    Write-Host " Starting $ServiceName..." -ForegroundColor Yellow
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 2
}
Write-Host " $ServiceName is running - rivhit125.exe traffic will exit via your PC." -ForegroundColor Green

if (-not (Test-Path $RivhitPath)) {
    Write-Host " Rivhit executable not found at $RivhitPath" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# If Rivhit is already running, its existing connections were established before
# the proxy was active - restart it so all traffic is captured from launch.
$existing = Get-Process -Name "rivhit125" -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host " Rivhit is already running - closing it so it restarts under the proxy..." -ForegroundColor Yellow
    $existing | Stop-Process -Force
    Start-Sleep -Seconds 2
}

Write-Host " Launching Rivhit via proxy..." -ForegroundColor Green
Start-Process -FilePath $RivhitPath
