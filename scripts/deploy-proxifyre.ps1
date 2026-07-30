# Deploy ProxiFyre (per-app SOCKS5 proxifier) - runs ON THE VM.
# Installs the pieces needed to transparently route a SPECIFIC app's traffic
# through the Proxy Point reverse SOCKS tunnel (localhost:1080), without that
# app needing any native proxy support:
#   1. VC++ 2022 x64 redistributable (ProxiFyre dependency)
#   2. Windows Packet Filter / NDISAPI driver (wiresock/ndisapi) - the packet
#      interception driver ProxiFyre is built on
#   3. ProxiFyre itself (wiresock/proxifyre), installed as a Windows service
#      named "ProxiFyreService"
#   4. Windows Firewall allow rules for ProxiFyre.exe (both directions) -
#      REQUIRED: without these, the driver still intercepts matched processes'
#      traffic but ProxiFyre's own relay connection to the SOCKS endpoint
#      silently hangs/times out (confirmed via live testing).
#
# The service is installed with StartType=Manual and left STOPPED - it never
# starts on its own (not on boot, not tied to Proxy Point auto-start). Use
# vm-start-rivhit-proxy.ps1 / vm-stop-rivhit-proxy.ps1 (or their desktop
# shortcuts) to toggle it on/off deliberately.
#
# NOTE on matching: ProxiFyre matches per-process by exe name/path - it does
# NOT follow parent/child relationships. Multiple instances of the SAME exe
# name (e.g. two rivhit125.exe windows) are already covered automatically.
# A DIFFERENT child executable (Rivhit's folder has several: rivhit220.exe,
# icredit.exe, BatchEMV.exe, dbeng12.exe, etc.) is only covered if matched too.
# Rather than enumerating every helper exe by name, $TargetExeNames defaults
# to a PATH-based pattern ("C:\Rivhit\") - any appNames entry containing a
# backslash is matched as a substring of the process's full path, so this
# covers every executable in that install folder, present or future,
# regardless of which one Rivhit spawns as a child process.
#
# To proxy additional/different apps later, edit C:\ProxiFyre\app-config.json
# (add more entries to "appNames", or add another object to the "proxies"
# array for a different target/port) and restart the service - see
# https://github.com/wiresock/proxifyre for the full config reference.

