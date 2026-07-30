# Start App Proxy (runs ON THE VM)
# Starts the ProxiFyre per-app SOCKS5 proxifier service (installed via
# scripts/deploy-proxifyre.ps1), which transparently routes Rivhit, Chrome,
# and Edge traffic through the reverse SOCKS tunnel (localhost:1080) created
# by enable-proxy-point.ps1 running on your PC - no special launch
# arguments or dedicated profiles needed, ProxiFyre intercepts at the
# network driver level based on process name/path.
#
# Coverage (see C:\ProxiFyre\app-config.json):
#   - C:\Rivhit\* (any exe in that folder - covers rivhit125.exe and any
#     child helper process it spawns, e.g. icredit.exe, BatchEMV.exe)
#   - chrome.exe  - ALL Chrome windows/profiles, not just a dedicated one
#   - msedge.exe  - ALL Edge windows/profiles
#
# The ProxiFyre service is intentionally left on Manual startup (never
# starts on its own / on boot, and not tied to Proxy Point's RDP auto-start)
# - only this script (or vm-stop-app-proxy.ps1) toggles it, per design choice
# to keep app-level proxying fully opt-in.

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
    Write-Host " Use the 'Start App Proxy' desktop shortcut (already set to Run as administrator)." -ForegroundColor Yellow
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
Write-Host " $ServiceName is running - Rivhit, Chrome, and Edge traffic will exit via your PC." -ForegroundColor Green

# Rivhit: safe to auto-restart (accounting data is saved server-side / on demand,
# and this mirrors the behavior already relied on before this was generalized).
if (Test-Path $RivhitPath) {
    $existingRivhit = Get-Process -Name "rivhit125" -ErrorAction SilentlyContinue
    if ($existingRivhit) {
        Write-Host " Rivhit is already running - closing it so it restarts under the proxy..." -ForegroundColor Yellow
        $existingRivhit | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
    Write-Host " Launching Rivhit via proxy..." -ForegroundColor Green
    Start-Process -FilePath $RivhitPath
}
else {
    Write-Host " Rivhit executable not found at $RivhitPath (skipped)." -ForegroundColor Yellow
}

# Chrome/Edge: NOT auto-closed (could lose open tabs/unsaved form data). Any
# already-open window's NEW connections (new tabs/navigations) made after this
# point are captured automatically; fully-closing and reopening guarantees it.
Write-Host ""
Write-Host " Chrome/Edge: not restarted automatically to avoid losing your open tabs." -ForegroundColor Cyan
Write-Host " Open a new tab/window (or close and reopen) to route it through the proxy." -ForegroundColor Gray
