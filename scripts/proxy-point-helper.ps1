# Shared Proxy Point helpers
# Used by enable-proxy-point.ps1 (standalone) and connect-vm-rdp.ps1 (auto-start).

function Get-ProxyPointKeyPath {
    param($Config)
    return ($Config.proxyPoint.sshKeyPath -replace '^~', $env:USERPROFILE)
}

function Get-ProxyPointLocalStatePath {
    $stateDirectory = Join-Path $env:LOCALAPPDATA "RdpProxyPoint"
    return (Join-Path $stateDirectory "owner.json")
}

function Set-ProxyPointLocalState {
    param(
        [string]$OwnerToken,
        [string]$PublicIP
    )

    $statePath = Get-ProxyPointLocalStatePath
    $stateDirectory = Split-Path -Parent $statePath
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    [ordered]@{
        ownerToken = $OwnerToken
        publicIP = $PublicIP
        computerName = $env:COMPUTERNAME
        processId = $PID
        updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json | Set-Content -Path $statePath -Encoding ASCII
}

function Get-ProxyPointLocalState {
    $statePath = Get-ProxyPointLocalStatePath
    if (-not (Test-Path $statePath)) { return $null }
    try {
        return (Get-Content $statePath -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Clear-ProxyPointLocalState {
    param([string]$OwnerToken)

    $statePath = Get-ProxyPointLocalStatePath
    if (-not (Test-Path $statePath)) { return }
    $state = Get-ProxyPointLocalState
    if (-not $OwnerToken -or ($state -and $state.ownerToken -eq $OwnerToken)) {
        Remove-Item $statePath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ProxyPointRemoteScript {
    param(
        $Config,
        [string]$PublicIP,
        [string]$Script,
        [int]$ConnectTimeoutSeconds = 10
    )

    $keyPath = Get-ProxyPointKeyPath -Config $Config
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    $sshArgs = @(
        "-i", $keyPath
        "-o", "BatchMode=yes"
        "-o", "ConnectTimeout=$ConnectTimeoutSeconds"
        "-o", "StrictHostKeyChecking=accept-new"
        "$($Config.proxyPoint.sshUser)@$PublicIP"
        "powershell.exe -NoProfile -NonInteractive -EncodedCommand $encoded"
    )

    $output = & ssh @sshArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Proxy Point remote command failed (ssh exit $LASTEXITCODE): $($output -join ' ')"
    }
    return ($output -join "`n")
}

function Claim-ProxyPointOwnership {
    param(
        $Config,
        [string]$PublicIP,
        [string]$OwnerToken
    )

    $port = [int]$Config.proxyPoint.socksPort
    $token = $OwnerToken.Replace("'", "''")
    $computerName = $env:COMPUTERNAME.Replace("'", "''")
    $userName = $env:USERNAME.Replace("'", "''")
    $appProxyMode = ([string]$Config.proxyPoint.appProxyMode).Replace("'", "''")
    $remoteScript = @"
`$ErrorActionPreference = 'Stop'
`$stateDirectory = 'C:\ProgramData\RdpProxyPoint'
`$statePath = Join-Path `$stateDirectory 'owner.json'
`$lockPath = Join-Path `$stateDirectory 'ownership.lock'
New-Item -ItemType Directory -Path `$stateDirectory -Force | Out-Null
`$lockStream = `$null
for (`$i = 0; `$i -lt 120 -and -not `$lockStream; `$i++) {
    try {
        `$lockStream = [IO.File]::Open(`$lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] {
        Start-Sleep -Milliseconds 250
    }
}
if (-not `$lockStream) { throw 'Timed out waiting for the Proxy Point ownership lock.' }
try {
    `$previousState = `$null
    if (Test-Path `$statePath) {
        try { `$previousState = Get-Content `$statePath -Raw | ConvertFrom-Json } catch {}
    }
    if (`$previousState -and `$previousState.appProxyMode -eq 'automatic') {
        `$previousAppProxy = Get-Service -Name 'ProxiFyreService' -ErrorAction SilentlyContinue
        if (`$previousAppProxy -and `$previousAppProxy.Status -ne 'Stopped') {
            Stop-Service -Name 'ProxiFyreService' -Force
            `$previousAppProxy.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
        }
    }

    [ordered]@{
        ownerToken = '$token'
        computerName = '$computerName'
        userName = '$userName'
        appProxyMode = '$appProxyMode'
        claimedAt = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json | Set-Content -Path `$statePath -Encoding ASCII

    for (`$i = 0; `$i -lt 20; `$i++) {
        `$listenerPids = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique
        if (-not `$listenerPids) { break }
        foreach (`$listenerPid in `$listenerPids) {
            Stop-Process -Id `$listenerPid -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 250
    }
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
        try {
            `$state = Get-Content `$statePath -Raw | ConvertFrom-Json
            if (`$state.ownerToken -eq '$token') {
                Remove-Item `$statePath -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        throw 'Could not stop the previous Proxy Point listener on port $port.'
    }
    Write-Output 'proxy-claimed:$token'
}
finally {
    `$lockStream.Dispose()
}
"@

    $result = Invoke-ProxyPointRemoteScript -Config $Config -PublicIP $PublicIP -Script $remoteScript
    if ($result -notmatch "proxy-claimed:$([regex]::Escape($OwnerToken))") {
        throw "VM did not confirm Proxy Point ownership: $result"
    }
}

function Get-ProxyPointRemoteStatus {
    param(
        $Config,
        [string]$PublicIP,
        [string]$OwnerToken
    )

    $port = [int]$Config.proxyPoint.socksPort
    $token = $OwnerToken.Replace("'", "''")
    $remoteScript = @"
`$stateDirectory = 'C:\ProgramData\RdpProxyPoint'
`$statePath = 'C:\ProgramData\RdpProxyPoint\owner.json'
`$lockPath = Join-Path `$stateDirectory 'ownership.lock'
New-Item -ItemType Directory -Path `$stateDirectory -Force | Out-Null
`$lockStream = `$null
for (`$i = 0; `$i -lt 40 -and -not `$lockStream; `$i++) {
    try {
        `$lockStream = [IO.File]::Open(`$lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] {
        Start-Sleep -Milliseconds 250
    }
}
if (-not `$lockStream) { throw 'Timed out waiting for the Proxy Point ownership lock.' }
try {
    `$ownerMatches = `$false
    if (Test-Path `$statePath) {
        try {
            `$state = Get-Content `$statePath -Raw | ConvertFrom-Json
            `$ownerMatches = (`$state.ownerToken -eq '$token')
        } catch {}
    }
    `$listening = [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
    Write-Output ('proxy-status:{0}:{1}' -f `$ownerMatches.ToString().ToLowerInvariant(), `$listening.ToString().ToLowerInvariant())
}
finally {
    `$lockStream.Dispose()
}
"@

    $result = Invoke-ProxyPointRemoteScript -Config $Config -PublicIP $PublicIP -Script $remoteScript
    if ($result -match 'proxy-status:(true|false):(true|false)') {
        return [pscustomobject]@{
            OwnerMatches = ($Matches[1] -eq "true")
            Listening = ($Matches[2] -eq "true")
        }
    }
    throw "Could not parse Proxy Point status: $result"
}

function Test-ProxyPointOwnership {
    param(
        $Config,
        [string]$PublicIP,
        [string]$OwnerToken
    )

    try {
        return (Get-ProxyPointRemoteStatus -Config $Config -PublicIP $PublicIP -OwnerToken $OwnerToken).OwnerMatches
    }
    catch {
        return $false
    }
}

function Wait-ProxyPointReady {
    param(
        $Config,
        [string]$PublicIP,
        [string]$OwnerToken,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $consecutiveReadyChecks = 0
    $observedOwnership = $false
    do {
        try {
            $status = Get-ProxyPointRemoteStatus -Config $Config -PublicIP $PublicIP -OwnerToken $OwnerToken
            if ($status.OwnerMatches) {
                $observedOwnership = $true
            }
            elseif ($observedOwnership) {
                throw "Proxy Point ownership was taken by another PC."
            }

            if ($status.OwnerMatches -and $status.Listening) {
                $consecutiveReadyChecks++
                if ($consecutiveReadyChecks -ge 3) { return }
            }
            else {
                $consecutiveReadyChecks = 0
            }
        }
        catch {
            if ($_.Exception.Message -match "taken by another PC") { throw }
            $consecutiveReadyChecks = 0
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    throw "Proxy Point did not become ready on VM localhost:$($Config.proxyPoint.socksPort) within $TimeoutSeconds seconds."
}

function Set-ProxyPointAppProxyState {
    param(
        $Config,
        [string]$PublicIP,
        [string]$OwnerToken,
        [bool]$Enabled
    )

    $desiredState = if ($Enabled) { "running" } else { "stopped" }
    $enabledLiteral = if ($Enabled) { '$true' } else { '$false' }
    $port = [int]$Config.proxyPoint.socksPort
    $token = $OwnerToken.Replace("'", "''")
    $remoteScript = @"
`$ErrorActionPreference = 'Stop'
`$stateDirectory = 'C:\ProgramData\RdpProxyPoint'
`$statePath = Join-Path `$stateDirectory 'owner.json'
`$lockPath = Join-Path `$stateDirectory 'ownership.lock'
New-Item -ItemType Directory -Path `$stateDirectory -Force | Out-Null
`$lockStream = `$null
for (`$i = 0; `$i -lt 120 -and -not `$lockStream; `$i++) {
    try {
        `$lockStream = [IO.File]::Open(`$lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] {
        Start-Sleep -Milliseconds 250
    }
}
if (-not `$lockStream) { throw 'Timed out waiting for the Proxy Point ownership lock.' }
try {
    if (-not (Test-Path `$statePath)) {
        Write-Output 'proxy-app:no-owner'
        exit 0
    }
    try {
        `$state = Get-Content `$statePath -Raw | ConvertFrom-Json
    } catch {
        Write-Output 'proxy-app:invalid-state'
        exit 0
    }
    if (`$state.ownerToken -ne '$token') {
        Write-Output 'proxy-app:not-owner'
        exit 0
    }
    if ($enabledLiteral -and `$state.appProxyMode -ne 'automatic') {
        Write-Output 'proxy-app:manual-mode'
        exit 0
    }
    if ($enabledLiteral -and -not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) {
        Write-Output 'proxy-app:no-listener'
        exit 0
    }

    `$service = Get-Service -Name 'ProxiFyreService' -ErrorAction SilentlyContinue
    if (-not `$service) {
        Write-Output 'proxy-app:missing'
        exit 0
    }
    if ($enabledLiteral) {
        if (`$service.Status -ne 'Running') {
            Start-Service -Name 'ProxiFyreService'
            `$service.WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
        }
        Write-Output 'proxy-app:running'
    }
    else {
        if (`$service.Status -ne 'Stopped') {
            Stop-Service -Name 'ProxiFyreService' -Force
            `$service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
        }
        Write-Output 'proxy-app:stopped'
    }
}
finally {
    `$lockStream.Dispose()
}
"@

    $result = Invoke-ProxyPointRemoteScript -Config $Config -PublicIP $PublicIP -Script $remoteScript
    if ($result -match 'proxy-app:missing') {
        throw "ProxiFyreService is not installed on the VM. Run scripts\deploy-proxifyre.ps1 on the VM."
    }
    if ($result -match 'proxy-app:(not-owner|no-owner)') {
        throw "This PC no longer owns Proxy Point."
    }
    if ($result -match 'proxy-app:no-listener') {
        throw "The owning Proxy Point listener is not ready."
    }
    if ($result -match 'proxy-app:manual-mode') {
        throw "App Proxy is configured for manual mode."
    }
    if ($result -notmatch "proxy-app:$desiredState") {
        throw "VM did not confirm App Proxy state '$desiredState': $result"
    }
    return $desiredState
}

function Release-ProxyPointOwnership {
    param(
        $Config,
        [string]$PublicIP,
        [string]$OwnerToken
    )

    $port = [int]$Config.proxyPoint.socksPort
    $token = $OwnerToken.Replace("'", "''")
    $remoteScript = @"
`$stateDirectory = 'C:\ProgramData\RdpProxyPoint'
`$statePath = 'C:\ProgramData\RdpProxyPoint\owner.json'
`$lockPath = Join-Path `$stateDirectory 'ownership.lock'
New-Item -ItemType Directory -Path `$stateDirectory -Force | Out-Null
`$lockStream = `$null
for (`$i = 0; `$i -lt 120 -and -not `$lockStream; `$i++) {
    try {
        `$lockStream = [IO.File]::Open(`$lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] {
        Start-Sleep -Milliseconds 250
    }
}
if (-not `$lockStream) { throw 'Timed out waiting for the Proxy Point ownership lock.' }
try {
    if (-not (Test-Path `$statePath)) {
        Write-Output 'proxy-release:no-owner'
        exit 0
    }
    try {
        `$state = Get-Content `$statePath -Raw | ConvertFrom-Json
    } catch {
        Write-Output 'proxy-release:invalid-state'
        exit 0
    }
    if (`$state.ownerToken -ne '$token') {
        Write-Output 'proxy-release:not-owner'
        exit 0
    }
    `$listenerPids = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    foreach (`$listenerPid in `$listenerPids) {
        Stop-Process -Id `$listenerPid -Force -ErrorAction SilentlyContinue
    }
    if (`$state.appProxyMode -eq 'automatic') {
        `$appProxyService = Get-Service -Name 'ProxiFyreService' -ErrorAction SilentlyContinue
        if (`$appProxyService -and `$appProxyService.Status -ne 'Stopped') {
            Stop-Service -Name 'ProxiFyreService' -Force
            `$appProxyService.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
        }
    }
    Remove-Item `$statePath -Force -ErrorAction SilentlyContinue
    Write-Output 'proxy-release:released'
}
finally {
    `$lockStream.Dispose()
}
"@

    return (Invoke-ProxyPointRemoteScript -Config $Config -PublicIP $PublicIP -Script $remoteScript)
}

# Ensure this PC has an SSH keypair and its public key is authorized on the VM.
# Requires Azure CLI to already be authenticated (uses az vm run-command).
function Ensure-ProxyPointKey {
    param($Config)

    $keyPath = Get-ProxyPointKeyPath -Config $Config
    $RG = $Config.azure.target.resourceGroup
    $VM = $Config.azure.target.vmName

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        throw "OpenSSH client (ssh) not found. Install the 'OpenSSH Client' Windows optional feature."
    }

    if (-not (Test-Path $keyPath)) {
        if (-not $Config.proxyPoint.autoSetupKey) {
            throw "SSH key not found at $keyPath and autoSetupKey is disabled. See README 'Proxy Point'."
        }
        Write-Host " No proxy key on this PC - generating one..." -ForegroundColor Yellow
        $sshDir = Split-Path -Parent $keyPath
        if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
        # cmd /c guarantees a truly empty passphrase (PowerShell quoting of -N "" is unreliable)
        cmd /c "ssh-keygen -t ed25519 -f `"$keyPath`" -N `"`" -C proxy-point-$env:COMPUTERNAME -q"
        if (-not (Test-Path $keyPath)) { throw "ssh-keygen failed to create $keyPath" }
    }

    # Quick probe: can we already authenticate? (5s, batch mode, no prompts)
    $publicIP = az vm show -g $RG -n $VM -d --query "publicIps" -o tsv
    ssh -i $keyPath -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new `
        "$($Config.proxyPoint.sshUser)@$publicIP" "exit" 2>$null
    if ($LASTEXITCODE -eq 0) { return }

    # Not authorized yet - deploy the public key through Azure run-command.
    Write-Host " Authorizing this PC's key on the VM (one-time, via Azure)..." -ForegroundColor Yellow
    $pubKey = (Get-Content "$keyPath.pub" -Raw).Trim()
    $deployScript = @"
`$authFile = 'C:\ProgramData\ssh\administrators_authorized_keys'
`$key = '$pubKey'
`$existing = if (Test-Path `$authFile) { Get-Content `$authFile } else { @() }
if (`$existing -notcontains `$key) {
    [System.IO.File]::WriteAllLines(`$authFile, (@(`$existing) + `$key | Where-Object { `$_ }), [System.Text.ASCIIEncoding]::new())
}
icacls `$authFile /inheritance:r /grant 'NT AUTHORITY\SYSTEM:(F)' /grant 'BUILTIN\Administrators:(F)' | Out-Null
Write-Output 'key-authorized'
"@
    $tmp = Join-Path $env:TEMP "proxy-point-deploy-key.ps1"
    Set-Content -Path $tmp -Value $deployScript -Encoding ASCII
    try {
        $result = az vm run-command invoke -g $RG -n $VM --command-id RunPowerShellScript `
            --scripts "@$tmp" --query "value[0].message" -o tsv
        if ($result -notmatch 'key-authorized') { throw "Key deployment failed: $result" }
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }

    # Verify
    ssh -i $keyPath -o BatchMode=yes -o ConnectTimeout=10 "$($Config.proxyPoint.sshUser)@$publicIP" "exit" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Key deployed but SSH auth still failing. Check VM sshd." }
    Write-Host " Key authorized on VM." -ForegroundColor Green
}

# True if a proxy-point ssh tunnel for the configured port is already running on this PC.
function Test-ProxyPointRunning {
    param($Config)
    $port = $Config.proxyPoint.socksPort
    $found = Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" |
        Where-Object { $_.CommandLine -match "-R\s+$port\b" }
    return [bool]$found
}
