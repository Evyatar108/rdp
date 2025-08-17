# Shared Azure CLI Authentication Helper
# Used by multiple scripts to ensure consistent authentication

function Ensure-AzureCLIAuthenticated {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [switch]$Quiet
    )
    
    if (-not $Quiet) {
        Write-Host "📋 Checking Azure authentication..." -ForegroundColor Yellow
    }
    
    $currentAccount = az account show 2>$null | ConvertFrom-Json
    $needsLogin = $false

    if (-not $currentAccount) {
        if (-not $Quiet) { Write-Host "⚠️ Not logged in to Azure" -ForegroundColor Yellow }
        $needsLogin = $true
    }
    elseif ($currentAccount.tenantId -ne $TenantId) {
        if (-not $Quiet) { Write-Host ("⚠️ Wrong tenant (current: {0}, required: {1})" -f $currentAccount.tenantId, $TenantId) -ForegroundColor Yellow }
        $needsLogin = $true
    }
    elseif ($currentAccount.id -ne $SubscriptionId) {
        if (-not $Quiet) { Write-Host ("⚠️ Wrong subscription (current: {0}, required: {1})" -f $currentAccount.id, $SubscriptionId) -ForegroundColor Yellow }
        # Just set the subscription, no need to re-login
        az account set --subscription $SubscriptionId
        if (-not $Quiet) { Write-Host "✅ Switched to correct subscription" -ForegroundColor Green }
    }
    else {
        if (-not $Quiet) { Write-Host "✅ Already authenticated to correct tenant and subscription" -ForegroundColor Green }
    }

    if ($needsLogin) {
        if (-not $Quiet) { Write-Host "🔐 Logging in to Azure..." -ForegroundColor Yellow }
        az login --tenant $TenantId | Out-Null
        az account set --subscription $SubscriptionId
        
        # Verify context
        $currentSub = az account show --query "id" -o tsv
        if ($currentSub -ne $SubscriptionId) {
            throw ("Failed to set correct subscription context. Expected: {0}, Got: {1}" -f $SubscriptionId, $currentSub)
        }
        if (-not $Quiet) { Write-Host "✅ Successfully authenticated and set context to subscription: $SubscriptionId" -ForegroundColor Green }
    } else {
        if (-not $Quiet) { Write-Host "✅ Using existing authentication context" -ForegroundColor Green }
    }
}

function Ensure-AzureCLIInstalled {
    param([switch]$Quiet)
    
    # Check if Azure CLI is installed
    $azCliPath = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCliPath) {
        if (-not $Quiet) { Write-Host "Azure CLI not found. Installing Azure CLI using winget..." -ForegroundColor Yellow }
        
        try {
            if (-not $Quiet) { Write-Host "Running: winget install --exact --id Microsoft.AzureCLI" -ForegroundColor Gray }
            winget install --exact --id Microsoft.AzureCLI
            
            if ($LASTEXITCODE -eq 0) {
                if (-not $Quiet) { Write-Host "Azure CLI installed successfully" -ForegroundColor Green }
                # Refresh PATH
                $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Machine) + ";" + [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::User)
            }
            else {
                throw "winget install failed with exit code: $LASTEXITCODE"
            }
        }
        catch {
            Write-Host "Failed to install Azure CLI via winget: $_" -ForegroundColor Red
            throw "Azure CLI installation failed"
        }
    }
    else {
        if (-not $Quiet) { Write-Host "Azure CLI found at: $($azCliPath.Source)" -ForegroundColor Green }
    }
}