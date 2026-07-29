# Shared Proxy Point helpers
# Used by enable-proxy-point.ps1 (standalone) and connect-vm-rdp.ps1 (auto-start).

function Get-ProxyPointKeyPath {
    param($Config)
    return ($Config.proxyPoint.sshKeyPath -replace '^~', $env:USERPROFILE)
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
