# VM RDP Launcher with Auto-Update
# This is the main script users should run - it updates scripts and launches the RDP connection

$ErrorActionPreference = "Stop"

Write-Host " VM RDP Launcher" -ForegroundColor Green
Write-Host "==================" -ForegroundColor Green

# Get script paths
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$updateScript = Join-Path $scriptDirectory "scripts\update-scripts.ps1"
$connectScript = Join-Path $scriptDirectory "scripts\connect-vm-rdp.ps1"

# Check for script updates
if (Test-Path $updateScript) {
    $scriptsUpdated = & $updateScript
    Write-Host "" # Empty line for spacing
    
    # If scripts were updated, restart this script to use the new version
    if ($scriptsUpdated) {
        Write-Host " Scripts updated! Restarting with new version..." -ForegroundColor Yellow
        Write-Host ""
        
        # Re-execute this script with the updated version
        & $MyInvocation.MyCommand.Path
        exit 0
    }
} else {
    Write-Host " Update script not found - continuing with current scripts" -ForegroundColor Yellow
    Write-Host "" # Empty line for spacing
}

# Launch the actual connect script
if (-not (Test-Path $connectScript)) {
    Write-Error "Connect script not found at: $connectScript"
    Write-Host " Ensure scripts\connect-vm-rdp.ps1 exists" -ForegroundColor Yellow
    exit 1
}

Write-Host " Launching RDP connection script..." -ForegroundColor Cyan
Write-Host "Script: $connectScript" -ForegroundColor Gray

# Execute the connect script
& $connectScript