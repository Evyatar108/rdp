$ErrorActionPreference = "Stop"

# Load configuration
. (Join-Path $PSScriptRoot "config-loader.ps1")
$config = Get-VMRdpConfig

# Extract configuration values
$TENANT_B = $config.azure.target.tenantId
$SUB_B = $config.azure.target.subscriptionId
$RG_B = $config.azure.target.resourceGroup
$VM_NAME = $config.azure.target.vmName

$HIBERNATION_DELAY_SECONDS = $config.hibernation.timing.delayAfterRdpCloseSeconds
$PROGRESS_UPDATE_INTERVAL = $config.hibernation.timing.progressUpdateIntervalSeconds
$HIBERNATION_RESUME_WAIT = $config.hibernation.timing.hibernationResumeWaitSeconds
$MONITOR_WINDOW_VISIBLE = $config.hibernation.showMonitorWindow

Write-Host " Connecting to Azure VM via RDP..." -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green

if ($config.logging.verboseOutput) {
    Write-Host "Configuration loaded:" -ForegroundColor Cyan
    Write-Host "   Tenant: $TENANT_B" -ForegroundColor Gray
    Write-Host "   Subscription: $SUB_B" -ForegroundColor Gray
    Write-Host "   Resource Group: $RG_B" -ForegroundColor Gray
    Write-Host "   VM Name: $VM_NAME" -ForegroundColor Gray
    Write-Host "   Hibernation Delay: $HIBERNATION_DELAY_SECONDS seconds" -ForegroundColor Gray
    Write-Host ""
}

# Use shared Azure authentication helper
. (Join-Path $PSScriptRoot "azure-auth-helper.ps1")
Ensure-AzureCLIAuthenticated -TenantId $TENANT_B -SubscriptionId $SUB_B

# Check VM status and start if needed
Write-Host " Checking VM status..." -ForegroundColor Yellow
$powerState = az vm show -g $RG_B -n $VM_NAME -d --query "powerState" -o tsv
$wasHibernated = $false

if ($powerState -eq "VM deallocated") {
    Write-Host " VM is hibernated/deallocated" -ForegroundColor Yellow
    $wasHibernated = $true
}
elseif ($powerState -ne "VM running") {
    Write-Host " VM is in state: $powerState" -ForegroundColor Yellow
}

if ($powerState -ne "VM running") {
    Write-Host " Starting VM..." -ForegroundColor Yellow
    az vm start -g $RG_B -n $VM_NAME | Out-Null
    
    # Wait for VM to be fully started
    do {
        Start-Sleep -Seconds 5
        $powerState = az vm show -g $RG_B -n $VM_NAME -d --query "powerState" -o tsv
        Write-Host "  Status: $powerState" -ForegroundColor Cyan
    } while ($powerState -ne "VM running")
    
    # Additional wait if VM was hibernated (needs time to fully resume services)
    if ($wasHibernated) {
        Write-Host " VM was hibernated - waiting $HIBERNATION_RESUME_WAIT seconds for full resume..." -ForegroundColor Yellow
        for ($i = $HIBERNATION_RESUME_WAIT; $i -gt 0; $i--) {
            Write-Progress -Activity "Waiting for hibernation resume" -Status "$i seconds remaining" -PercentComplete (($HIBERNATION_RESUME_WAIT - $i) / $HIBERNATION_RESUME_WAIT * 100)
            Start-Sleep -Seconds 1
        }
        Write-Progress -Activity "Waiting for hibernation resume" -Completed
        Write-Host " Hibernation resume wait completed" -ForegroundColor Green
    }
}
else {
    Write-Host " VM is already running" -ForegroundColor Green
}

# Get VM public IP
Write-Host " Getting VM connection details..." -ForegroundColor Yellow
$publicIP = az vm show -g $RG_B -n $VM_NAME -d --query "publicIps" -o tsv

if (-not $publicIP) {
    Write-Error "No public IP found for VM. Cannot establish RDP connection."
    exit 1
}

Write-Host " Connecting to: $publicIP" -ForegroundColor Cyan

# Create temporary RDP file
Write-Host " Creating RDP connection file..." -ForegroundColor Yellow
$tempRdpFile = Join-Path $env:TEMP "AzureVM-$VM_NAME.rdp"

# Generate RDP file content
$rdpContent = @"
full address:s:$publicIP
prompt for credentials:i:1
administrative session:i:1
"@

Set-Content -Path $tempRdpFile -Value $rdpContent -Force

$proxyProcess = $null
$proxyOwnerToken = $null

