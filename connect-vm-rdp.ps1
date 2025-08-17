$ErrorActionPreference = "Stop"

# ----- CONFIGURATION SETTINGS -----
# Azure Target Configuration
$TENANT_B = "66d51e14-99b9-435a-8c05-449dc0c91710"
$SUB_B = "30748a75-b2b8-4e4f-b5df-e87aa4ceef7b"
$RG_B = "VM-RG-TARGET"
$VM_NAME = "DesktopVM"

# Auto-Hibernation Settings
$HIBERNATION_DELAY_SECONDS = 120  # Wait 2 minutes after RDP closes before hibernating
$PROGRESS_UPDATE_INTERVAL = 1     # Update countdown every 1 second
$HIBERNATION_RESUME_WAIT = 30     # Wait 30 seconds after starting hibernated VM
$MONITOR_WINDOW_VISIBLE = $true   # Set to $false to hide hibernation monitor window

Write-Host "🖥️ Connecting to Azure VM via RDP..." -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green

# Check current Azure context and login if needed
Write-Host "📋 Checking Azure authentication..." -ForegroundColor Yellow
$currentAccount = az account show 2>$null | ConvertFrom-Json
$needsLogin = $false

if (-not $currentAccount) {
    Write-Host "⚠️ Not logged in to Azure" -ForegroundColor Yellow
    $needsLogin = $true
} elseif ($currentAccount.tenantId -ne $TENANT_B) {
    Write-Host "⚠️ Wrong tenant (current: $($currentAccount.tenantId), required: $TENANT_B)" -ForegroundColor Yellow
    $needsLogin = $true
} elseif ($currentAccount.id -ne $SUB_B) {
    Write-Host "⚠️ Wrong subscription (current: $($currentAccount.id), required: $SUB_B)" -ForegroundColor Yellow
    # Just set the subscription, no need to re-login
    az account set --subscription $SUB_B
    Write-Host "✅ Switched to correct subscription" -ForegroundColor Green
} else {
    Write-Host "✅ Already authenticated to correct tenant and subscription" -ForegroundColor Green
}

if ($needsLogin) {
    Write-Host "🔐 Logging in to Azure..." -ForegroundColor Yellow
    az login --tenant $TENANT_B | Out-Null
    az account set --subscription $SUB_B
    
    # Verify context
    $currentSub = az account show --query "id" -o tsv
    if ($currentSub -ne $SUB_B) {
        Write-Error "Failed to set correct subscription context. Expected: $SUB_B, Got: $currentSub"
        exit 1
    }
    Write-Host "✅ Successfully authenticated and set context to subscription: $SUB_B" -ForegroundColor Green
} else {
    Write-Host "✅ Using existing authentication context" -ForegroundColor Green
}

# Check VM status and start if needed
Write-Host "🔍 Checking VM status..." -ForegroundColor Yellow
$powerState = az vm show -g $RG_B -n $VM_NAME -d --query "powerState" -o tsv
$wasHibernated = $false

if ($powerState -eq "VM deallocated") {
    Write-Host "🛌 VM is hibernated/deallocated" -ForegroundColor Yellow
    $wasHibernated = $true
} elseif ($powerState -ne "VM running") {
    Write-Host "⚠️ VM is in state: $powerState" -ForegroundColor Yellow
}

if ($powerState -ne "VM running") {
    Write-Host "🚀 Starting VM..." -ForegroundColor Yellow
    az vm start -g $RG_B -n $VM_NAME | Out-Null
    
    # Wait for VM to be fully started
    do {
        Start-Sleep -Seconds 5
        $powerState = az vm show -g $RG_B -n $VM_NAME -d --query "powerState" -o tsv
        Write-Host "  Status: $powerState" -ForegroundColor Cyan
    } while ($powerState -ne "VM running")
    
    # Additional wait if VM was hibernated (needs time to fully resume services)
    if ($wasHibernated) {
        Write-Host "⏱️ VM was hibernated - waiting $HIBERNATION_RESUME_WAIT seconds for full resume..." -ForegroundColor Yellow
        for ($i = $HIBERNATION_RESUME_WAIT; $i -gt 0; $i--) {
            Write-Progress -Activity "Waiting for hibernation resume" -Status "$i seconds remaining" -PercentComplete (($HIBERNATION_RESUME_WAIT-$i)/$HIBERNATION_RESUME_WAIT*100)
            Start-Sleep -Seconds 1
        }
        Write-Progress -Activity "Waiting for hibernation resume" -Completed
        Write-Host "✅ Hibernation resume wait completed" -ForegroundColor Green
    }
} else {
    Write-Host "✅ VM is already running" -ForegroundColor Green
}

