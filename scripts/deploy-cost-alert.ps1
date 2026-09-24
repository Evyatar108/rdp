# Deploy the subscription cost alert (Azure Consumption budget)
#
# Creates or updates a monthly budget that emails when spend crosses the
# configured amount. Safe to re-run: the same configuration always converges
# to the same budget.
#
# The Azure CLI's `az consumption budget create` cannot attach email
# notifications, so this uses the Consumption REST API directly.

param(
    [switch]$Remove,
    [switch]$Status
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "config-loader.ps1")
$config = Get-VMRdpConfig

$subscriptionId = $config.azure.target.subscriptionId
$tenantId = $config.azure.target.tenantId
$costAlert = $config.costAlert
$budgetName = $costAlert.budgetName
$apiVersion = "2021-10-01"
$budgetUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Consumption/budgets/$budgetName" + "?api-version=$apiVersion"

Write-Host "Azure Cost Alert Deployment" -ForegroundColor Green
Write-Host "===========================" -ForegroundColor Green

. (Join-Path $PSScriptRoot "azure-auth-helper.ps1")

# Every call below passes -subscription explicitly, so this script does not
# need the machine's default CLI context to point at the target subscription
# and must not change it. Only log in when the subscription is genuinely
# unreachable, which avoids disturbing an unrelated active context.
function Test-TargetSubscriptionAccess {
    az account show --subscription $subscriptionId --only-show-errors 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

Ensure-AzureCLIInstalled -Quiet
if (-not (Test-TargetSubscriptionAccess)) {
    Write-Host "Target subscription not reachable with cached credentials - signing in..." -ForegroundColor Yellow
    Ensure-AzureCLIAuthenticated -TenantId $tenantId -SubscriptionId $subscriptionId
    if (-not (Test-TargetSubscriptionAccess)) {
        throw "Cannot access subscription $subscriptionId after sign-in"
    }
}

function Get-Budget {
    $existing = az rest --method get --url $budgetUrl --subscription $subscriptionId --only-show-errors 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing) {
        return $existing | ConvertFrom-Json
    }
    return $null
}

function Show-Budget {
    param($Budget)

    if (-not $Budget) {
        Write-Host "No budget named '$budgetName' exists on this subscription." -ForegroundColor Yellow
        return
    }

    Write-Host "Budget:        $($Budget.name)" -ForegroundColor Cyan
    Write-Host "  Amount:      $($Budget.properties.amount) $($Budget.properties.currentSpend.unit)" -ForegroundColor Gray
    Write-Host "  Time grain:  $($Budget.properties.timeGrain)" -ForegroundColor Gray
    if ($Budget.properties.currentSpend) {
        Write-Host "  Spent now:   $($Budget.properties.currentSpend.amount) $($Budget.properties.currentSpend.unit)" -ForegroundColor Gray
    }
    if ($Budget.properties.forecastSpend) {
        Write-Host "  Forecast:    $($Budget.properties.forecastSpend.amount) $($Budget.properties.forecastSpend.unit)" -ForegroundColor Gray
    }

    foreach ($key in $Budget.properties.notifications.PSObject.Properties.Name) {
        $notification = $Budget.properties.notifications.$key
        $recipients = $notification.contactEmails -join ", "
        Write-Host "  Alert '$key': $($notification.thresholdType) $($notification.operator) $($notification.threshold)% -> $recipients" -ForegroundColor Gray
    }
}

if ($Status) {
    Show-Budget -Budget (Get-Budget)
    return
}

if ($Remove) {
    Write-Host "Removing budget '$budgetName'..." -ForegroundColor Yellow
    az rest --method delete --url $budgetUrl --subscription $subscriptionId --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to remove budget '$budgetName'"
    }
    Write-Host "Budget removed." -ForegroundColor Green
    return
}

if (-not $costAlert.enabled) {
    Write-Host "costAlert.enabled is false in config.json - nothing to deploy." -ForegroundColor Yellow
    Write-Host "Set it to true, or run with -Remove to delete an existing budget." -ForegroundColor Gray
    return
}

$emails = @($costAlert.contactEmails | Where-Object { $_ -and $_.Trim() })
if ($emails.Count -eq 0) {
    throw "costAlert.contactEmails is empty. Azure rejects a budget alert with no recipients."
}

$amount = [double]$costAlert.monthlyAmountUsd
if ($amount -le 0) {
    throw "costAlert.monthlyAmountUsd must be greater than zero (got '$($costAlert.monthlyAmountUsd)')."
}

# Azure requires a monthly budget to start on the first day of a month.
# Preserve the original start date on re-runs so history is not reset.
$existingBudget = Get-Budget
if ($existingBudget -and $existingBudget.properties.timePeriod.startDate) {
    $startDate = ([datetime]$existingBudget.properties.timePeriod.startDate).ToUniversalTime().ToString("yyyy-MM-01T00:00:00Z")
}
else {
    $startDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-01T00:00:00Z")
}
$endDate = ([datetime]$startDate).AddYears(10).ToString("yyyy-MM-01T00:00:00Z")

$notifications = [ordered]@{
    "Actual_GreaterThan_100_Percent" = [ordered]@{
        enabled       = $true
        operator      = "GreaterThan"
        threshold     = 100
        contactEmails = $emails
        thresholdType = "Actual"
    }
}

if ($costAlert.forecastAlert) {
    $notifications["Forecasted_GreaterThan_100_Percent"] = [ordered]@{
        enabled       = $true
        operator      = "GreaterThan"
        threshold     = 100
        contactEmails = $emails
        thresholdType = "Forecasted"
    }
}

$body = [ordered]@{
    properties = [ordered]@{
        category      = "Cost"
        amount        = $amount
        timeGrain     = "Monthly"
        timePeriod    = [ordered]@{
            startDate = $startDate
            endDate   = $endDate
        }
        notifications = $notifications
    }
}

# Pass the payload as a file. Inline JSON on the az command line is mangled
# by PowerShell quoting rules.
$bodyFile = Join-Path ([IO.Path]::GetTempPath()) "azure-budget-$budgetName.json"
$body | ConvertTo-Json -Depth 6 | Set-Content -Path $bodyFile -Encoding UTF8

try {
    Write-Host "Deploying budget '$budgetName'..." -ForegroundColor Yellow
    Write-Host "  Amount:    $amount USD per month" -ForegroundColor Gray
    Write-Host "  Starts:    $startDate" -ForegroundColor Gray
    Write-Host "  Recipients: $($emails -join ', ')" -ForegroundColor Gray
    Write-Host "  Forecast alert: $([bool]$costAlert.forecastAlert)" -ForegroundColor Gray

    az rest --method put --url $budgetUrl --subscription $subscriptionId --headers "Content-Type=application/json" --body "@$bodyFile" --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Budget deployment failed"
    }
}
finally {
    Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
}

Write-Host "Budget deployed." -ForegroundColor Green
Write-Host ""
Show-Budget -Budget (Get-Budget)
