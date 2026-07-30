# Releases this PC's Proxy Point ownership when its local RDP process exits.
# The VM-side release is token-checked, so an older monitor cannot tear down a
# newer PC's tunnel after ownership has moved.

param(
    [Parameter(Mandatory)]
    [int]$RdpProcessId,

    [Parameter(Mandatory)]
    [int]$ProxyProcessId,

    [Parameter(Mandatory)]
    [string]$OwnerToken,

    [Parameter(Mandatory)]
    [string]$PublicIP
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "config-loader.ps1")
. (Join-Path $PSScriptRoot "proxy-point-helper.ps1")
$config = Get-VMRdpConfig

try {
    Wait-Process -Id $RdpProcessId -ErrorAction SilentlyContinue

    if ($config.proxyPoint.releaseOnRdpClose) {
        try {
            $result = Release-ProxyPointOwnership `
                -Config $config `
                -PublicIP $PublicIP `
                -OwnerToken $OwnerToken
            if ($result -match "proxy-release:released") {
                Write-Host " Proxy Point released after RDP closed." -ForegroundColor Green
            }
        }
        catch {
            Write-Host " Proxy Point release after RDP close failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
finally {
    Start-Sleep -Seconds 2
    $proxyProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $ProxyProcessId" -ErrorAction SilentlyContinue
    if ($proxyProcess -and $proxyProcess.CommandLine -match [regex]::Escape($OwnerToken)) {
        & taskkill.exe /PID $ProxyProcessId /T /F 2>$null | Out-Null
    }
    Clear-ProxyPointLocalState -OwnerToken $OwnerToken
}
