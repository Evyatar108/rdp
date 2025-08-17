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
    "showMonitorWindow": true
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