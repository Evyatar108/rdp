# Proxy Point and App Proxy Operations

This guide describes the current end-user behavior, verification flow, and
recovery procedure for routing selected VM applications through the network of
the PC that opened the RDP connection.

## What starts automatically

Running `.\vm-rdp.ps1` on a connecting PC:

1. Pulls the latest repo changes when auto-update is enabled.
2. Starts/resumes the Azure VM.
3. Creates and authorizes a per-PC SSH key on first use.
4. Starts a reverse SSH SOCKS5 tunnel in a minimized PowerShell window.
5. Opens RDP.

The tunnel exposes `127.0.0.1:1080` on the VM, but the tunnel alone does not
route any application through it.

## What remains manual

Application-level proxying is intentionally opt-in.

- **Browser via Proxy Point** launches a dedicated Chrome/Edge profile with
  explicit SOCKS5 arguments. Normal browser windows are unaffected.
- **Start App Proxy** starts `ProxiFyreService` and routes:
  - every executable under `C:\Rivhit\`
  - all `chrome.exe` processes
  - all `msedge.exe` processes
- **Stop App Proxy** stops transparent routing.

Chrome and Edge are not force-closed when the proxy is toggled because doing
so could lose tabs or unsaved form data. Open a new tab/window or restart the
browser to guarantee new connections use the new route.

## Verify the tunnel

On the VM:

```powershell
curl.exe -s --max-time 15 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

The result should be the connecting PC's public IP, not the Azure VM's IP.

## Verify transparent App Proxy routing

1. Use **Start App Proxy** on the VM.
2. Open a new Chrome or Edge window.
3. Visit `https://api.ipify.org?format=json`.
4. Confirm the shown IP is the connecting PC's public IP.

For a CLI-only diagnostic, temporarily add `curl.exe` to `appNames` in
`C:\ProxiFyre\app-config.json`, restart `ProxiFyreService`, and run plain
`curl.exe https://api.ipify.org` without SOCKS arguments. Remove the temporary
entry afterward.

## Rebuild or repair VM-side setup

From an elevated PowerShell session on the VM repo clone:

```powershell
Set-Location C:\repos\rdp
.\scripts\deploy-proxifyre.ps1
.\scripts\deploy-vm-shortcuts.ps1
```

`deploy-proxifyre.ps1` installs or repairs:

- Visual C++ 2022 x64 runtime
- Windows Packet Filter / NDISAPI driver
- ProxiFyre binaries and `ProxiFyreService`
- `C:\ProxiFyre\app-config.json`
- required inbound and outbound firewall rules for `ProxiFyre.exe`
- manual/stopped service startup policy

`deploy-vm-shortcuts.ps1` recreates all three shortcuts in the correct desktop
folder. The current VM redirects the desktop to
`C:\Users\shabi108\OneDrive\Desktop`.

## Troubleshooting

### No tunnel detected

The PC-side SSH tunnel is not running or failed to bind port 1080. Re-run
`.\vm-rdp.ps1` on the connecting PC or manually run
`.\scripts\enable-proxy-point.ps1`.

### App hangs or times out after Start App Proxy

Check the service, driver, and firewall rules:

```powershell
Get-Service ProxiFyreService
Get-Service ndisrd
Get-NetFirewallRule -DisplayName "ProxiFyre*" |
    Select-Object DisplayName, Direction, Action, Enabled
```

The known critical failure mode is missing firewall rules for
`C:\ProxiFyre\ProxiFyre.exe`: interception succeeds, but forwarding silently
times out.

### Shortcut is missing

Run:

```powershell
.\scripts\deploy-vm-shortcuts.ps1
```

Do not manually place shortcuts under `C:\Users\shabi108\Desktop` on the
current VM; that folder is not the active OneDrive-redirected desktop.

### Edge fails only under Azure Run Command

`az vm run-command` executes as SYSTEM in non-interactive Session 0. Edge can
fail there because its SYSTEM profile/Crashpad directories are unavailable.
This does not indicate an interactive RDP-session or ProxiFyre failure.

## Security and lifecycle notes

- The SSH tunnel persists until its minimized PC-side PowerShell process is
  stopped, the PC restarts, or `disable-proxy-point.ps1` is run.
- Each connecting PC receives its own SSH key, appended to the VM's
  administrators authorized-keys file.
- `ProxiFyreService` is intentionally manual and stopped by default.
- Proxy Point affects only explicitly configured applications; RDP itself is
  not routed through the SOCKS tunnel.
