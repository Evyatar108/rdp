# Shared Azure CLI Authentication Helper
# Used by multiple scripts to ensure consistent authentication

function Ensure-AzureCLIInstalled {
    param([switch]$Quiet)

    # First check if az command is available
    $azCliPath = Get-Command az -ErrorAction SilentlyContinue
    if ($azCliPath) {
        if (-not $Quiet) { Write-Host "✅ Azure CLI found at: $($azCliPath.Source)" -ForegroundColor Green }
        return
    }

    # If not found, try to refresh PATH first
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Machine) + ";" + [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::User)
    $azCliPath = Get-Command az -ErrorAction SilentlyContinue
    if ($azCliPath) {
        if (-not $Quiet) { Write-Host "✅ Azure CLI found after PATH refresh: $($azCliPath.Source)" -ForegroundColor Green }
        return
    }

    # Still not found, try to install
    if (-not $Quiet) { Write-Host "🧩 Azure CLI not found. Installing via winget..." -ForegroundColor Yellow }
    try {
        if (-not $Quiet) { Write-Host "➡️ winget install --exact --id Microsoft.AzureCLI" -ForegroundColor Gray }
        winget install --exact --id Microsoft.AzureCLI

        # Accept both success (0) and "already installed" type codes
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
            if (-not $Quiet) { Write-Host "✅ Azure CLI install/upgrade completed" -ForegroundColor Green }
            # Refresh PATH again
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Machine) + ";" + [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::User)
            $azCliPath = Get-Command az -ErrorAction SilentlyContinue
            if (-not $azCliPath -and -not $Quiet) {
                Write-Host "⚠️ Azure CLI processed but not yet in PATH. A new session may be required." -ForegroundColor Yellow
            }
        }
        else {
            throw "winget install failed with exit code: $LASTEXITCODE"
        }
    }
    catch {
        Write-Host "❌ Failed to install Azure CLI via winget: $_" -ForegroundColor Red
        throw "Azure CLI installation failed"
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

    $currentAccount = az account show 2>$null | ConvertFrom-Json
    $needsLogin = $false

    if (-not $currentAccount) {
        $needsLogin = $true
    } elseif ($currentAccount.tenantId -ne $TenantId) {
        $needsLogin = $true
    } elseif ($currentAccount.id -ne $SubscriptionId) {
        az account set --subscription $SubscriptionId
    }

    if ($needsLogin) {
        az login --tenant $TenantId | Out-Null
        az account set --subscription $SubscriptionId
        
        $currentSub = az account show --query "id" -o tsv
        if ($currentSub -ne $SubscriptionId) {
            throw "Failed to set correct subscription context"
        }
    }
}