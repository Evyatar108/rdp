$ErrorActionPreference = "Stop"

# Load configuration
. (Join-Path $PSScriptRoot "config-loader.ps1")
$config = Get-VMRdpConfig

# Extract configuration values
$TENANT_B = $config.azure.target.tenantId
$SUB_B = $config.azure.target.subscriptionId
$RG_B = $config.azure.target.resourceGroup
$VM_NAME = $config.azure.target.vmName

Write-Host " Stopping Azure VM..." -ForegroundColor Green
Write-Host "=====================" -ForegroundColor Green

if ($config.logging.verboseOutput) {
    Write-Host "Configuration loaded:" -ForegroundColor Cyan
    Write-Host "   Tenant: $TENANT_B" -ForegroundColor Gray
    Write-Host "   Subscription: $SUB_B" -ForegroundColor Gray
    Write-Host "   Resource Group: $RG_B" -ForegroundColor Gray
    Write-Host "   VM Name: $VM_NAME" -ForegroundColor Gray
    Write-Host ""
}

# Use shared Azure authentication helper
. (Join-Path $PSScriptRoot "azure-auth-helper.ps1")
Ensure-AzureCLIAuthenticated -TenantId $TENANT_B -SubscriptionId $SUB_B

# Check current VM status
Write-Host " Checking VM status..." -ForegroundColor Yellow
$powerState = az vm show -g $RG_B -n $VM_NAME -d --query "powerState" -o tsv

if (-not $powerState) {
    Write-Error "Unable to retrieve VM status. Check if the VM exists and you have access."
    exit 1
}

Write-Host " Current VM status: $powerState" -ForegroundColor Cyan

if ($powerState -eq "VM deallocated" -or $powerState -eq "VM stopped") {
    Write-Host "" 
    Write-Host " VM is already stopped" -ForegroundColor Yellow
    Write-Host " No action needed" -ForegroundColor Gray
    exit 0
}

# Stop the VM
Write-Host " Initiating VM stop..." -ForegroundColor Yellow
Write-Host " This will perform a graceful shutdown and deallocate the VM" -ForegroundColor Gray

try {
    az vm deallocate -g $RG_B -n $VM_NAME --no-wait
    Write-Host " Stop command sent successfully!" -ForegroundColor Green
    Write-Host "" 
    Write-Host " The VM is now stopping..." -ForegroundColor Yellow
    Write-Host "   The guest OS will shut down gracefully" -ForegroundColor Gray
    Write-Host "   Resources will be deallocated to save costs" -ForegroundColor Gray
    Write-Host ""
    Write-Host " Monitoring stop progress..." -ForegroundColor Cyan
    
    # Wait a moment for the stop to begin
    Start-Sleep -Seconds 3
    
    # Monitor the stop process
    $stopComplete = $false
    $statusChecks = 0
    $maxChecks = 60 # Maximum 5 minutes (60 * 5 seconds)
    
    while (-not $stopComplete -and $statusChecks -lt $maxChecks) {
        $statusChecks++
        $currentState = az vm show -g $RG_B -n $VM_NAME -d --query "powerState" -o tsv
        
        Write-Host "  Status check $statusChecks : $currentState" -ForegroundColor Cyan
        
        if ($currentState -eq "VM deallocated") {
            $stopComplete = $true
            Write-Host "" 
            Write-Host " VM stopped successfully!" -ForegroundColor Green
            Write-Host " The VM is now deallocated and not incurring compute costs" -ForegroundColor Green
        }
        else {
            Start-Sleep -Seconds 5
        }
    }
    
    if (-not $stopComplete) {
        Write-Host "" 
        Write-Host " VM stop is taking longer than expected" -ForegroundColor Yellow
        Write-Host " The VM may still be stopping - check Azure portal for status" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Failed to stop VM: $_"
    exit 1
}