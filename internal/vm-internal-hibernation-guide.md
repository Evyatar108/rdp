# VM Internal Hibernation Monitor Guide

## Overview

The VM Internal Hibernation Monitor is the primary automatic hibernation
mechanism. It runs inside the VM, so it does not depend on the local RDP
launcher or the connecting PC remaining online.

The external RDP-process monitor is deliberately disabled in `config.json`.

## Hibernation behavior

- Runs inside the VM as a scheduled task
- Measures keyboard and mouse inactivity with `GetLastInputInfo`
- Hibernates after 60 minutes of inactivity
- Uses the VM's managed identity to call Azure without a human refresh token

## 🚀 Quick Setup

### **1. Deploy to VM**
```powershell
# Copy the deployment script to your VM, then run:
.\scripts\deploy-internal-monitor.ps1

# Or with custom timeout:
.\scripts\deploy-internal-monitor.ps1 -InactivityTimeoutMinutes 15
```

### **2. Verify Installation**
```powershell
# Check status:
.\scripts\deploy-internal-monitor.ps1

# View live logs:
Get-Content $env:TEMP\hibernation-monitor.log -Wait
```

### **3. Uninstall (if needed)**
```powershell
.\scripts\deploy-internal-monitor.ps1 -Uninstall
```

## ⚙️ Configuration

### **JSON Configuration:**
```json
{
  "hibernation": {
    "internal": {
      "enabled": true,
      "inactivityTimeoutMinutes": 60,
      "checkIntervalSeconds": 60
    }
  }
}
```

### **Settings Explained:**
- **`enabled`** - Enable/disable internal monitoring
- **`inactivityTimeoutMinutes`** - Minutes of inactivity before hibernation
- **`checkIntervalSeconds`** - How often to check for activity

## 🔍 How It Works

### **Activity detection**

The monitor uses the Windows `GetLastInputInfo` API in `shabi108`'s
interactive session. It does not infer activity from running applications or
background processes.

### **Hibernation process**

1. Check idle time every 60 seconds.
2. At the threshold, log into Azure with the VM's managed identity.
3. Run `az vm deallocate --hibernate true` for the configured VM.
4. Log Azure errors and retry while the VM remains idle.

## 🔧 Advanced Features

### **Automatic Startup:**
- **Scheduled task** - Starts at `shabi108` logon
- **Interactive user** - Required for session-specific idle input
- **Recovery trigger** - Retries every minute if the monitor exits
- **Single instance** - Prevents duplicate monitors

## 📝 Monitoring & Logging

### **Log File Location:**
`C:\VMHibernation\hibernation-monitor.log`

### **Sample Log Entries:**
```
[2024-01-15 14:30:00] 🔍 VM Internal Hibernation Monitor Started
[2024-01-15 14:30:00]    Inactivity timeout: 10 minutes
[2024-01-15 14:30:00]    Check interval: 60 seconds
[2024-01-15 14:35:00] No activity detected for 5.2 minutes (check 1/10)
[2024-01-15 14:45:00] User activity detected, resetting inactivity counter
[2024-01-15 15:00:00] Inactivity threshold reached, hibernating VM...
```

### **Status Commands:**
```powershell
# Check scheduled task status
Get-ScheduledTask -TaskName "VMHibernationMonitor"

# View task history
Get-ScheduledTaskInfo -TaskName "VMHibernationMonitor"

# Monitor live activity
Get-Content $env:TEMP\hibernation-monitor.log -Wait
```

## 🎛️ Troubleshooting

### **Common Issues:**

#### **Monitor Not Starting:**
```powershell
# Check if task exists
Get-ScheduledTask -TaskName "VMHibernationMonitor"

# Start manually
Start-ScheduledTask -TaskName "VMHibernationMonitor"

# Check task logs
Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" | Where-Object {$_.Message -like "*VMHibernationMonitor*"}
```

#### **Hibernation Not Working:**
```powershell
# Test hibernation manually
Stop-Computer -Force -Hibernate

# Check hibernation support
powercfg /availablesleepstates

# Verify hibernation is enabled
powercfg /hibernate on
```

#### **False Activity Detection:**
- Check log file for specific processes being detected
- Adjust `inactivityTimeoutMinutes` if needed
- Review running background processes

### **Debug Mode:**
```powershell
# Run monitor manually for debugging
.\vm-internal-hibernation-monitor.ps1 `
    -InactivityTimeoutMinutes 2 `
    -CheckIntervalSeconds 10 `
    -SubscriptionId "<subscription-id>" `
    -ResourceGroup "<resource-group>" `
    -VMName "<vm-name>"
```

## 💡 Best Practices

### **Recommended Settings:**
- **Development VM:** 15-30 minutes timeout
- **Production VM:** 10-15 minutes timeout  
- **Demo VM:** 5-10 minutes timeout
- **Shared VM:** 20-30 minutes timeout

### **Performance Tips:**
- Monitor runs efficiently with minimal CPU impact
- Log file auto-rotates to prevent disk space issues
- Scheduled task has built-in restart capabilities
- Check interval can be increased for less frequent monitoring

### **Security considerations**

- The monitor uses isolated Azure CLI state under
  `C:\VMHibernation\.azure-managed-identity`.
- The `DesktopVM Self Hibernate Operator` role is assigned only on DesktopVM.
- The role permits only VM read and deallocate actions.
- No human Azure refresh token is required or stored for the task.

## External monitor

`hibernation.external.enabled` remains `false`. If it is intentionally enabled
later, both monitors act independently and whichever reaches Azure first will
hibernate the VM.