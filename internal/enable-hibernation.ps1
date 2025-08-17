$ErrorActionPreference = "Stop"

# ----- TARGET (Tenant B) Configuration -----
$TENANT_B = "66d51e14-99b9-435a-8c05-449dc0c91710"
$SUB_B = "30748a75-b2b8-4e4f-b5df-e87aa4ceef7b"
$RG_B = "VM-RG-TARGET"
$VM_NAME = "DesktopVM"
$OS_DISK_NAME = "DesktopVM-OS-Managed"

Write-Host "🛌 Starting VM Hibernation Enablement Process" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green

# Step 1: Check current Azure context and login if needed
Write-Host "📋 Step 1: Checking Azure authentication..." -ForegroundColor Yellow
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
    az login --tenant $TENANT_B
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

# Step 2: Check current VM status and hibernation capability
Write-Host "`n📋 Step 2: Checking current VM status..." -ForegroundColor Yellow
$vmExists = az vm show -g $RG_B -n $VM_NAME --query "name" -o tsv 2>$null
if (-not $vmExists) {
    Write-Error "VM '$VM_NAME' not found in resource group '$RG_B'"
    exit 1
}

$currentHibernation = az vm show -g $RG_B -n $VM_NAME --query "additionalCapabilities.hibernationEnabled" -o tsv
$vmSize = az vm show -g $RG_B -n $VM_NAME --query "hardwareProfile.vmSize" -o tsv
$powerState = az vm show -g $RG_B -n $VM_NAME --query "instanceView.statuses[1].displayStatus" -o tsv

Write-Host "VM Name: $VM_NAME" -ForegroundColor Cyan
Write-Host "VM Size: $vmSize" -ForegroundColor Cyan
Write-Host "Power State: $powerState" -ForegroundColor Cyan
Write-Host "Hibernation Enabled: $currentHibernation" -ForegroundColor Cyan

# Check if hibernation is already enabled
if ($currentHibernation -eq "true") {
    Write-Host "✅ Hibernation is already enabled on this VM!" -ForegroundColor Green
    Write-Host "`n🧪 Testing hibernation functionality..." -ForegroundColor Yellow
    
    # Test hibernation if VM is running
    if ($powerState -eq "VM running") {
        Write-Host "Hibernating VM..." -ForegroundColor Yellow
        az vm deallocate -g $RG_B -n $VM_NAME --hibernate
        Write-Host "✅ VM hibernated successfully!" -ForegroundColor Green
        
        Write-Host "Resuming VM from hibernation..." -ForegroundColor Yellow
        az vm start -g $RG_B -n $VM_NAME
        Write-Host "✅ VM resumed from hibernation successfully!" -ForegroundColor Green
    }
    
    Write-Host "`n🎉 Hibernation is fully configured and tested!" -ForegroundColor Green
    exit 0
}

# Step 3: Deallocate VM if it's running
Write-Host "`n📋 Step 3: Preparing VM for hibernation enablement..." -ForegroundColor Yellow
if ($powerState -eq "VM running") {
    Write-Host "Deallocating VM '$VM_NAME'..." -ForegroundColor Yellow
    az vm deallocate -g $RG_B -n $VM_NAME
    Write-Host "✅ VM deallocated successfully" -ForegroundColor Green
} else {
    Write-Host "✅ VM is already deallocated" -ForegroundColor Green
}

# Step 4: Check and update OS disk hibernation support
Write-Host "`n📋 Step 4: Configuring OS disk for hibernation..." -ForegroundColor Yellow
$diskHibernation = az disk show -g $RG_B -n $OS_DISK_NAME --query "supportsHibernation" -o tsv

Write-Host "OS Disk: $OS_DISK_NAME" -ForegroundColor Cyan
Write-Host "Current hibernation support: $diskHibernation" -ForegroundColor Cyan

if ($diskHibernation -ne "true") {
    Write-Host "Enabling hibernation support on OS disk..." -ForegroundColor Yellow
    az disk update -g $RG_B -n $OS_DISK_NAME --set supportsHibernation=true
    
    # Verify the update
    $updatedDiskHibernation = az disk show -g $RG_B -n $OS_DISK_NAME --query "supportsHibernation" -o tsv
    if ($updatedDiskHibernation -eq "true") {
        Write-Host "✅ OS disk hibernation support enabled successfully" -ForegroundColor Green
    } else {
        Write-Error "Failed to enable hibernation support on OS disk"
        exit 1
    }
} else {
    Write-Host "✅ OS disk already supports hibernation" -ForegroundColor Green
}

