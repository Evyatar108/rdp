# Deploy Internal Hibernation Monitor to VM

param(
    [string]$VMPath = "C:\VMHibernation",
    [int]$InactivityTimeoutMinutes = 10,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "This script requires Administrator privileges to create scheduled tasks" -ForegroundColor Red
    Write-Host "Run PowerShell as Administrator and try again." -ForegroundColor Yellow
    Write-Host "Tip: Right-click PowerShell and select 'Run as Administrator'." -ForegroundColor Gray
    exit 1
}

function Install-InternalMonitor {
    Write-Host "Installing VM Internal Hibernation Monitor..." -ForegroundColor Cyan

    # Load configuration to get the correct timeout
    try {
        . (Join-Path $PSScriptRoot "config-loader.ps1")
        $config = Get-VMRdpConfig
        $timeoutFromConfig = $config.hibernation.internal.inactivityTimeoutMinutes
        Write-Host "Loaded inactivity timeout from config: $timeoutFromConfig minutes" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Could not load configuration: $_" -ForegroundColor Red
        Write-Host "The internal monitor requires a valid config.json file." -ForegroundColor Red
        throw "Configuration loading failed"
    }

    # Load shared Azure authentication helper
    . (Join-Path $PSScriptRoot "azure-auth-helper.ps1")
    
    # Ensure Azure CLI is available and authenticated
    Write-Host "Setting up Azure CLI..." -ForegroundColor Yellow
    Ensure-AzureCLIInstalled
    Ensure-AzureCLIAuthenticated -TenantId $config.azure.target.tenantId -SubscriptionId $config.azure.target.subscriptionId

    # Create directory structure
    if (-not (Test-Path $VMPath)) {
        Write-Host "Creating directory: $VMPath" -ForegroundColor Green
        New-Item -Path $VMPath -ItemType Directory -Force | Out-Null
    }

    # Copy the monitor script
    $sourceScript = Join-Path $PSScriptRoot "vm-internal-hibernation-monitor.ps1"
    $targetScript = Join-Path $VMPath "vm-internal-hibernation-monitor.ps1"
    $monitorLog = Join-Path $VMPath "hibernation-monitor.log"

    if (Test-Path $sourceScript) {
        Write-Host "Copying monitor script to VM..." -ForegroundColor Green
        Copy-Item $sourceScript $targetScript -Force
        Write-Host "Monitor script copied to: $targetScript" -ForegroundColor Green
    }
    else {
        throw "Source monitor script not found: $sourceScript"
    }

    # Create scheduled task
    Write-Host "Creating scheduled task for automatic startup..." -ForegroundColor Green

    $taskName = "VMHibernationMonitor"
    $taskDescription = "Automatically hibernates VM after $timeoutFromConfig minutes of inactivity"

    # Remove existing task if it exists
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "Removing existing scheduled task..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    # Create task action
    $actionArgs = "-NoProfile -NoLogo -NoExit -ExecutionPolicy Bypass -File `"$targetScript`" -InactivityTimeoutMinutes $timeoutFromConfig -LogFile `"$monitorLog`""
    Write-Host "Task arguments: $actionArgs" -ForegroundColor Gray
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs

    # Create task trigger (at startup + delay)
    $triggerLogon = New-ScheduledTaskTrigger -AtLogOn
    # Periodic repetition so Task Scheduler relaunches the monitor shortly if closed (Windows limit ~31 days)
    $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 30)

    # Create task settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false
    $settings.ExecutionTimeLimit = "PT0S"   # No time limit; run indefinitely
    $settings.RestartCount = 0              # Disable engine restarts; rely on repeating trigger
    $settings.MultipleInstances = "IgnoreNew"  # Prevent duplicate instances

    # Create task principal (run in interactive user session so window is visible)
    $principal = New-ScheduledTaskPrincipal -UserId "$env:UserDomain\$env:UserName" -LogonType Interactive -RunLevel Highest

    # Register the task
    try {
        Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger @($triggerLogon, $triggerRepeat) -Settings $settings -Principal $principal | Out-Null
        Write-Host "Scheduled task '$taskName' created successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to create scheduled task: $_" -ForegroundColor Red
        throw "Scheduled task creation failed"
    }

    # Stop any existing running instances first
    Write-Host "Stopping any existing monitor instances..." -ForegroundColor Yellow
    try {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    catch { }

    # Start the task immediately
    Write-Host "Starting hibernation monitor..." -ForegroundColor Green
    try {
        Start-ScheduledTask -TaskName $taskName
        Write-Host "Hibernation monitor started" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to start task immediately: $_" -ForegroundColor Yellow
        Write-Host "Task will start automatically on next boot" -ForegroundColor Gray
    }

    Write-Host "VM Internal Hibernation Monitor installed and started!" -ForegroundColor Green
    Write-Host "  Monitor script: $targetScript" -ForegroundColor Gray
    Write-Host "  Inactivity timeout: $timeoutFromConfig minutes" -ForegroundColor Gray
    Write-Host "  Log file: $monitorLog" -ForegroundColor Gray
    Write-Host "  Scheduled task: $taskName" -ForegroundColor Gray
}

