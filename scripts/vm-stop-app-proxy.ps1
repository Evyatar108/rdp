# Stop App Proxy (runs ON THE VM)
# Stops the ProxiFyre service, reverting Rivhit/Chrome/Edge to normal (VM/Azure)
# egress. Closes Rivhit first so it restarts cleanly outside the proxy next
# time. Chrome/Edge are NOT force-closed (avoid losing open tabs) - close and
# reopen them yourself to fully return their traffic to normal VM egress.
# In automatic appProxyMode this is a per-session override; the next successful
# RDP/Proxy Point ownership claim starts the service again.

param(
    [string]$ServiceName = "ProxiFyreService",
    [string]$RivhitPath = "C:\Rivhit\rivhit125.exe"
)

$ErrorActionPreference = "Stop"

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host " This must run elevated (stopping a Windows service requires admin)." -ForegroundColor Red
    Write-Host " Use the 'Stop App Proxy' desktop shortcut (already set to Run as administrator)." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

$existingRivhit = Get-Process -Name "rivhit125" -ErrorAction SilentlyContinue
if ($existingRivhit) {
    Write-Host " Closing Rivhit so it restarts cleanly without the proxy..." -ForegroundColor Yellow
    $existingRivhit | Stop-Process -Force
    Start-Sleep -Seconds 1
}

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Write-Host " Stopping $ServiceName..." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force
    Write-Host " Stopped. Rivhit's traffic will use normal VM egress from now on." -ForegroundColor Green
}
else {
    Write-Host " $ServiceName was not running." -ForegroundColor Gray
}

Write-Host ""
Write-Host " Chrome/Edge: close and reopen any windows that were open while the proxy" -ForegroundColor Cyan
Write-Host " was active, so new connections use normal VM egress again." -ForegroundColor Gray
