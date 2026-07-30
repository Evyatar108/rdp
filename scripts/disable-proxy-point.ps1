# Disable Proxy Point
# Stops any running proxy-point SSH tunnels started by enable-proxy-point.ps1.

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "config-loader.ps1")
$config = Get-VMRdpConfig
$SOCKS_PORT = [int]$config.proxyPoint.socksPort
if ($SOCKS_PORT -lt 1 -or $SOCKS_PORT -gt 65535) {
    throw "Invalid proxyPoint.socksPort '$SOCKS_PORT'; refusing to stop SSH processes."
}
. (Join-Path $PSScriptRoot "proxy-point-helper.ps1")

Write-Host " Stopping proxy point tunnels..." -ForegroundColor Yellow

$state = Get-ProxyPointLocalState
if ($state -and $state.ownerToken -and $state.publicIP) {
    try {
        $result = Release-ProxyPointOwnership `
            -Config $config `
            -PublicIP $state.publicIP `
            -OwnerToken $state.ownerToken
        if ($result -match "proxy-release:released") {
            Write-Host " Released this PC's VM-side Proxy Point ownership." -ForegroundColor Green
        }
        elseif ($result -match "proxy-release:not-owner") {
            Write-Host " Another PC already owns Proxy Point; its tunnel was not touched." -ForegroundColor Gray
        }
    }
    catch {
        Write-Host " Could not release VM-side ownership: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

$killed = 0
Get-CimInstance Win32_Process |
    Where-Object {
        $_.Name -match '^powershell(\.exe)?$' -and
        $_.CommandLine -match 'enable-proxy-point\.ps1'
    } |
    ForEach-Object {
        Write-Host "  Stopping proxy wrapper (PID $($_.ProcessId))" -ForegroundColor Gray
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        $killed++
    }

Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" | ForEach-Object {
    if ($_.CommandLine -match "-R\s+$SOCKS_PORT\b") {
        Write-Host "  Stopping ssh tunnel (PID $($_.ProcessId))" -ForegroundColor Gray
        Stop-Process -Id $_.ProcessId -Force
        $killed++
    }

    Clear-ProxyPointLocalState
}

if ($killed -gt 0) {
    Write-Host " Stopped $killed tunnel process(es). Proxy point disabled." -ForegroundColor Green
} else {
    Write-Host " No active proxy point tunnels found." -ForegroundColor Green
}
