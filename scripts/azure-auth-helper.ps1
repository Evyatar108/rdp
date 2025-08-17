# Shared Azure CLI Authentication Helper
# Used by multiple scripts to ensure consistent authentication

function Ensure-AzureCLIInstalled {
    param([switch]$Quiet)

    $azCliPath = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCliPath) {
        if (-not $Quiet) { Write-Host "🧩 Azure CLI not found. Installing via winget..." -ForegroundColor Yellow }
        try {
            if (-not $Quiet) { Write-Host "➡️ winget install --exact --id Microsoft.AzureCLI" -ForegroundColor Gray }
            winget install --exact --id Microsoft.AzureCLI

            if ($LASTEXITCODE -eq 0) {
                if (-not $Quiet) { Write-Host "✅ Azure CLI installed successfully" -ForegroundColor Green }
                # Refresh PATH for current session
                $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Machine) + ";" + [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::User)
                # Verify availability
                $azCliPath = Get-Command az -ErrorAction SilentlyContinue
                if (-not $azCliPath -and -not $Quiet) {
                    Write-Host "⚠️ Azure CLI installed but not yet in PATH. A new session may be required." -ForegroundColor Yellow
                }
            } else {
                throw "winget install failed with exit code: $LASTEXITCODE"
            }
        } catch {
            Write-Host "❌ Failed to install Azure CLI via winget: $_" -ForegroundColor Red
            throw "Azure CLI installation failed"
        }
    } else {
        if (-not $Quiet) { Write-Host "✅ Azure CLI found at: $($azCliPath.Source)" -ForegroundColor Green }
    }
}

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
        if (-not $Quiet) { Write-Host "⚠️ Wrong tenant (current: $($currentAccount.tenantId), required: $TenantId)" -ForegroundColor Yellow }
        $needsLogin = $true
    }
    elseif ($currentAccount.id -ne $SubscriptionId) {
        if (-not $Quiet) { Write-Host "⚠️ Wrong subscription (current: $($currentAccount.id), required: $SubscriptionId)" -ForegroundColor Yellow }
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
            throw "Failed to set correct subscription context. Expected: $SubscriptionId, Got: $currentSub"
        }
        if (-not $Quiet) { Write-Host "✅ Successfully authenticated and set context to subscription: $SubscriptionId" -ForegroundColor Green }
    }
    else {
        if (-not $Quiet) { Write-Host "✅ Using existing authentication context" -ForegroundColor Green }
    }
}