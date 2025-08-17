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
    Write-Host "✅ Successfully authenticated" -ForegroundColor Green
}
# Check VM status and start if needed
Write-Host "🔍 Checking VM status..." -ForegroundColor Yellow
$powerState = az vm show -g $RG_B -n $VM_NAME -d --query "powerState" -o tsv

if ($powerState -ne "VM running") {
    Write-Host "🚀 Starting VM..." -ForegroundColor Yellow
    az vm start -g $RG_B -n $VM_NAME | Out-Null
    
    # Wait for VM to be fully started
    do {
        Start-Sleep -Seconds 5
        $powerState = az vm show -g $RG_B -n $VM_NAME -d --query "powerState" -o tsv
        Write-Host "  Status: $powerState" -ForegroundColor Cyan
    } while ($powerState -ne "VM running")
}

Write-Host "✅ VM is running" -ForegroundColor Green

# Get VM public IP
Write-Host "🌐 Getting VM connection details..." -ForegroundColor Yellow
$publicIP = az vm show -g $RG_B -n $VM_NAME -d --query "publicIps" -o tsv

if (-not $publicIP) {
    Write-Error "No public IP found for VM. Cannot establish RDP connection."
    exit 1
}

Write-Host "🔗 Connecting to: $publicIP" -ForegroundColor Cyan

# Connect via RDP and monitor for auto-hibernation
Write-Host "🖥️ Launching RDP connection..." -ForegroundColor Yellow
$rdpProcess = Start-Process "mstsc" -ArgumentList "/v:$publicIP" -WindowStyle Normal -PassThru

Write-Host "✅ RDP connection launched!" -ForegroundColor Green
Write-Host "💡 Username: shabi108" -ForegroundColor Yellow
Write-Host "🔐 Enter your password when prompted" -ForegroundColor Yellow

# Monitor RDP process and hibernate when it closes
Write-Host "`n🛌 Auto-hibernation monitoring enabled..." -ForegroundColor Cyan
Write-Host "   VM will hibernate 2 minutes after RDP window closes" -ForegroundColor Yellow
Write-Host "   Press Ctrl+C to disable auto-hibernation" -ForegroundColor Yellow

try {
    # Wait for RDP process to exit
    $rdpProcess.WaitForExit()
    Write-Host "`n🔌 RDP connection closed" -ForegroundColor Yellow
    
    # Wait before hibernating (gives time to reconnect if needed)
    $delayMinutes = [math]::Round($HIBERNATION_DELAY_SECONDS / 60, 1)
    Write-Host "⏱️ Waiting $delayMinutes minutes before hibernating VM..." -ForegroundColor Yellow
    Write-Host "   (Press Ctrl+C to cancel hibernation)" -ForegroundColor Gray
    
    for ($i = $HIBERNATION_DELAY_SECONDS; $i -gt 0; $i--) {
        Write-Progress -Activity "Auto-hibernation countdown" -Status "$i seconds remaining" -PercentComplete (($HIBERNATION_DELAY_SECONDS-$i)/$HIBERNATION_DELAY_SECONDS*100)
        Start-Sleep -Seconds $PROGRESS_UPDATE_INTERVAL
    }
    
    Write-Progress -Activity "Auto-hibernation countdown" -Completed
    
    # Hibernate the VM
    Write-Host "`n🛌 Hibernating VM..." -ForegroundColor Green
    try {
        $hibernateResult = az vm deallocate -g $RG_B -n $VM_NAME --hibernate true 2>&1 | ConvertFrom-Json
        
        if ($hibernateResult) {
            Write-Host "✅ VM hibernated successfully!" -ForegroundColor Green
            Write-Host "💰 VM is now in hibernated state (no compute charges)" -ForegroundColor Cyan
            Write-Host "🔄 Run this script again to resume and reconnect" -ForegroundColor Yellow
        } else {
            Write-Host "✅ VM hibernation completed (no output)" -ForegroundColor Green
            Write-Host "💰 VM is now in hibernated state (no compute charges)" -ForegroundColor Cyan
            Write-Host "🔄 Run this script again to resume and reconnect" -ForegroundColor Yellow
        }
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Host "❌ Failed to hibernate VM: $errorMessage" -ForegroundColor Red
        
        # Parse Azure CLI error if available
        if ($errorMessage -match "\{.*\}") {
            try {
                $errorJson = $errorMessage | ConvertFrom-Json
                if ($errorJson.error) {
                    Write-Host "   Error Code: $($errorJson.error.code)" -ForegroundColor Yellow
                    Write-Host "   Error Message: $($errorJson.error.message)" -ForegroundColor Yellow
                }
            } catch {
                # Error parsing failed, show raw message
                Write-Host "   Raw error: $errorMessage" -ForegroundColor Yellow
            }
        }
    }
    
} catch [System.Management.Automation.PipelineStoppedException] {
    Write-Host "`n⚠️ Auto-hibernation cancelled by user" -ForegroundColor Yellow
    Write-Host "VM remains running" -ForegroundColor Cyan
} catch {
    Write-Host "`n❌ Error during hibernation monitoring: $_" -ForegroundColor Red
}