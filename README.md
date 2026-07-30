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
├── 📂 scripts/            ← Internal scripts (auto-updated)
│   ├── 📄 config-loader.ps1
│   ├── 📄 update-scripts.ps1
│   ├── 📄 connect-vm-rdp.ps1
│   └── 📄 hibernation-monitor.ps1
└── 📂 internal/           ← Setup and docs
    ├── 📄 enable-hibernation.ps1
    └── 📄 *.md documentation
```

### **What You See:**
- **[`vm-rdp.ps1`](vm-rdp.ps1)** - **Only script you need to run!**
- **[`config.json`](config.json)** - **All configuration in one place**
- **[`README.md`](README.md)** - This usage guide

### **Auto-Managed Scripts:**
- **[`scripts/config-loader.ps1`](scripts/config-loader.ps1)** - Configuration loader
- **[`scripts/update-scripts.ps1`](scripts/update-scripts.ps1)** - Handles git pull updates
- **[`scripts/connect-vm-rdp.ps1`](scripts/connect-vm-rdp.ps1)** - RDP connection logic
- **[`scripts/hibernation-monitor.ps1`](scripts/hibernation-monitor.ps1)** - Monitor process

### **Setup & Documentation:**
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
- Set `$MONITOR_WINDOW_VISIBLE = $true` to see hibernation monitor
- Window shows detailed progress and stays open for debugging
- See exactly when RDP closes and countdown starts

### **Production Mode:**
- Set `$MONITOR_WINDOW_VISIBLE = $false` for clean operation
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
3. Starts the tunnel in a minimized window alongside the RDP session

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
    "reconnectDelaySeconds": 5
  }
}
```

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
  non-obvious gotcha with this tool). The service is left **stopped,
  StartType=Manual** — it never starts on its own (not on boot, not tied to
  Proxy Point's RDP auto-start) so it stays a deliberate, manual toggle.
- **To use it:** on the VM, double-click the **"Start App Proxy"** desktop
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
- **Not automatic:** unlike the tunnel itself, this toggle is intentionally
  **not** wired into `connect-vm-rdp.ps1`'s auto-start — nothing is proxied
  until someone deliberately runs the "Start App Proxy" shortcut.

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
4. **VM hibernation enabled** (run [`enable-hibernation.ps1`](enable-hibernation.ps1) first)

## 🆘 Troubleshooting

### **VM Won't Hibernate:**
- Check that hibernation is enabled: run [`enable-hibernation.ps1`](enable-hibernation.ps1)
- Verify page file is on C: drive (not temp D: drive)
- Ensure VM size supports hibernation (Dsv5, Esv5, etc.)

### **Monitor Not Working:**
- Set `$MONITOR_WINDOW_VISIBLE = $true` to see debug output
- Check that [`hibernation-monitor.ps1`](hibernation-monitor.ps1) exists in same directory
- Verify Azure CLI authentication and permissions

### **Auto-Update Issues:**
- Ensure you're in a git repository directory
- Check git credentials and network connectivity
- Set `$AUTO_UPDATE_ENABLED = $false` in [`scripts/update-scripts.ps1`](scripts/update-scripts.ps1)

## 📚 Documentation

- **[`internal/auto-hibernate-guide.md`](internal/auto-hibernate-guide.md)** - Detailed usage guide
- **[`internal/hibernation-enablement-guide.md`](internal/hibernation-enablement-guide.md)** - Technical setup
- **[`internal/hibernation-quick-reference.md`](internal/hibernation-quick-reference.md)** - Quick commands
- **[`internal/fix-pagefile-hibernation.md`](internal/fix-pagefile-hibernation.md)** - Troubleshooting

---

**🎉 Enjoy your intelligent VM hibernation system with automatic updates and massive cost savings!**