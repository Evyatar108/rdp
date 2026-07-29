# Enable Proxy Point
# Runs on YOUR PC. Establishes a reverse SSH tunnel to the VM so that the VM
# gets a local SOCKS5 proxy (localhost:1080) whose traffic EXITS through this PC.
# Use the "Browser via Proxy Point" shortcut on the VM to browse through it.
#
# Requires: OpenSSH client (built into Windows 10/11). The SSH key is generated
# and authorized on the VM automatically on first use (via Azure run-command).
#
# -NoAuth: skip Azure CLI auth/key setup (used when launched from connect-vm-rdp.ps1
#          which has already authenticated and ensured the key).

param(
    [switch]$NoAuth
)

$ErrorActionPreference = "Stop"

# Load configuration
. (Join-Path $PSScriptRoot "config-loader.ps1")
$config = Get-VMRdpConfig

$TENANT_B = $config.azure.target.tenantId
$SUB_B = $config.azure.target.subscriptionId
$RG_B = $config.azure.target.resourceGroup
$VM_NAME = $config.azure.target.vmName

$SOCKS_PORT = $config.proxyPoint.socksPort
$SSH_USER = $config.proxyPoint.sshUser
$AUTO_RECONNECT = $config.proxyPoint.autoReconnect
$RECONNECT_DELAY = $config.proxyPoint.reconnectDelaySeconds

. (Join-Path $PSScriptRoot "proxy-point-helper.ps1")
$SSH_KEY = Get-ProxyPointKeyPath -Config $config

Write-Host " Proxy Point (VM browser exits via this PC)" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green

if (-not $NoAuth) {
    # Ensure Azure CLI + auth (same helper as RDP script), then key setup
    . (Join-Path $PSScriptRoot "azure-auth-helper.ps1")
    Ensure-AzureCLIAuthenticated -TenantId $TENANT_B -SubscriptionId $SUB_B
    Ensure-ProxyPointKey -Config $config
}
elseif (-not (Test-Path $SSH_KEY)) {
    Write-Error "SSH key not found at $SSH_KEY (unexpected with -NoAuth). Run enable-proxy-point.ps1 without -NoAuth."
}

# Ensure VM is running, then resolve public IP
$powerState = az vm show -g $RG_B -n $VM_NAME -d --query "powerState" -o tsv
if ($powerState -ne "VM running") {
    Write-Host " VM is '$powerState' - starting it..." -ForegroundColor Yellow
    az vm start -g $RG_B -n $VM_NAME | Out-Null
}
$publicIP = az vm show -g $RG_B -n $VM_NAME -d --query "publicIps" -o tsv
if (-not $publicIP) { Write-Error "No public IP found for VM." }

Write-Host " VM: $publicIP | SOCKS on VM: localhost:$SOCKS_PORT | Exit: this PC" -ForegroundColor Cyan
Write-Host " Press Ctrl+C to stop the proxy point." -ForegroundColor Yellow
Write-Host ""

# Reverse dynamic SOCKS: the VM listens on localhost:$SOCKS_PORT, this PC does
# the SOCKS proxying, so all proxied traffic egresses from this PC's network.
$sshArgs = @(
    "-N"
    "-R", "$SOCKS_PORT"
    "-i", $SSH_KEY
    "-o", "BatchMode=yes"
    "-o", "ExitOnForwardFailure=yes"
    "-o", "ServerAliveInterval=15"
    "-o", "ServerAliveCountMax=3"
    "-o", "StrictHostKeyChecking=accept-new"
    "$SSH_USER@$publicIP"
)

while ($true) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') Establishing tunnel..." -ForegroundColor Cyan
    & ssh @sshArgs
    $code = $LASTEXITCODE
    Write-Host "$(Get-Date -Format 'HH:mm:ss') Tunnel ended (exit $code)." -ForegroundColor Yellow
    if (-not $AUTO_RECONNECT) { break }
    Write-Host " Reconnecting in $RECONNECT_DELAY seconds... (Ctrl+C to stop)" -ForegroundColor Gray
    Start-Sleep -Seconds $RECONNECT_DELAY
    # Re-resolve IP in case the VM was restarted meanwhile
    $newIP = az vm show -g $RG_B -n $VM_NAME -d --query "publicIps" -o tsv
    if ($newIP -and $newIP -ne $publicIP) {
        $publicIP = $newIP
        $sshArgs[-1] = "$SSH_USER@$publicIP"
        Write-Host " VM IP changed - now using $publicIP" -ForegroundColor Yellow
    }
}
