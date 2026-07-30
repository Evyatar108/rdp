# VM RDP Auto-Hibernation System

A complete Azure VM hibernation solution that automatically hibernates your VM when you close the RDP connection, saving up to 80% on compute costs.

## 🚀 Quick Start

**Main script to run:**
```powershell
.\vm-rdp.ps1
```

This launcher script will:
1. **Auto-update** - Pull latest script updates from git repository
2. **Launch RDP** - Start the VM and open RDP connection
3. **Monitor automatically** - Hibernate VM when you close RDP

## 📁 Clean Project Structure

```
📂 vm-hibernation/
├── 📄 vm-rdp.ps1          ← Main script (run this!)
├── 📄 config.json         ← All configuration settings
├── 📄 README.md           ← This guide
├── 📄 CLAUDE.md           ← Gotchas/architecture notes for agents & contributors
├── 📂 scripts/            ← Internal scripts (auto-updated)
│   ├── 📄 config-loader.ps1
│   ├── 📄 azure-auth-helper.ps1
│   ├── 📄 update-scripts.ps1
│   ├── 📄 connect-vm-rdp.ps1        ← RDP connect + auto-starts Proxy Point tunnel
│   ├── 📄 hibernation-monitor.ps1
│   ├── 📄 stop-vm.ps1
│   ├── 📄 deploy-internal-monitor.ps1
│   ├── 📄 vm-internal-hibernation-monitor.ps1
│   ├── 📄 proxy-point-helper.ps1    ← SSH key mgmt + tunnel-running detection
│   ├── 📄 enable-proxy-point.ps1    ← PC-side: starts the reverse SSH SOCKS tunnel
│   ├── 📄 disable-proxy-point.ps1   ← PC-side: stops the tunnel
│   ├── 📄 proxy-point-rdp-monitor.ps1 ← PC-side: releases ownership when RDP closes
│   ├── 📄 vm-browser-via-proxy.ps1  ← VM-side: dedicated proxied browser profile
│   ├── 📄 deploy-proxifyre.ps1      ← VM-side: one-time ProxiFyre install (Rivhit/Chrome/Edge)
│   ├── 📄 deploy-vm-shortcuts.ps1   ← VM-side: recreates all proxy desktop shortcuts
│   ├── 📄 vm-start-app-proxy.ps1    ← VM-side: toggle ProxiFyre ON
│   └── 📄 vm-stop-app-proxy.ps1     ← VM-side: toggle ProxiFyre OFF
└── 📂 internal/           ← Setup and docs
    ├── 📄 enable-hibernation.ps1
    └── 📄 *.md documentation
```
VM-side desktop also has "Browser via Proxy Point", "Start App Proxy", and
"Stop App Proxy" shortcuts (in the OneDrive-redirected Desktop folder — see
`CLAUDE.md`).

### **What You See:**
- **[`vm-rdp.ps1`](vm-rdp.ps1)** - **Only script you need to run!**
- **[`config.json`](config.json)** - **All configuration in one place**
- **[`README.md`](README.md)** - This usage guide
- **[`CLAUDE.md`](CLAUDE.md)** - Architecture notes and gotchas for anyone (human or AI agent) changing this repo

