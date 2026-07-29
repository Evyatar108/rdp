# Browser via Proxy Point (runs ON THE VM)
# Launches a browser that routes all traffic through the reverse SOCKS tunnel
# (localhost:1080) created by enable-proxy-point.ps1 running on your PC.
# Traffic exits from the PC's network, not the VM/Azure network.
#
# A dedicated browser profile is used so proxying never affects your normal browser.

param(
    [int]$SocksPort = 1080
)

$ErrorActionPreference = "Stop"

# Verify the tunnel is up (something must be listening on the SOCKS port)
$listening = Get-NetTCPConnection -LocalPort $SocksPort -State Listen -ErrorAction SilentlyContinue
if (-not $listening) {
    Write-Host " No tunnel detected on localhost:$SocksPort" -ForegroundColor Red
    Write-Host " Run scripts\enable-proxy-point.ps1 on your PC first." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Find an installed Chromium-based browser (Edge/Chrome both support --proxy-server)
$browserCandidates = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
)
$browser = $browserCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) {
    Write-Error "No supported browser (Chrome/Edge) found on this VM."
}

$profileDir = Join-Path $env:LOCALAPPDATA "ProxyPointBrowserProfile"

Write-Host " Launching browser through proxy point (localhost:$SocksPort)..." -ForegroundColor Green
Start-Process $browser -ArgumentList @(
    "--proxy-server=socks5://127.0.0.1:$SocksPort",
    "--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE 127.0.0.1",  # force DNS through the SOCKS proxy too
    "--user-data-dir=$profileDir",
    "--no-first-run",
    "https://api.ipify.org?format=json"
)
Write-Host " The opened tab shows your egress IP - it should be your PC's IP." -ForegroundColor Cyan
