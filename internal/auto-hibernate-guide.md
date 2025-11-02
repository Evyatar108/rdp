# 🛌 Auto-Hibernate on RDP Disconnect

## 🎯 **How It Works**

The updated [`connect-vm-rdp.ps1`](connect-vm-rdp.ps1) script now includes automatic hibernation:

1. **Starts VM** if not running
2. **Launches RDP** connection
3. **Monitors RDP process** in the background
4. **Detects when RDP window closes**
5. **Waits 2 minutes** (grace period for reconnection)
6. **Hibernates VM automatically**

## 🚀 **Usage**

Simply run the connect script as usual:
```powershell
.\connect-vm-rdp.ps1
```

**What happens:**
- ✅ RDP window opens for your VM connection
- 🔍 Script monitors the RDP process in background
- 🔌 When you close the RDP window, countdown starts
- ⏱️ 2-minute grace period (press Ctrl+C to cancel)
- 🛌 VM hibernates automatically
- 💰 **No compute charges** while hibernated

## 🎛️ **User Control**

- **Cancel hibernation**: Press `Ctrl+C` during the 2-minute countdown
- **Reconnect**: Run the script again to resume and reconnect
- **Manual hibernation**: Close PowerShell window to skip auto-hibernation

## 💡 **Benefits**

### Cost Optimization
- **Automatic savings**: No more forgetting to hibernate
- **Grace period**: 2 minutes to reconnect if needed
- **Immediate**: Hibernation starts right after RDP closes

### Convenience
- **Single script**: Connect and auto-hibernate in one
- **Smart detection**: Monitors actual RDP window, not just connections
- **User control**: Easy to cancel if you need VM to stay running

### State Preservation
- **Exact resume**: All applications and data preserved
- **Fast restart**: ~60 seconds to resume from hibernation
- **Seamless workflow**: Pick up exactly where you left off

## 🔄 **Workflow Example**

1. **Run script**: `.\connect-vm-rdp.ps1`
2. **VM starts**: If not already running
3. **RDP opens**: Connect with username `***`
4. **Work normally**: Use your VM as usual
5. **Close RDP**: When finished, close the RDP window
6. **Auto-countdown**: 2-minute timer starts automatically
7. **VM hibernates**: Automatically saves state and stops compute charges
8. **Next session**: Run script again to resume exactly where you left off

## ⚙️ **Customization Options**

Easy configuration at the top of [`connect-vm-rdp.ps1`](connect-vm-rdp.ps1):

```powershell
# Auto-Hibernation Settings
$HIBERNATION_DELAY_SECONDS = 120  # Change to your preferred delay (e.g., 300 for 5 minutes)
$PROGRESS_UPDATE_INTERVAL = 1     # Update frequency for countdown display
```

**Examples:**
- **5 minutes delay**: `$HIBERNATION_DELAY_SECONDS = 300`
- **30 seconds delay**: `$HIBERNATION_DELAY_SECONDS = 30`
- **10 minutes delay**: `$HIBERNATION_DELAY_SECONDS = 600`

## 🛡️ **Safety Features**

- **Grace period**: 2 minutes to reconnect before hibernation
- **User cancellation**: Ctrl+C anytime during countdown
- **Error handling**: Script handles connection failures gracefully
- **Visual feedback**: Clear progress indicator and status messages

## 📊 **Cost Impact**

**Before**: VM runs 24/7 = ~$50-100/month  
**After**: VM hibernates when not in use = ~$10-20/month  
**Savings**: Up to 80% reduction in compute costs!

Your VM will now automatically hibernate when you close the RDP connection, maximizing cost savings while preserving your exact work state!