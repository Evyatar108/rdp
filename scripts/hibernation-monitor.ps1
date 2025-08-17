param(
    [string]$RG_B,
    [string]$VM_NAME,
    [int]$HIBERNATION_DELAY_SECONDS,
    [int]$PROGRESS_UPDATE_INTERVAL,
    [int]$rdpProcessId,
    [string]$Visible = "true"
)

$ErrorActionPreference = 'Continue'

# Load configuration for additional settings
try {
    . (Join-Path $PSScriptRoot "config-loader.ps1")
    $config = Get-VMRdpConfig
    $verboseOutput = $config.logging.verboseOutput
    $showDetailedErrors = $config.logging.showDetailedErrors
    
    # Check if external hibernation monitoring is disabled
    if (-not $config.hibernation.external.enabled) {
        Write-Host "External hibernation monitoring is disabled in config.json" -ForegroundColor Yellow
        Write-Host "Only the internal VM monitor will handle hibernation." -ForegroundColor Cyan
        Write-Host "VM will remain running until internal monitor triggers hibernation." -ForegroundColor Gray
        Write-Host ""
        Write-Host "To re-enable external monitoring, set hibernation.external.enabled to true in config.json" -ForegroundColor Gray
        
        if ($isVisible) {
            Write-Host "Press Enter to close this window..." -ForegroundColor Yellow
            Read-Host
        }
        else {
            Start-Sleep -Seconds 5
        }
        exit 0
    }
}
catch {
    # Fallback if config loading fails
    $verboseOutput = $true
    $showDetailedErrors = $true
    Write-Host "Warning: Could not load configuration, using defaults" -ForegroundColor Yellow
}

$isVisible = $Visible -eq "true"

try {
    Write-Host "VM Hibernation Monitor" -ForegroundColor Green
    Write-Host "======================" -ForegroundColor Green
    Write-Host "Monitoring RDP Process ID: $rdpProcessId" -ForegroundColor Cyan
    Write-Host "VM: $VM_NAME in $RG_B" -ForegroundColor Cyan
    $delayMinutes = [math]::Round($HIBERNATION_DELAY_SECONDS / 60, 1)
    Write-Host "Hibernation delay: $delayMinutes minutes after RDP closes" -ForegroundColor Cyan
    
    if ($verboseOutput) {
        Write-Host "Visible mode: $isVisible" -ForegroundColor Cyan
        Write-Host "Verbose output: enabled" -ForegroundColor Cyan
    }
    
    Write-Host "Press Ctrl+C to cancel hibernation monitoring" -ForegroundColor Yellow
    Write-Host ""
    
    # Get the RDP process
    Write-Host "Looking for RDP process..." -ForegroundColor Yellow
    $rdpProcess = Get-Process -Id $rdpProcessId -ErrorAction SilentlyContinue
    
    if (-not $rdpProcess) {
        Write-Host "RDP process with ID $rdpProcessId not found." -ForegroundColor Red
        Write-Host "Available mstsc processes:" -ForegroundColor Yellow
        $mstscProcesses = Get-Process -Name "mstsc" -ErrorAction SilentlyContinue
        foreach ($proc in $mstscProcesses) {
            Write-Host "  PID: $($proc.Id), Start Time: $($proc.StartTime)" -ForegroundColor Gray
        }
        throw "RDP process not found"
    }
    
    # Wait for RDP process to exit
    Write-Host "Found RDP process. Monitoring connection..." -ForegroundColor Green
    Write-Host "   Waiting for RDP window to close..." -ForegroundColor Cyan
    Write-Host "   (Countdown will start AFTER you close the RDP window)" -ForegroundColor Yellow
    
    # This blocks until the RDP process exits
    $rdpProcess.WaitForExit()
    
    Write-Host ""
    Write-Host "RDP connection closed" -ForegroundColor Yellow
    
    # Now start the countdown before hibernating
    $delayMinutes = [math]::Round($HIBERNATION_DELAY_SECONDS / 60, 1)
    Write-Host "Starting $delayMinutes minute countdown before hibernating VM..." -ForegroundColor Yellow
    Write-Host "   (Press Ctrl+C to cancel hibernation)" -ForegroundColor Gray
    
    for ($i = $HIBERNATION_DELAY_SECONDS; $i -gt 0; $i--) {
        Write-Progress -Activity "Auto-hibernation countdown" -Status "$i seconds remaining" -PercentComplete (($HIBERNATION_DELAY_SECONDS - $i) / $HIBERNATION_DELAY_SECONDS * 100)
        Start-Sleep -Seconds $PROGRESS_UPDATE_INTERVAL
    }
    
    Write-Progress -Activity "Auto-hibernation countdown" -Completed
    
    # Hibernate the VM
    Write-Host ""
    Write-Host "Hibernating VM..." -ForegroundColor Green
    Write-Host "Running: az vm deallocate -g $RG_B -n $VM_NAME --hibernate true" -ForegroundColor Gray
    
    # Run hibernation command and capture output
    $hibernateOutput = az vm deallocate -g $RG_B -n $VM_NAME --hibernate true 2>&1
    $hibernateExitCode = $LASTEXITCODE
    
    if ($hibernateExitCode -eq 0) {
        Write-Host "VM hibernated successfully!" -ForegroundColor Green
        Write-Host "VM is now in hibernated state (no compute charges)" -ForegroundColor Cyan
        Write-Host "Run connect-vm-rdp.ps1 again to resume and reconnect" -ForegroundColor Yellow
    }
    else {
        Write-Host "Hibernation command failed with exit code: $hibernateExitCode" -ForegroundColor Red
        Write-Host "Output: $hibernateOutput" -ForegroundColor Yellow
    }
    
}
catch [System.Management.Automation.PipelineStoppedException] {
    Write-Host ""
    Write-Host "Auto-hibernation cancelled by user" -ForegroundColor Yellow
    Write-Host "VM remains running" -ForegroundColor Cyan
}
catch {
    Write-Host ""
    Write-Host "Error during hibernation monitoring: $_" -ForegroundColor Red
    
    if ($showDetailedErrors) {
        Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Yellow
        if ($_.ScriptStackTrace) {
            Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Gray
        }
    }
}
finally {
    # Always show final status and wait if visible, regardless of success or failure
    Write-Host ""
    Write-Host "Hibernation monitor finished." -ForegroundColor Gray
    
    if ($isVisible) {
        Write-Host "Press Enter to close this window..." -ForegroundColor Yellow
        try {
            Read-Host
        }
        catch {
            # In case Read-Host fails for any reason
            Start-Sleep -Seconds 30
        }
    }
    else {
        Write-Host "Window will close in 5 seconds..." -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
}