### **Auto-Managed Scripts:**
- **[`scripts/config-loader.ps1`](scripts/config-loader.ps1)** - Configuration loader
- **[`scripts/update-scripts.ps1`](scripts/update-scripts.ps1)** - Handles git pull updates
- **[`scripts/connect-vm-rdp.ps1`](scripts/connect-vm-rdp.ps1)** - RDP connection logic
- **[`scripts/hibernation-monitor.ps1`](scripts/hibernation-monitor.ps1)** - Monitor process
- **[`scripts/proxy-point-helper.ps1`](scripts/proxy-point-helper.ps1)**, **[`scripts/enable-proxy-point.ps1`](scripts/enable-proxy-point.ps1)**, **[`scripts/deploy-proxifyre.ps1`](scripts/deploy-proxifyre.ps1)**, **[`scripts/vm-start-app-proxy.ps1`](scripts/vm-start-app-proxy.ps1)** / **[`scripts/vm-stop-app-proxy.ps1`](scripts/vm-stop-app-proxy.ps1)** - see the [Proxy Point](#-proxy-point-vm-browser-exits-via-your-pc) section below

### **Setup & Documentation:**
- **[`internal/README.md`](internal/README.md)** - Index separating current runbooks from historical migration artifacts
- **[`internal/enable-hibernation.ps1`](internal/enable-hibernation.ps1)** - Initial hibernation setup
- **[`internal/*.md`](internal/)** - Detailed guides and documentation

## ⚙️ Configuration

All settings are managed through a single JSON configuration file: **[`config.json`](config.json)**

### **Main Configuration Categories:**

#### **Azure Settings:**
```json
{
  "azure": {
    "target": {
      "tenantId": "your-tenant-id",
      "subscriptionId": "your-subscription-id",
      "resourceGroup": "your-resource-group",
      "vmName": "your-vm-name"
    }
  }
}
```

#### **Hibernation Settings:**
```json
{
  "hibernation": {
    "timing": {
      "delayAfterRdpCloseSeconds": 120,
      "progressUpdateIntervalSeconds": 1,
      "hibernationResumeWaitSeconds": 30
    },
    "showMonitorWindow": true,
    "internal": {
      "enabled": true,
      "inactivityTimeoutMinutes": 10,
      "checkIntervalSeconds": 60
    }
  }
}
```

#### **Auto-Update Settings:**
```json
{
  "autoUpdate": {
    "enabled": true,
    "git": {
      "autoInstall": true,
      "installPaths": [
        "C:\\Program Files\\Git\\cmd",
        "C:\\Program Files (x86)\\Git\\cmd"
      ]
    }
  }
}
```

#### **Other Settings:**
```json
{
  "logging": {
    "verboseOutput": true,
    "showDetailedErrors": true
  }
}
```

## 🎯 Daily Usage

### **Simple Workflow:**
1. **Run:** `.\vm-rdp.ps1`
2. **Scripts auto-update** from git repository
3. **VM starts** (if hibernated/stopped)
4. **RDP opens** automatically
5. **Work normally** in the VM
6. **Close RDP** when done
7. **VM hibernates** automatically after delay
8. **Save money!** VM only charges for actual usage

### **Debug Mode:**
- Set `hibernation.showMonitorWindow` to `true` in `config.json`
- Window shows detailed progress and stays open for debugging
- See exactly when RDP closes and countdown starts

### **Production Mode:**
- Set `hibernation.showMonitorWindow` to `false` in `config.json`
- Monitor runs hidden in background
- Automatic hibernation with no visible windows

## 🌐 Proxy Point (VM browser exits via your PC)

Route the VM's browser traffic through the PC you're connecting from, so websites
see your PC's IP/location instead of the Azure datacenter network.

**How it works:** your PC opens a reverse SSH tunnel to the VM
(`ssh -R 1080 ...`). The VM gets a local SOCKS5 proxy on `localhost:1080` whose
traffic egresses from your PC. A dedicated browser shortcut on the VM uses that
proxy (with proxy-side DNS); everything else on the VM (including RDP) is unaffected.

### Usage
**Automatic (default):** just run `.\vm-rdp.ps1` as usual. When
`proxyPoint.enabled` is `true` in `config.json`, the connect script:
1. Generates an SSH key on this PC on first use (`proxyPoint.autoSetupKey`)
2. Authorizes the key on the VM automatically (one-time, via Azure run-command —
   works for any PC whose user can run the start script)
3. Claims Proxy Point ownership for this PC (**latest connection wins**)
4. Replaces any older PC's tunnel and starts this PC's tunnel minimized
5. Releases this PC's ownership automatically when its RDP window closes
6. Starts/stops transparent Rivhit/Chrome/Edge proxying according to
   `proxyPoint.appProxyMode`

If another PC runs `vm-rdp.ps1` while this session is open, that newer PC takes
over Proxy Point automatically. The older RDP session remains connected, but
its proxy tunnel exits and it cannot tear down the newer tunnel later. When the
newer RDP session closes, Proxy Point becomes unavailable; an older still-open
session is not automatically restored and must rerun `vm-rdp.ps1` to reclaim it.

Then, **on the VM:** double-click the **"Browser via Proxy Point"** desktop
shortcut (or run `.\scripts\vm-browser-via-proxy.ps1`). It opens a browser tab
showing your egress IP — it should be your PC's IP. Regular browser windows on
the VM are NOT proxied.

**Manual:** run `.\scripts\enable-proxy-point.ps1` yourself (keep the window
open; it auto-reconnects if the tunnel drops).

**To stop:** close the minimized tunnel window (or Ctrl+C), or run
`.\scripts\disable-proxy-point.ps1`. Set `proxyPoint.enabled` to `false` to
stop auto-starting it with RDP.

### Configuration (`config.json`)
```json
{
  "proxyPoint": {
    "enabled": true,
    "autoSetupKey": true,
    "socksPort": 1080,
    "sshUser": "shabi108",
    "sshKeyPath": "~/.ssh/vm-proxy_ed25519",
    "autoReconnect": true,
    "reconnectDelaySeconds": 5,
    "ownershipMode": "latestWins",
    "releaseOnRdpClose": true,
    "appProxyMode": "automatic"
  }
}
```

`appProxyMode` accepts:

- `"automatic"` (current default): start `ProxiFyreService` when the owning
  tunnel becomes ready and stop it when that owner releases the tunnel.
- `"manual"`: leave `ProxiFyreService` under the **Start App Proxy** /
  **Stop App Proxy** shortcuts' control.

Set `proxyPoint.enabled` to `false` to disable automatic tunnel setup entirely.
Configuration changes apply on the next `vm-rdp.ps1`/Proxy Point launch.

### VM-side setup (already done for the current VM)
- OpenSSH Server installed + running on the VM, firewall + NSG allow port 22
- Keys live in `C:\ProgramData\ssh\administrators_authorized_keys` on the VM
  (strict ACL: only SYSTEM + Administrators, plain ASCII encoding). Each
  connecting PC gets its own key added automatically on first run.

### Troubleshooting
- **"No tunnel detected" on the VM** — the tunnel isn't running on the PC (check for the minimized "enable-proxy-point" window, or run it manually), or it failed to bind (check its window)
- **Permission denied (publickey)** — key not deployed, wrong encoding (must be ASCII/UTF-8 no BOM), wrong ACL on `administrators_authorized_keys`, or the key was created with a passphrase
- **Browser shows the Azure IP** — you launched a normal browser window instead of the shortcut; the proxy applies only to the dedicated profile

### Proxying Rivhit, Chrome, and Edge together via ProxiFyre

Beyond the dedicated-profile browser shortcut above, this repo also supports
[ProxiFyre](https://github.com/wiresock/proxifyre), a free/open-source
Windows SOCKS5 "proxifier" that redirects a named process's traffic at the
network-driver level — no proxy settings or special launch args needed on
the app's part at all. This is used for a single unified toggle that covers
**Rivhit + Chrome + Edge together**.

**Currently configured for:**
- The entire `C:\Rivhit\` install folder (matched by path, not just
  `rivhit125.exe`) — this also covers helper/child processes Rivhit spawns
  under a different exe name (e.g. `icredit.exe`, `BatchEMV.exe`), since
  ProxiFyre matches by process name/path and does **not** follow
  parent→child relationships; same-named multiple instances of one exe are
  already covered automatically, but a differently-named child needs its
  own match, which is why the whole folder is targeted here.
- `chrome.exe` and `msedge.exe` by name — this covers **every** window and
  profile of those browsers, not just a dedicated one. That's a deliberate
  choice: while the proxy is toggled on, all Chrome/Edge browsing on the VM
  exits via your PC, not just a special profile.

- **One-time setup (on the VM, elevated PowerShell):**
  `.\scripts\deploy-proxifyre.ps1`
  Installs the VC++ 2022 redistributable, the Windows Packet Filter (NDISAPI)
  driver, ProxiFyre itself as a Windows service (`ProxiFyreService`), and
  **required Windows Firewall allow rules for `ProxiFyre.exe`** — without
  those rules the driver still intercepts matched processes' traffic, but
  ProxiFyre's own relay connection to the SOCKS endpoint silently hangs/times
  out with no visible error (confirmed via live testing — this is the one
  non-obvious gotcha with this tool). The Windows service remains
  **StartType=Manual**, so it never starts merely because Windows boots.
  `proxyPoint.appProxyMode` controls whether the Proxy Point workflow starts
  and stops it automatically or leaves it under shortcut control.
  The deploy script also runs `deploy-vm-shortcuts.ps1` to recreate all
  Proxy Point/App Proxy desktop shortcuts.
- **Manual use/override:** on the VM, double-click the **"Start App Proxy"** desktop
  shortcut (or run `.\scripts\vm-start-app-proxy.ps1` elevated). This starts
  `ProxiFyreService` and launches/restarts Rivhit so it's captured from
  launch. Chrome/Edge are **not** force-closed (to avoid losing open tabs) —
  open a new tab/window (or close and reopen) so it routes through the proxy.
- **To stop:** double-click **"Stop App Proxy"** (or run
  `.\scripts\vm-stop-app-proxy.ps1` elevated). This stops the service and
  closes Rivhit (restart it to resume normal VM/Azure egress); close and
  reopen Chrome/Edge windows to fully return them to normal egress too.
- **To proxy additional/different apps:** edit
  `C:\ProxiFyre\app-config.json` on the VM (add executable names or
  `"C:\\SomeFolder\\"`-style paths to `appNames`, or add another object to
  the `proxies` array to route a different app through a different SOCKS
  endpoint), then restart `ProxiFyreService`. See the
  [ProxiFyre config reference](https://github.com/wiresock/proxifyre#configuration)
  for all options (per-app rules, exclusions, LAN bypass, etc.).
- **Requires** the Proxy Point tunnel to already be running (same
  `localhost:1080` SOCKS proxy the browser shortcut uses) — both start/stop
  scripts check for it and fail fast with a clear message if it's down.
- With `appProxyMode: "automatic"`, the service follows the owning tunnel's
  lifetime. With `"manual"`, nothing is transparently proxied until someone
  runs **Start App Proxy**. The shortcuts remain available in both modes as
  per-session overrides.

## 💰 Cost Savings

- **Before:** VM running 24/7 = ~$50-100/month
- **After:** Intelligent auto-hibernation = ~$10-20/month  
- **Your Savings:** Up to **80% cost reduction**
- **Zero manual intervention** required

## 🔧 Advanced Features

- **Auto-update system** - Always uses latest script versions
- **Smart VM resume detection** - Waits for hibernated VMs to fully boot
- **Separate monitor process** - Continues running even if main script closes
- **Configurable timing** - Adjust hibernation delay as needed
- **Error handling** - Robust operation with detailed debugging
- **Git integration** - Automatic updates from repository

## 📝 Prerequisites

1. **Azure CLI** installed and configured
2. **Git** installed (for auto-updates)
3. **PowerShell** execution policy allowing script execution
4. **VM hibernation enabled** (run
   [`internal/enable-hibernation.ps1`](internal/enable-hibernation.ps1) first)

## 🆘 Troubleshooting

### **VM Won't Hibernate:**
- Check that hibernation is enabled: run
  [`internal/enable-hibernation.ps1`](internal/enable-hibernation.ps1)
- Verify page file is on C: drive (not temp D: drive)
- Ensure VM size supports hibernation (Dsv5, Esv5, etc.)

### **Monitor Not Working:**
- Set `hibernation.showMonitorWindow` to `true` in `config.json`
- Check that
  [`scripts/hibernation-monitor.ps1`](scripts/hibernation-monitor.ps1) exists
- Verify Azure CLI authentication and permissions

### **Auto-Update Issues:**
- Ensure you're in a git repository directory
- Check git credentials and network connectivity
- Set `autoUpdate.enabled` to `false` in `config.json`

## 📚 Documentation

- **[`internal/README.md`](internal/README.md)** - Documentation index (current vs. historical)
- **[`internal/auto-hibernate-guide.md`](internal/auto-hibernate-guide.md)** - Detailed usage guide
- **[`internal/hibernation-enablement-guide.md`](internal/hibernation-enablement-guide.md)** - Technical setup
- **[`internal/hibernation-quick-reference.md`](internal/hibernation-quick-reference.md)** - Quick commands
- **[`internal/fix-pagefile-hibernation.md`](internal/fix-pagefile-hibernation.md)** - Troubleshooting
- **[`internal/proxy-point-operations.md`](internal/proxy-point-operations.md)** - Proxy Point/App Proxy behavior, verification, recovery, and troubleshooting
- **[`internal/israel-region-migration-record.md`](internal/israel-region-migration-record.md)** - Durable record of the Germany-to-Israel migration and pending cleanup

---

**🎉 Enjoy your intelligent VM hibernation system with automatic updates and massive cost savings!**