# Proxy Point and App Proxy Operations

This guide describes the current end-user behavior, verification flow, and
recovery procedure for routing selected VM applications through the network of
the PC that opened the RDP connection.

## What starts automatically

Running `.\vm-rdp.ps1` on a connecting PC:

1. Pulls the latest repo changes when auto-update is enabled.
2. Starts/resumes the Azure VM.
3. Creates and authorizes a per-PC SSH key on first use.
4. Claims a tokenized VM-side ownership lease.
5. Stops any older PC's listener and starts this PC's reverse SSH SOCKS5
   tunnel in a minimized PowerShell window.
6. Opens RDP.
7. Releases this PC's lease and tunnel when its local RDP window closes.
8. Starts/stops transparent application proxying according to
   `proxyPoint.appProxyMode`.

The tunnel exposes `127.0.0.1:1080` on the VM, but the tunnel alone does not
route any application through it.

## Multiple connecting PCs

Proxy Point uses `ownershipMode: "latestWins"`:

- The newest PC that successfully runs `vm-rdp.ps1` becomes the owner.
- Claim/release operations are serialized on the VM with an ownership lock.
- A per-connection random token prevents an older RDP-close monitor from
  removing a newer PC's tunnel.
- The older PC's SSH reconnect loop detects the token change and exits.
- Existing RDP sessions are not disconnected; only Proxy Point ownership
  changes.

VM ownership state is stored under `C:\ProgramData\RdpProxyPoint`. Each PC
also keeps its current token under `%LOCALAPPDATA%\RdpProxyPoint` so
`disable-proxy-point.ps1` can release only that PC's lease.

Only one shared VM endpoint (`127.0.0.1:1080`) exists, so simultaneous PCs
cannot both provide egress at once. When the newest owner's RDP window closes,
the tunnel is released. An older still-open RDP session is not automatically
restored; rerun `vm-rdp.ps1` on that PC to reclaim ownership.

## App Proxy mode

`config.json` controls transparent Rivhit/Chrome/Edge proxying independently
from tunnel creation:

```json
{
  "proxyPoint": {
    "enabled": true,
    "appProxyMode": "automatic"
  }
}
```

- `"automatic"` (current default): `ProxiFyreService` starts after the current
  owner's SOCKS listener is confirmed ready. The matching owner release stops
  the service. A stale/older owner cannot stop a newer owner's service/tunnel.
- `"manual"`: the tunnel still starts automatically, but users control
  `ProxiFyreService` through **Start App Proxy** and **Stop App Proxy**.
- `proxyPoint.enabled: false`: no automatic tunnel or App Proxy lifecycle.

The Windows service remains `StartType=Manual` in both modes; automatic mode
means the Proxy Point scripts start it, not Windows boot. Changes apply on the
next Proxy Point launch.

## Manual shortcuts and overrides

- **Browser via Proxy Point** launches a dedicated Chrome/Edge profile with
  explicit SOCKS5 arguments. Normal browser windows are unaffected.
- **Start App Proxy** starts `ProxiFyreService` and routes:
  - every executable under `C:\Rivhit\`
  - all `chrome.exe` processes
  - all `msedge.exe` processes
- **Stop App Proxy** stops transparent routing.

The App Proxy shortcuts remain usable in automatic mode as per-session
overrides. If manually stopped, automatic mode starts it again on the next
successful ownership claim.

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

1. Confirm `ProxiFyreService` is running (automatic mode) or use
   **Start App Proxy** (manual mode).
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
- Windows service `StartType=Manual` policy (lifecycle still follows
  `appProxyMode`)

`deploy-vm-shortcuts.ps1` recreates all three shortcuts in the correct desktop
folder. The current VM redirects the desktop to
`C:\Users\shabi108\OneDrive\Desktop`.

## Troubleshooting

### No tunnel detected

The PC-side SSH tunnel is not running or failed to bind port 1080. Re-run
`.\vm-rdp.ps1` on the connecting PC or manually run
`.\scripts\enable-proxy-point.ps1`.

### Another PC took over

This is expected under latest-wins ownership. The previous tunnel window exits
after detecting that its token no longer owns the VM endpoint. Rerun
`vm-rdp.ps1` on the desired PC to take ownership back.

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

- The SSH tunnel normally lasts for the local RDP window lifetime. It also
  stops when another PC claims ownership, the PC restarts, or
  `disable-proxy-point.ps1` is run.
- Each connecting PC receives its own SSH key, appended to the VM's
  administrators authorized-keys file.
- `ProxiFyreService` is `StartType=Manual`; its session lifecycle is selected
  by `proxyPoint.appProxyMode`.
- Proxy Point affects only explicitly configured applications; RDP itself is
  not routed through the SOCKS tunnel.