param(
    [string]$InstallDir = "C:\ProxiFyre",
    [string[]]$TargetExeNames = @("C:\Rivhit\"),
    [int]$SocksPort = 1080,
    [string]$NdisapiVersion = "v3.6.2",
    [string]$NdisapiMsiName = "Windows.Packet.Filter.3.6.2.1.x64.msi",
    [string]$ProxiFyreVersion = "v2.4.0",
    [string]$ProxiFyreZipName = "ProxiFyre-v2.4.0-x64-signed.zip"
)

$ErrorActionPreference = "Stop"

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "This script requires Administrator privileges (driver + service install)." -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator', then re-run." -ForegroundColor Yellow
    exit 1
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

function Invoke-Download($url, $out) {
    if (Test-Path $out) { Write-Host " Already downloaded: $out" -ForegroundColor Gray; return }
    Write-Host " Downloading $url" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
}

# 1. VC++ 2022 x64 redistributable (silent, idempotent)
$vcRedistPath = Join-Path $InstallDir "vc_redist.x64.exe"
Invoke-Download "https://aka.ms/vs/17/release/vc_redist.x64.exe" $vcRedistPath
Write-Host " Installing VC++ 2022 x64 redistributable..." -ForegroundColor Yellow
$p = Start-Process -FilePath $vcRedistPath -ArgumentList "/quiet", "/norestart" -Wait -PassThru
Write-Host " vc_redist exit code: $($p.ExitCode)" -ForegroundColor Gray  # 0=ok, 1638/3010=already installed/reboot pending

# 2. Windows Packet Filter (NDISAPI) driver (silent MSI, idempotent)
$ndisMsiPath = Join-Path $InstallDir "WindowsPacketFilter.x64.msi"
Invoke-Download "https://github.com/wiresock/ndisapi/releases/download/$NdisapiVersion/$NdisapiMsiName" $ndisMsiPath
Write-Host " Installing Windows Packet Filter driver..." -ForegroundColor Yellow
$p2 = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$ndisMsiPath`"", "/qn", "/norestart" -Wait -PassThru
Write-Host " WinpkFilter msiexec exit code: $($p2.ExitCode)" -ForegroundColor Gray

# 3. ProxiFyre binaries
$zipPath = Join-Path $InstallDir "ProxiFyre-x64.zip"
Invoke-Download "https://github.com/wiresock/proxifyre/releases/download/$ProxiFyreVersion/$ProxiFyreZipName" $zipPath
$exePath = Join-Path $InstallDir "ProxiFyre.exe"
if (-not (Test-Path $exePath)) {
    Write-Host " Extracting ProxiFyre..." -ForegroundColor Yellow
    Expand-Archive -Path $zipPath -DestinationPath $InstallDir -Force
}
$nested = Get-ChildItem -Path $InstallDir -Recurse -Filter "ProxiFyre.exe" | Select-Object -First 1
if ($nested -and $nested.FullName -ne $exePath) {
    Copy-Item $nested.FullName $exePath -Force
    $dllNested = Get-ChildItem -Path $nested.DirectoryName -Filter "socksify.dll" -ErrorAction SilentlyContinue
    if ($dllNested) { Copy-Item $dllNested.FullName (Join-Path $InstallDir "socksify.dll") -Force }
}
if (-not (Test-Path $exePath)) { throw "ProxiFyre.exe not found after extraction." }

# 4. app-config.json - only the specified exe(s) are proxied; everything else is untouched
$config = @{
    logLevel  = "Error"
    bypassLan = $true
    proxies   = @(
        @{
            appNames                 = $TargetExeNames
            socks5ProxyEndpoint      = "127.0.0.1:$SocksPort"
            supportedProtocols       = @("TCP", "UDP")
            supportedAddressFamilies = @("IPv4")
        }
    )
} | ConvertTo-Json -Depth 5
Set-Content -Path (Join-Path $InstallDir "app-config.json") -Value $config -Force
Write-Host " app-config.json written (targeting: $($TargetExeNames -join ', '))" -ForegroundColor Green

# 5. Install as a Windows service, but force it to Manual startup and leave it stopped.
# NOTE: the .NET service registers itself under the name "ProxiFyreService"
# (NOT "ProxiFyre" - the exe name), with StartType defaulting to Automatic.
Push-Location $InstallDir
$svc = Get-Service -Name "ProxiFyreService" -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host " Installing ProxiFyre service..." -ForegroundColor Yellow
    & .\ProxiFyre.exe install | Write-Host
    Start-Sleep -Seconds 2
    $svc = Get-Service -Name "ProxiFyreService" -ErrorAction SilentlyContinue
}
else {
    Write-Host " ProxiFyreService already installed." -ForegroundColor Gray
}
if (-not $svc) { throw "ProxiFyreService not found after install - check ProxiFyre.exe output above." }

# 5b. CRITICAL: Windows Firewall silently blocks ProxiFyre's own outbound relay
# connections to the SOCKS endpoint without this rule - the driver still
# intercepts/redirects matched processes' traffic, but ProxiFyre's attempt to
# forward it then hangs/times out with no error surfaced anywhere (confirmed
# via live testing: adding this rule was the difference between a proxied
# request working end-to-end vs. timing out). The ProxiFyre README calls this
# out as a troubleshooting step, but it's applied here unconditionally so a
# fresh deploy works out of the box.
Write-Host " Adding firewall rules for ProxiFyre.exe (required - see comment above)..." -ForegroundColor Yellow
$exeForRule = Join-Path $InstallDir "ProxiFyre.exe"
if (-not (Get-NetFirewallRule -DisplayName "ProxiFyre Inbound" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "ProxiFyre Inbound" -Direction Inbound -Program $exeForRule -Action Allow -Profile Any | Out-Null
}
if (-not (Get-NetFirewallRule -DisplayName "ProxiFyre Outbound" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "ProxiFyre Outbound" -Direction Outbound -Program $exeForRule -Action Allow -Profile Any | Out-Null
}

sc.exe config ProxiFyreService start= demand | Out-Null
if ($svc.Status -eq "Running") { Stop-Service -Name "ProxiFyreService" -Force }
Pop-Location

$final = Get-Service -Name "ProxiFyreService"
Write-Host ""
Write-Host " ProxiFyre deployed." -ForegroundColor Green
Write-Host "   Service: ProxiFyreService (Status: $($final.Status), StartType: $($final.StartType))" -ForegroundColor Gray
Write-Host "   Config:  $InstallDir\app-config.json" -ForegroundColor Gray
Write-Host "   Toggle with: scripts\vm-start-rivhit-proxy.ps1 / scripts\vm-stop-rivhit-proxy.ps1" -ForegroundColor Gray
Write-Host "   (or the 'Start/Stop Rivhit via Proxy' desktop shortcuts)" -ForegroundColor Gray
