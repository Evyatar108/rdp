# Deploy VM desktop shortcuts (runs ON THE VM).
# Recreates all Proxy Point / App Proxy shortcuts from repo scripts so the
# desktop setup is reproducible after rebuilding the VM or user profile.

param(
    [string]$UserName = "shabi108"
)

$ErrorActionPreference = "Stop"

$userProfile = Join-Path "C:\Users" $UserName
$oneDriveDesktop = Join-Path $userProfile "OneDrive\Desktop"
$plainDesktop = Join-Path $userProfile "Desktop"

if (Test-Path $oneDriveDesktop) {
    $desktop = $oneDriveDesktop
}
elseif (Test-Path $plainDesktop) {
    $desktop = $plainDesktop
    Write-Host " OneDrive Desktop not found; using $plainDesktop" -ForegroundColor Yellow
}
else {
    throw "No desktop folder found for user '$UserName'. Checked '$oneDriveDesktop' and '$plainDesktop'."
}

function New-PowerShellShortcut {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [string]$Description,

        [switch]$RunAsAdministrator
    )

    if (-not (Test-Path $ScriptPath)) {
        throw "Shortcut target script not found: $ScriptPath"
    }

    $shortcutPath = Join-Path $desktop "$Name.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoLogo -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $shortcut.WorkingDirectory = Split-Path $ScriptPath -Parent
    $shortcut.Description = $Description
    $shortcut.WindowStyle = 1
    $shortcut.Save()

    if ($RunAsAdministrator) {
        # Set the .lnk "Run as administrator" flag.
        $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)
    }

    Write-Host " Created: $shortcutPath" -ForegroundColor Green
}

# Remove names superseded by the unified App Proxy shortcuts.
@(
    "Start Rivhit via Proxy.lnk",
    "Stop Rivhit Proxy.lnk"
) | ForEach-Object {
    Remove-Item (Join-Path $desktop $_) -Force -ErrorAction SilentlyContinue
}

New-PowerShellShortcut `
    -Name "Browser via Proxy Point" `
    -ScriptPath (Join-Path $PSScriptRoot "vm-browser-via-proxy.ps1") `
    -Description "Launches a dedicated browser profile through the PC-hosted Proxy Point"

New-PowerShellShortcut `
    -Name "Start App Proxy" `
    -ScriptPath (Join-Path $PSScriptRoot "vm-start-app-proxy.ps1") `
    -Description "Routes Rivhit, Chrome, and Edge through the PC-hosted Proxy Point" `
    -RunAsAdministrator

New-PowerShellShortcut `
    -Name "Stop App Proxy" `
    -ScriptPath (Join-Path $PSScriptRoot "vm-stop-app-proxy.ps1") `
    -Description "Stops transparent proxying for Rivhit, Chrome, and Edge" `
    -RunAsAdministrator

Write-Host ""
Write-Host " VM proxy shortcuts deployed to: $desktop" -ForegroundColor Cyan
