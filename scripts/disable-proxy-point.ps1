# Disable Proxy Point
# Stops any running proxy-point SSH tunnels started by enable-proxy-point.ps1.

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "config-loader.ps1")
$config = Get-VMRdpConfig
$SOCKS_PORT = $config.proxyPoint.socksPort

Write-Host " Stopping proxy point tunnels..." -ForegroundColor Yellow

$killed = 0
Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" | ForEach-Object {
    if ($_.CommandLine -match "-R\s+$SOCKS_PORT\b") {
        Write-Host "  Stopping ssh tunnel (PID $($_.ProcessId))" -ForegroundColor Gray
        Stop-Process -Id $_.ProcessId -Force
        $killed++
    }
}

if ($killed -gt 0) {
    Write-Host " Stopped $killed tunnel process(es). Proxy point disabled." -ForegroundColor Green
} else {
    Write-Host " No active proxy point tunnels found." -ForegroundColor Green
}