function Uninstall-InternalMonitor {
    Write-Host "Uninstalling VM Internal Hibernation Monitor..." -ForegroundColor Yellow

    $taskName = "VMHibernationMonitor"

    # Remove scheduled task
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "Stopping and removing scheduled task..." -ForegroundColor Yellow
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Scheduled task removed" -ForegroundColor Green
    }
    else {
        Write-Host "No scheduled task found to remove" -ForegroundColor Yellow
    }

    # Remove files
    if (Test-Path $VMPath) {
        Write-Host "Removing hibernation monitor files..." -ForegroundColor Yellow
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
        Write-Host "  Last Run: $($taskInfo.LastRunTime)" -ForegroundColor Gray
        Write-Host "  Next Run: $($taskInfo.NextRunTime)" -ForegroundColor Gray
        Write-Host "  Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
    }
    else {
        Write-Host "Scheduled task not found" -ForegroundColor Red
    }

    $scriptPath = Join-Path $VMPath "vm-internal-hibernation-monitor.ps1"
    if (Test-Path $scriptPath) {
        Write-Host "Monitor script: Installed" -ForegroundColor Green
        Write-Host "  Location: $scriptPath" -ForegroundColor Gray
    }
    else {
        Write-Host "Monitor script: Not found" -ForegroundColor Red
    }

    $logPath = (Join-Path $VMPath "hibernation-monitor.log")
    if (Test-Path $logPath) {
        $logSize = (Get-Item $logPath).Length
        Write-Host "Log file: $logSize bytes" -ForegroundColor Green
        Write-Host "  Location: $logPath" -ForegroundColor Gray

        # Show last few log entries
        $lastEntries = Get-Content $logPath -Tail 5 -ErrorAction SilentlyContinue
        if ($lastEntries) {
            Write-Host "  Recent log entries:" -ForegroundColor Gray
            foreach ($entry in $lastEntries) {
                Write-Host "    $entry" -ForegroundColor DarkGray
            }
        }
    }
    else {
        Write-Host "Log file: Not found" -ForegroundColor Yellow
    }
}

Write-Host "VM Internal Hibernation Monitor Deployment" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green

if ($Uninstall) {
    Uninstall-InternalMonitor
}
else {
    # Check if running inside a VM
    $isVM = $false
    try {
        $model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
        if ($model -match "Virtual|VMware|VirtualBox|Hyper-V") { $isVM = $true }
    }
    catch { $isVM = $false }

    if (-not $isVM) {
        Write-Host "Warning: This does not appear to be running inside a VM" -ForegroundColor Yellow
        Write-Host "  Continuing anyway..." -ForegroundColor Yellow
    }

    Install-InternalMonitor
    Start-Sleep -Seconds 2
    Show-Status
}

Write-Host ""
Write-Host "Usage Tips:" -ForegroundColor Yellow
Write-Host "  - To check status: .\deploy-internal-monitor.ps1" -ForegroundColor Gray
Write-Host "  - To uninstall: .\deploy-internal-monitor.ps1 -Uninstall" -ForegroundColor Gray
Write-Host "  - To change timeout: .\deploy-internal-monitor.ps1 -InactivityTimeoutMinutes 15" -ForegroundColor Gray
Write-Host "  - View logs: Get-Content C:\VMHibernation\hibernation-monitor.log" -ForegroundColor Gray
