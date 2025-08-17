# Deploy Internal Hibernation Monitor to VM
# Copies the monitor script to the VM and sets up as a scheduled task

param(
    [string]$VMPath = "C:\VMHibernation",
    [int]$InactivityTimeoutMinutes = 10,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# Check if running as Administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "❌ This script requires Administrator privileges to create scheduled tasks" -ForegroundColor Red
    Write-Host "💡 Please run PowerShell as Administrator and try again" -ForegroundColor Yellow
    Write-Host "🔧 To run as Administrator:" -ForegroundColor Cyan
    Write-Host "   1. Right-click on PowerShell" -ForegroundColor Gray
    Write-Host "   2. Select 'Run as Administrator'" -ForegroundColor Gray
    Write-Host "   3. Navigate to this directory and run the script again" -ForegroundColor Gray
    Write-Host "🛡️ If you get execution policy errors, run this first:" -ForegroundColor Yellow
    Write-Host "   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Gray
    Write-Host "   Or run: powershell -ExecutionPolicy Bypass -File .\scripts\deploy-internal-monitor.ps1" -ForegroundColor Gray
    exit 1
}

function Install-InternalMonitor {
    Write-Host "Installing VM Internal Hibernation Monitor..." -ForegroundColor Cyan
    
    # Create directory structure
    if (-not (Test-Path $VMPath)) {
        Write-Host "Creating directory: $VMPath" -ForegroundColor Green
        New-Item -Path $VMPath -ItemType Directory -Force | Out-Null
    }
    
    # Copy the monitor script
    $sourceScript = Join-Path $PSScriptRoot "vm-internal-hibernation-monitor.ps1"
    $targetScript = Join-Path $VMPath "vm-internal-hibernation-monitor.ps1"
    
    if (Test-Path $sourceScript) {
        Write-Host "Copying monitor script to VM..." -ForegroundColor Green
        Copy-Item $sourceScript $targetScript -Force
        Write-Host "Monitor script copied to: $targetScript" -ForegroundColor Green
    } else {
        throw "Source monitor script not found: $sourceScript"
    }
    
    # Create scheduled task
    Write-Host "Creating scheduled task for automatic startup..." -ForegroundColor Green
    
    $taskName = "VMHibernationMonitor"
    $taskDescription = "Automatically hibernates VM after $InactivityTimeoutMinutes minutes of inactivity"
    
    # Remove existing task if it exists
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "Removing existing scheduled task..." -ForegroundColor Green
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    
    # Create task action
    $actionArgs = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$targetScript`" -InactivityTimeoutMinutes $InactivityTimeoutMinutes"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
    
    # Create task trigger (at startup + delay)
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = "PT2M"  # 2 minute delay after startup
    
    # Create task settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false
    $settings.RestartInterval = "PT1M"  # Restart every 1 minute if it fails
    $settings.RestartCount = 999        # Keep retrying
    
    # Create task principal (run as SYSTEM for reliability)
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    # Register the task
    try {
        Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
        Write-Host "Scheduled task '$taskName' created successfully" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create scheduled task: $_" -ForegroundColor Red
        throw "Scheduled task creation failed"
    }
    
    # Start the task immediately
    Write-Host "Starting hibernation monitor..." -ForegroundColor Green
    try {
        Start-ScheduledTask -TaskName $taskName
        Write-Host "Hibernation monitor started" -ForegroundColor Green
    } catch {
        Write-Host "Failed to start task immediately: $_" -ForegroundColor Yellow
        Write-Host "   Task will start automatically on next boot" -ForegroundColor Gray
    }
    
    Write-Host "VM Internal Hibernation Monitor installed and started!" -ForegroundColor Green
    Write-Host "   Monitor script: $targetScript" -ForegroundColor Gray
    Write-Host "   Inactivity timeout: $InactivityTimeoutMinutes minutes" -ForegroundColor Gray
    Write-Host "   Log file: $env:TEMP\hibernation-monitor.log" -ForegroundColor Gray
    Write-Host "   Scheduled task: $taskName" -ForegroundColor Gray
}

function Uninstall-InternalMonitor {
    Write-Host "Uninstalling VM Internal Hibernation Monitor..." -ForegroundColor Yellow
    
    $taskName = "VMHibernationMonitor"
    
    # Remove scheduled task
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "Stopping and removing scheduled task..." -ForegroundColor Green
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Scheduled task removed" -ForegroundColor Green
    } else {
        Write-Host "No scheduled task found to remove" -ForegroundColor Green
    }
    
    # Remove files
    if (Test-Path $VMPath) {
        Write-Host "Removing hibernation monitor files..." -ForegroundColor Green
        Remove-Item $VMPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Monitor files removed" -ForegroundColor Green
    }
    
    Write-Host "VM Internal Hibernation Monitor uninstalled successfully!" -ForegroundColor Green
}

function Show-Status {
    Write-Host "VM Internal Hibernation Monitor Status" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    
    $taskName = "VMHibernationMonitor"
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if ($task) {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
        Write-Host "Scheduled Task: $($task.State)" -ForegroundColor Green
        Write-Host "   Last Run: $($taskInfo.LastRunTime)" -ForegroundColor Gray
        Write-Host "   Next Run: $($taskInfo.NextRunTime)" -ForegroundColor Gray
        Write-Host "   Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
    } else {
        Write-Host "Scheduled task not found" -ForegroundColor Red
    }
    
    $scriptPath = Join-Path $VMPath "vm-internal-hibernation-monitor.ps1"
    if (Test-Path $scriptPath) {
        Write-Host "Monitor script: Installed" -ForegroundColor Green
        Write-Host "   Location: $scriptPath" -ForegroundColor Gray
    } else {
        Write-Host "Monitor script: Not found" -ForegroundColor Red
    }
    
    $logPath = "$env:TEMP\hibernation-monitor.log"
    if (Test-Path $logPath) {
        $logSize = (Get-Item $logPath).Length
        Write-Host "Log file: $logSize bytes" -ForegroundColor Green
        Write-Host "   Location: $logPath" -ForegroundColor Gray
        
        # Show last few log entries
        $lastEntries = Get-Content $logPath -Tail 5 -ErrorAction SilentlyContinue
        if ($lastEntries) {
            Write-Host "   Recent log entries:" -ForegroundColor Gray
            foreach ($entry in $lastEntries) {
                Write-Host "     $entry" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "Log file: Not found" -ForegroundColor Yellow
    }
}

# Main execution
Write-Host "VM Internal Hibernation Monitor Deployment" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green

if ($Uninstall) {
    Uninstall-InternalMonitor
} else {
    # Check if running inside a VM
    $isVM = (Get-WmiObject -Class Win32_ComputerSystem).Model -match "Virtual|VMware|VirtualBox|Hyper-V"
    if (-not $isVM) {
        Write-Host "Warning: This does not appear to be running inside a VM" -ForegroundColor Yellow
        Write-Host "   Continuing anyway..." -ForegroundColor Yellow
    }
    
    Install-InternalMonitor
    Start-Sleep -Seconds 2
    Show-Status
}

