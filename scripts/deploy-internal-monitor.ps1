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
    Write-Host ""
    Write-Host "🔧 To run as Administrator:" -ForegroundColor Cyan
    Write-Host "   1. Right-click on PowerShell" -ForegroundColor Gray
    Write-Host "   2. Select 'Run as Administrator'" -ForegroundColor Gray
    Write-Host "   3. Navigate to this directory and run the script again" -ForegroundColor Gray
    Write-Host ""
    Write-Host "🛡️ If you get execution policy errors, run this first:" -ForegroundColor Yellow
    Write-Host "   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Gray
    Write-Host "   Or run: powershell -ExecutionPolicy Bypass -File .\scripts\deploy-internal-monitor.ps1" -ForegroundColor Gray
    exit 1
}

function Write-Status {
    param([string]$Message, [string]$Color = "Green")
    Write-Host $Message -ForegroundColor $Color
}

function Install-InternalMonitor {
    Write-Status "Installing VM Internal Hibernation Monitor..." "Cyan"
    
    # Create directory structure
    if (-not (Test-Path $VMPath)) {
        Write-Status "Creating directory: $VMPath"
        New-Item -Path $VMPath -ItemType Directory -Force | Out-Null
    }
    
    # Copy the monitor script
    $sourceScript = Join-Path $PSScriptRoot "vm-internal-hibernation-monitor.ps1"
    $targetScript = Join-Path $VMPath "vm-internal-hibernation-monitor.ps1"
    
    if (Test-Path $sourceScript) {
        Write-Status "Copying monitor script to VM..."
        Copy-Item $sourceScript $targetScript -Force
        Write-Status "Monitor script copied to: $targetScript"
    } else {
        throw "Source monitor script not found: $sourceScript"
    }
    
    # Create scheduled task
    Write-Status "Creating scheduled task for automatic startup..."
    
    $taskName = "VMHibernationMonitor"
    $taskDescription = "Automatically hibernates VM after $InactivityTimeoutMinutes minutes of inactivity"
    
    # Remove existing task if it exists
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Status "Removing existing scheduled task..."
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
        Write-Status "Scheduled task '$taskName' created successfully"
    } catch {
        Write-Status "❌ Failed to create scheduled task: $_" "Red"
        throw "Scheduled task creation failed"
    }
    
    # Start the task immediately
    Write-Status "Starting hibernation monitor..."
    try {
        Start-ScheduledTask -TaskName $taskName
        Write-Status "Hibernation monitor started"
    } catch {
        Write-Status "Failed to start task immediately: $_" "Yellow"
        Write-Status "   Task will start automatically on next boot" "Gray"
    }
    
    Write-Status "VM Internal Hibernation Monitor installed and started!" "Green"
    Write-Status "   Monitor script: $targetScript" "Gray"
    Write-Status "   Inactivity timeout: $InactivityTimeoutMinutes minutes" "Gray"
    Write-Status "   Log file: $env:TEMP\hibernation-monitor.log" "Gray"
    Write-Status "   Scheduled task: $taskName" "Gray"
}

function Uninstall-InternalMonitor {
    Write-Status "Uninstalling VM Internal Hibernation Monitor..." "Yellow"
    
    $taskName = "VMHibernationMonitor"
    
    # Remove scheduled task
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Status "Stopping and removing scheduled task..."
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Status "Scheduled task removed"
    } else {
        Write-Status "No scheduled task found to remove"
    }
    
    # Remove files
    if (Test-Path $VMPath) {
        Write-Status "Removing hibernation monitor files..."
        Remove-Item $VMPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Status "Monitor files removed"
    }
    
    Write-Status "VM Internal Hibernation Monitor uninstalled successfully!" "Green"
}

function Show-Status {
    Write-Status "VM Internal Hibernation Monitor Status" "Cyan"
    Write-Status "=========================================" "Cyan"
    
    $taskName = "VMHibernationMonitor"
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if ($task) {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
        Write-Status "Scheduled Task: $($task.State)" "Green"
        Write-Status "   Last Run: $($taskInfo.LastRunTime)" "Gray"
        Write-Status "   Next Run: $($taskInfo.NextRunTime)" "Gray"
        Write-Status "   Last Result: $($taskInfo.LastTaskResult)" "Gray"
    } else {
        Write-Status "Scheduled task not found" "Red"
    }
    
    $scriptPath = Join-Path $VMPath "vm-internal-hibernation-monitor.ps1"
    if (Test-Path $scriptPath) {
        Write-Status "Monitor script: Installed" "Green"
        Write-Status "   Location: $scriptPath" "Gray"
    } else {
        Write-Status "Monitor script: Not found" "Red"
    }
    
    $logPath = "$env:TEMP\hibernation-monitor.log"
    if (Test-Path $logPath) {
        $logSize = (Get-Item $logPath).Length
        Write-Status "Log file: $logSize bytes" "Green"
        Write-Status "   Location: $logPath" "Gray"
        
        # Show last few log entries
        $lastEntries = Get-Content $logPath -Tail 5 -ErrorAction SilentlyContinue
        if ($lastEntries) {
            Write-Status "   Recent log entries:" "Gray"
            foreach ($entry in $lastEntries) {
                Write-Status "     $entry" "DarkGray"
            }
        }
    } else {
        Write-Status "Log file: Not found" "Yellow"
    }
}

# Main execution
Write-Status "VM Internal Hibernation Monitor Deployment" "Green"
Write-Status "===========================================" "Green"

if ($Uninstall) {
    Uninstall-InternalMonitor
} else {
    # Check if running inside a VM
    $isVM = (Get-WmiObject -Class Win32_ComputerSystem).Model -match "Virtual|VMware|VirtualBox|Hyper-V"
    if (-not $isVM) {
        Write-Status "Warning: This does not appear to be running inside a VM" "Yellow"
        Write-Status "   Continuing anyway..." "Yellow"
    }
    
    Install-InternalMonitor
    Start-Sleep -Seconds 2
    Show-Status
}

Write-Status ""