# Get VM public IP
Write-Host "🌐 Getting VM connection details..." -ForegroundColor Yellow
$publicIP = az vm show -g $RG_B -n $VM_NAME -d --query "publicIps" -o tsv

if (-not $publicIP) {
    Write-Error "No public IP found for VM. Cannot establish RDP connection."
    exit 1
}

Write-Host "🔗 Connecting to: $publicIP" -ForegroundColor Cyan

# Connect via RDP
Write-Host "🖥️ Launching RDP connection..." -ForegroundColor Yellow
$rdpProcess = Start-Process "mstsc" -ArgumentList "/v:$publicIP" -WindowStyle Normal -PassThru

Write-Host "✅ RDP connection launched!" -ForegroundColor Green
Write-Host "💡 Username: shabi108" -ForegroundColor Yellow
Write-Host "🔐 Enter your password when prompted" -ForegroundColor Yellow

# Start hibernation monitoring in separate window immediately after RDP launches
Write-Host "`n🛌 Starting hibernation monitor in separate window..." -ForegroundColor Cyan
$delayMinutes = [math]::Round($HIBERNATION_DELAY_SECONDS / 60, 1)
Write-Host "   VM will hibernate $delayMinutes minutes after RDP window closes" -ForegroundColor Yellow

# Get the directory where this script is located
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$hibernationMonitorScript = Join-Path $scriptDirectory "hibernation-monitor.ps1"

# Verify the hibernation monitor script exists
if (-not (Test-Path $hibernationMonitorScript)) {
    Write-Error "Hibernation monitor script not found at: $hibernationMonitorScript"
    Write-Host "💡 Ensure hibernation-monitor.ps1 is in the same directory as this script" -ForegroundColor Yellow
    exit 1
}

# Start monitoring in separate PowerShell window with configurable visibility
$visibleParam = if ($MONITOR_WINDOW_VISIBLE) { "true" } else { "false" }
$monitorArguments = @(
    "-ExecutionPolicy Bypass"
    "-File `"$hibernationMonitorScript`""
    "-RG_B `"$RG_B`""
    "-VM_NAME `"$VM_NAME`""
    "-HIBERNATION_DELAY_SECONDS $HIBERNATION_DELAY_SECONDS"
    "-PROGRESS_UPDATE_INTERVAL $PROGRESS_UPDATE_INTERVAL"
    "-rdpProcessId $($rdpProcess.Id)"
    "-Visible $visibleParam"
)

$windowStyle = if ($MONITOR_WINDOW_VISIBLE) { "Normal" } else { "Hidden" }
$monitorProcess = Start-Process "powershell.exe" -ArgumentList $monitorArguments -WindowStyle $windowStyle -PassThru

$visibilityText = if ($MONITOR_WINDOW_VISIBLE) { "visible" } else { "hidden" }
Write-Host "✅ Hibernation monitor started in $visibilityText window (PID: $($monitorProcess.Id))" -ForegroundColor Green
Write-Host "💡 This window can now be closed safely - monitoring continues independently" -ForegroundColor Cyan
Write-Host "🔧 Monitor script: hibernation-monitor.ps1" -ForegroundColor Gray
if ($MONITOR_WINDOW_VISIBLE) {
    Write-Host "🐛 Monitor window is visible for debugging - set `$MONITOR_WINDOW_VISIBLE = `$false to hide" -ForegroundColor Yellow
}
