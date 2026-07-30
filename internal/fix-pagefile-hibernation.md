# 🛠️ Fix Page File for Hibernation

This procedure applies to whichever VM is currently selected in the repo-root
`config.json`. The original incident occurred on the retired Germany VM, so
do not reuse the old `VM-RG-TARGET` identifier.

## ❌ **Current Issue**
```
The Hibernate-Deallocate Operation cannot be performed on a VM that has extension 
'AzureHibernateExtension' in failed state. Error details from the extension: 
Page file is in temp disk. Please move it to OS disk to enable hibernation.
```

## 🎯 **Root Cause**
Your VM's page file is currently on the **temporary disk (D: drive)** instead of the **OS disk (C: drive)**. Hibernation requires the page file to be on the OS disk because:
- Temporary disk contents are lost during hibernation
- Page file contains memory state needed for hibernation
- OS disk persists through hibernation/resume cycles

## 🔧 **Solution Steps**

### Step 1: Connect to VM
```bash
# From the repo root, resolve the current target
$config = Get-Content .\config.json -Raw | ConvertFrom-Json
$rg = $config.azure.target.resourceGroup
$vm = $config.azure.target.vmName
az vm show -g $rg -n $vm -d --query publicIps -o tsv

# Connect via RDP using the public IP
```

### Step 2: Move Page File to C: Drive (Inside Windows VM)

1. **Open System Properties**:
   - Right-click "This PC" → Properties
   - Click "Advanced system settings"
   - Click "Settings" under Performance
   - Go to "Advanced" tab → "Change" under Virtual memory

2. **Configure Page File**:
   - Uncheck "Automatically manage paging file size for all drives"
   - Select **C: drive**
   - Choose "System managed size" or "Custom size"
   - Select **D: drive (temp disk)**
   - Choose "No paging file"
   - Click "Set" for both drives
   - Click "OK" and restart VM

### Step 3: Alternative PowerShell Method (Inside Windows VM)
```powershell
# Run inside Windows VM as Administrator
# Remove page file from temp disk (D:)
$pagefile = Get-WmiObject -Class Win32_PageFileSetting
$pagefile | Where-Object {$_.Name -like "D:*"} | Remove-WmiObject

# Add page file to OS disk (C:)
$pageFileSize = (Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB * 1.5
New-WmiObject -Class Win32_PageFileSetting -Arguments @{
    Name = "C:\pagefile.sys"
    InitialSize = [int]$pageFileSize * 1024
    MaximumSize = [int]$pageFileSize * 1024
}

# Restart required
Restart-Computer -Force
```

### Step 4: Verify Page File Location
```powershell
# Inside Windows VM - check page file location
Get-WmiObject -Class Win32_PageFileSetting | Select-Object Name, InitialSize, MaximumSize
```

### Step 5: Re-test Hibernation (From Azure CLI)
```powershell
# After page file is moved and VM restarted
$config = Get-Content .\config.json -Raw | ConvertFrom-Json
$rg = $config.azure.target.resourceGroup
$vm = $config.azure.target.vmName
az vm deallocate -g $rg -n $vm --hibernate
az vm start -g $rg -n $vm
```

## 📋 **Repair Sequence**

1. Confirm the current VM size supports hibernation.
2. Move the page file from the temporary disk to the OS disk.
3. Restart Windows.
4. Run `.\internal\enable-hibernation.ps1` from the repo root.
5. Verify state preservation after the test hibernate/resume cycle.

## 🚨 **Important Notes**

- **VM must be running** to change page file settings
- **Restart required** after page file changes
- **System-managed size** is recommended (1.5x RAM)
- **Monitor C: drive space** - ensure sufficient space for page file

## ⚡ **Quick Fix Commands**

```text
# Connect to VM first, then run inside Windows:
# 1. Open PowerShell as Administrator
# 2. Run the PowerShell commands above
# 3. Restart VM
# 4. Run internal\enable-hibernation.ps1 from the repo root
```

## 🔍 **Verification Steps**

After fixing page file:
1. **Check page file location**: Should be on C: drive only
2. **Test hibernation**: `az vm deallocate -g $rg -n $vm --hibernate`
3. **Test resume**: `az vm start -g $rg -n $vm`
4. **Verify state preservation**: Applications should resume exactly as left

## 📚 **References**

- [Maintained hibernation enablement guide](hibernation-enablement-guide.md)
- [Windows Page File Configuration](https://docs.microsoft.com/windows/client-management/introduction-page-file)
- [Azure Hibernation Troubleshooting](https://aka.ms/hibernate-resume/errors)