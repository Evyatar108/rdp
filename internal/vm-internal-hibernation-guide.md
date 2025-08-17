# VM Internal Hibernation Monitor Guide

## 🎯 Overview

The VM Internal Hibernation Monitor provides **backup hibernation** that runs **inside the VM itself**. This ensures your VM hibernates even when:

- External RDP monitoring fails
- Network connectivity is lost
- You forget to close RDP properly
- The external monitoring script crashes

## 🛡️ Dual Hibernation Protection

### **Primary: External RDP Monitor**
- Monitors RDP connection from outside the VM
- Hibernates when you close RDP (2 minutes delay)
- Fast response, ideal for normal usage

### **Backup: Internal Inactivity Monitor**
- Runs inside the VM as a scheduled task
- Monitors user activity (keyboard, mouse, active sessions)
- Hibernates after 10 minutes of complete inactivity
- Always running, provides safety net

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
      "inactivityTimeoutMinutes": 10,
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

### **Activity Detection:**
1. **Keyboard/Mouse Input** - Uses Windows API to detect last input time
2. **Active RDP Sessions** - Checks for active remote desktop connections  
3. **User Processes** - Monitors for running browsers, Office apps, development tools
4. **System Activity** - Combines all indicators for smart decision making

### **Hibernation Process:**
1. **Detection Phase** - Continuously monitors for user activity
2. **Validation Phase** - Confirms inactivity across multiple checks
3. **Hibernation Phase** - Tries multiple hibernation methods for reliability
4. **Logging** - Records all activity for debugging and monitoring

## 📊 Activity Monitoring

### **Monitored Processes:**
- **Browsers:** Chrome, Firefox, Edge
- **Office:** Word, Excel, PowerPoint
- **Development:** Visual Studio Code, Visual Studio
- **System:** Notepad, Command Prompt, PowerShell

### **Monitored Inputs:**
- Keyboard activity
- Mouse movement and clicks
- Remote desktop sessions
- System interactions

## 🔧 Advanced Features

### **Intelligent Detection:**
- **Multi-factor activity checking** - Combines input timing + process monitoring
- **False positive prevention** - Requires consistent inactivity across multiple checks
- **Session awareness** - Considers active RDP sessions as user activity
- **Process filtering** - Ignores system processes, focuses on user applications

### **Robust Hibernation:**
- **Primary method:** PowerShell `Stop-Computer -Hibernate`
- **Fallback 1:** Windows `shutdown /h` command
- **Fallback 2:** Direct Windows API call via `rundll32`
- **Error handling:** Comprehensive logging of hibernation attempts

### **Automatic Startup:**
- **Scheduled Task** - Starts automatically with Windows
- **System Level** - Runs as NT AUTHORITY\SYSTEM for reliability
- **Auto-restart** - Restarts automatically if the process crashes
- **Delayed start** - 2-minute delay after boot to allow system initialization

## 📝 Monitoring & Logging

### **Log File Location:**
```
%TEMP%\hibernation-monitor.log
```

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
.\vm-internal-hibernation-monitor.ps1 -InactivityTimeoutMinutes 2 -CheckIntervalSeconds 10
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

### **Security Considerations:**
- Runs as SYSTEM account for reliability
- No network communication required
- Local activity monitoring only
- No sensitive data logged

## 🔗 Integration with External Monitor

The internal monitor works **alongside** the external RDP monitor:

### **Cooperation Logic:**
1. **External monitor** hibernates when RDP closes (2 minutes)
2. **Internal monitor** hibernates after inactivity (10 minutes)
3. **Whichever triggers first** will hibernate the VM
4. **Both provide safety nets** for different scenarios

### **Typical Scenarios:**
- **Normal usage:** External monitor hibernates when you close RDP
- **Forgotten session:** Internal monitor hibernates after inactivity timeout
- **Network issues:** Internal monitor continues working independently
- **Process crashes:** The other monitor provides backup

This creates a **robust, fail-safe hibernation system** that maximizes cost savings while ensuring reliability! 🎉