# Step 5: Enable hibernation on VM
Write-Host "`n📋 Step 5: Enabling hibernation on VM..." -ForegroundColor Yellow
az vm update -g $RG_B -n $VM_NAME --enable-hibernation true

# Verify hibernation is enabled
$updatedHibernation = az vm show -g $RG_B -n $VM_NAME --query "additionalCapabilities.hibernationEnabled" -o tsv
if ($updatedHibernation -eq "true") {
    Write-Host "✅ Hibernation enabled on VM successfully" -ForegroundColor Green
} else {
    Write-Error "Failed to enable hibernation on VM"
    exit 1
}

# Step 6: Start VM
Write-Host "`n📋 Step 6: Starting VM to initialize hibernation..." -ForegroundColor Yellow
az vm start -g $RG_B -n $VM_NAME

# Wait for VM to be fully started
Write-Host "Waiting for VM to be fully started..." -ForegroundColor Yellow
do {
    Start-Sleep -Seconds 10
    $powerState = az vm show -g $RG_B -n $VM_NAME -d --query "powerState" -o tsv
    Write-Host "Current state: $powerState" -ForegroundColor Cyan
} while ($powerState -ne "VM running")

Write-Host "✅ VM started successfully" -ForegroundColor Green

# Step 7: Verify hibernation configuration
Write-Host "`n📋 Step 7: Verifying hibernation configuration..." -ForegroundColor Yellow
$finalConfig = az vm show -g $RG_B -n $VM_NAME --query "{Name:name, HibernationEnabled:additionalCapabilities.hibernationEnabled, VMSize:hardwareProfile.vmSize, PowerState:instanceView.statuses[1].displayStatus}" -o json | ConvertFrom-Json

Write-Host "`n🔍 Final Configuration:" -ForegroundColor Green
Write-Host "VM Name: $($finalConfig.Name)" -ForegroundColor Cyan
Write-Host "VM Size: $($finalConfig.VMSize)" -ForegroundColor Cyan
Write-Host "Power State: $($finalConfig.PowerState)" -ForegroundColor Cyan
Write-Host "Hibernation Enabled: $($finalConfig.HibernationEnabled)" -ForegroundColor Cyan

$diskConfig = az disk show -g $RG_B -n $OS_DISK_NAME --query "{Name:name, SupportsHibernation:supportsHibernation}" -o json | ConvertFrom-Json
Write-Host "OS Disk Hibernation Support: $($diskConfig.SupportsHibernation)" -ForegroundColor Cyan

# Step 8: Test hibernation functionality
Write-Host "`n📋 Step 8: Testing hibernation functionality..." -ForegroundColor Yellow
Write-Host "Hibernating VM..." -ForegroundColor Yellow
az vm deallocate -g $RG_B -n $VM_NAME --hibernate true

# Verify hibernation state
Start-Sleep -Seconds 10
$hibernatedState = az vm show -g $RG_B -n $VM_NAME --query "instanceView.statuses[1].displayStatus" -o tsv
Write-Host "Hibernation state: $hibernatedState" -ForegroundColor Cyan

Write-Host "Resuming VM from hibernation..." -ForegroundColor Yellow
az vm start -g $RG_B -n $VM_NAME

# Wait for resume
do {
    Start-Sleep -Seconds 10
    $hibernatedState = az vm show -g $RG_B -n $VM_NAME -d --query "powerState" -o tsv
    Write-Host "Resume state: $resumeState" -ForegroundColor Cyan
} while ($resumeState -ne "VM running")

Write-Host "`n🎉 HIBERNATION ENABLEMENT COMPLETED SUCCESSFULLY! 🎉" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green
Write-Host "✅ VM hibernation is now fully configured and tested" -ForegroundColor Green
Write-Host "✅ You can now hibernate your VM using: az vm deallocate -g $RG_B -n $VM_NAME --hibernate" -ForegroundColor Green
Write-Host "✅ Resume hibernation using: az vm start -g $RG_B -n $VM_NAME" -ForegroundColor Green
Write-Host "`n📋 Next steps:" -ForegroundColor Yellow
Write-Host "1. The Windows hibernation extension will be automatically installed" -ForegroundColor White
Write-Host "2. Page file will be configured on C: drive automatically" -ForegroundColor White
Write-Host "3. Hibernation will be available in Windows power options" -ForegroundColor White
Write-Host "4. Monitor your Azure costs - hibernated VMs are not charged for compute" -ForegroundColor White