# Start proxy point tunnel (VM browser egress via this PC) if enabled.
# Every connection claims a new token: latest connection wins automatically.
if ($config.proxyPoint.enabled) {
    Write-Host " Setting up proxy point (VM browser exits via this PC)..." -ForegroundColor Yellow
    try {
        if ($config.proxyPoint.ownershipMode -ne "latestWins") {
            throw "Unsupported proxyPoint.ownershipMode '$($config.proxyPoint.ownershipMode)'. Expected 'latestWins'."
        }
        . (Join-Path $PSScriptRoot "proxy-point-helper.ps1")
        Ensure-ProxyPointKey -Config $config
        $proxyOwnerToken = [guid]::NewGuid().ToString("N")
        $proxyScript = Join-Path $PSScriptRoot "enable-proxy-point.ps1"
        $proxyProcess = Start-Process "powershell.exe" -ArgumentList @(
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$proxyScript`"",
            "-NoAuth",
            "-OwnerToken", $proxyOwnerToken
        ) -WindowStyle Minimized -PassThru

        Wait-ProxyPointReady `
            -Config $config `
            -PublicIP $publicIP `
            -OwnerToken $proxyOwnerToken `
            -TimeoutSeconds 20

        Write-Host " Proxy point tunnel ready; this PC is the current owner" -ForegroundColor Green
        Write-Host "   A later PC connection will take over automatically" -ForegroundColor Gray
        Write-Host "   Use 'Start App Proxy' on the VM for Rivhit/Chrome/Edge" -ForegroundColor Gray
    }
    catch {
        if ($proxyOwnerToken) {
            try {
                Release-ProxyPointOwnership `
                    -Config $config `
                    -PublicIP $publicIP `
                    -OwnerToken $proxyOwnerToken | Out-Null
            }
            catch {}
        }

        if ($proxyProcess -and -not $proxyProcess.HasExited) {
            if (-not $proxyProcess.WaitForExit(5000)) {
                & taskkill.exe /PID $proxyProcess.Id /T /F 2>$null | Out-Null
            }
        }
        Write-Host " Proxy point setup failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   RDP will continue; VM browser shortcut won't work until fixed" -ForegroundColor Gray
    }
}

# Connect via RDP
Write-Host " Launching RDP connection..." -ForegroundColor Yellow
$rdpProcess = Start-Process "mstsc" -ArgumentList "`"$tempRdpFile`"" -WindowStyle Normal -PassThru

Write-Host " RDP connection launched!" -ForegroundColor Green
Write-Host " Enter your credentials when prompted" -ForegroundColor Yellow
Write-Host " RDP file: $tempRdpFile" -ForegroundColor Gray

if ($proxyProcess -and $proxyOwnerToken -and $config.proxyPoint.releaseOnRdpClose) {
    $proxyMonitorScript = Join-Path $PSScriptRoot "proxy-point-rdp-monitor.ps1"
    Start-Process "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$proxyMonitorScript`"",
        "-RdpProcessId", $rdpProcess.Id,
        "-ProxyProcessId", $proxyProcess.Id,
        "-OwnerToken", $proxyOwnerToken,
        "-PublicIP", $publicIP
    ) -WindowStyle Hidden | Out-Null
    Write-Host " Proxy Point will release automatically when this RDP window closes" -ForegroundColor Gray
}

# Check if external hibernation monitoring is enabled
if ($config.hibernation.external.enabled) {
    # Start hibernation monitoring in separate window immediately after RDP launches
    Write-Host "`n Starting hibernation monitor in separate window..." -ForegroundColor Cyan
    $delayMinutes = [math]::Round($HIBERNATION_DELAY_SECONDS / 60, 1)
    Write-Host "   VM will hibernate $delayMinutes minutes after RDP window closes" -ForegroundColor Yellow

    # Get the directory where this script is located (scripts folder)
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $hibernationMonitorScript = Join-Path $scriptDirectory "hibernation-monitor.ps1"

    # Verify the hibernation monitor script exists
    if (-not (Test-Path $hibernationMonitorScript)) {
        Write-Error "Hibernation monitor script not found at: $hibernationMonitorScript"
        Write-Host " Ensure hibernation-monitor.ps1 is in the same directory as this script" -ForegroundColor Yellow
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
    Write-Host " Hibernation monitor started in $visibilityText window (PID: $($monitorProcess.Id))" -ForegroundColor Green
    Write-Host " This window can now be closed safely - monitoring continues independently" -ForegroundColor Cyan
    Write-Host " Monitor script: hibernation-monitor.ps1" -ForegroundColor Gray
    if ($MONITOR_WINDOW_VISIBLE) {
        Write-Host " Monitor window is visible for debugging - set `$MONITOR_WINDOW_VISIBLE = `$false to hide" -ForegroundColor Yellow
    }
} else {
    Write-Host "`nExternal hibernation monitoring is disabled" -ForegroundColor Yellow
    Write-Host "   Only the internal VM monitor will handle hibernation" -ForegroundColor Cyan
    Write-Host "   To enable external monitoring, set hibernation.external.enabled to true in config.json" -ForegroundColor Gray
}
