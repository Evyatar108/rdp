# Stop Rivhit Proxy (runs ON THE VM)
# Stops the ProxiFyre service, reverting rivhit125.exe to normal (VM/Azure) egress.
# Optionally closes Rivhit first so it restarts cleanly outside the proxy next time.

param(
    [string]$ServiceName = "ProxiFyreService"
)

$ErrorActionPreference = "Stop"

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host " This must run elevated (stopping a Windows service requires admin)." -ForegroundColor Red
    Write-Host " Use the 'Stop Rivhit Proxy' desktop shortcut (already set to Run as administrator)." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

$existing = Get-Process -Name "rivhit125" -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host " Closing Rivhit so it restarts cleanly without the proxy..." -ForegroundColor Yellow
    $existing | Stop-Process -Force
    Start-Sleep -Seconds 1
}

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Write-Host " Stopping $ServiceName..." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force
    Write-Host " Stopped. Rivhit traffic will use normal VM egress from now on." -ForegroundColor Green
}
else {
    Write-Host " $ServiceName was not running." -ForegroundColor Gray
}
