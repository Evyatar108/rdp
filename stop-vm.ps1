# VM Stop Launcher
# Convenience script to stop the Azure VM

$ErrorActionPreference = "Stop"

Write-Host " VM Stop Launcher" -ForegroundColor Green
Write-Host "==================" -ForegroundColor Green
Write-Host ""

# Get script paths
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$stopScript = Join-Path $scriptDirectory "scripts\stop-vm.ps1"

# Launch the stop script
if (-not (Test-Path $stopScript)) {
    Write-Error "Stop script not found at: $stopScript"
    Write-Host " Ensure scripts\stop-vm.ps1 exists" -ForegroundColor Yellow
    exit 1
}

# Execute the stop script
& $stopScript