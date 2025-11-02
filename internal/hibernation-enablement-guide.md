# 🛌 VM Hibernation Enablement Guide

## 📋 Overview
This guide provides step-by-step instructions to enable hibernation on your copied VM in Tenant B.

**VM Configuration:**
- **VM Name**: DesktopVM
- **Resource Group**: VM-RG-TARGET
- **Subscription**: 30748a75-b2b8-4e4f-b5df-e87aa4ceef7b
- **Location**: germanywestcentral
- **VM Size**: Dsv5-series (hibernation-compatible ✅)
- **OS Disk**: DesktopVM-OS-Managed

## 🚀 Implementation Steps

### Step 1: Azure CLI Authentication
```bash
# Login to Tenant B
az login --tenant 66d51e14-99b9-435a-8c05-449dc0c91710

# Set subscription context
az account set --subscription 30748a75-b2b8-4e4f-b5df-e87aa4ceef7b

# Verify current context
az account show
```

### Step 2: Check Current VM Status
```bash
# Check VM current status
az vm show --resource-group VM-RG-TARGET --name DesktopVM -d --query "powerState" -o tsv

# Check if hibernation is already enabled
az vm show --resource-group VM-RG-TARGET --name DesktopVM --query "additionalCapabilities.hibernationEnabled" -o tsv
```

### Step 3: Deallocate VM
```bash
# Stop and deallocate the VM
az vm deallocate --resource-group VM-RG-TARGET --name DesktopVM

# Verify VM is deallocated
az vm show --resource-group VM-RG-TARGET --name DesktopVM -d --query "powerState" -o tsv
```

### Step 4: Update OS Disk for Hibernation
```bash
# Check current hibernation support on OS disk
az disk show --resource-group VM-RG-TARGET --name DesktopVM-OS-Managed --query "supportsHibernation" -o tsv

# Enable hibernation support on OS disk
az disk update --resource-group VM-RG-TARGET --name DesktopVM-OS-Managed --set supportsHibernation=true

# Verify hibernation support is enabled
az disk show --resource-group VM-RG-TARGET --name DesktopVM-OS-Managed --query "supportsHibernation" -o tsv
```

### Step 5: Enable Hibernation on VM
```bash
# Enable hibernation on the VM
az vm update --resource-group VM-RG-TARGET --name DesktopVM --enable-hibernation true

# Verify hibernation is enabled
az vm show --resource-group VM-RG-TARGET --name DesktopVM --query "additionalCapabilities.hibernationEnabled" -o tsv
```

### Step 6: Start VM
```bash
# Start the VM
az vm start --resource-group VM-RG-TARGET --name DesktopVM

# Check VM status
az vm show --resource-group VM-RG-TARGET --name DesktopVM -d --query "powerState" -o tsv
```

## 🔍 Verification Steps

### Verify Hibernation Configuration
```bash
# Check VM hibernation status
az vm show --resource-group VM-RG-TARGET --name DesktopVM -d --query "{Name:name, HibernationEnabled:additionalCapabilities.hibernationEnabled, VMSize:hardwareProfile.vmSize, PowerState:powerState}" -o table

# Check OS disk hibernation support
az disk show --resource-group VM-RG-TARGET --name DesktopVM-OS-Managed --query "{Name:name, SupportsHibernation:supportsHibernation, DiskSizeGB:diskSizeGB}" -o table
```

### Test Hibernation Functionality
```bash
# Hibernate the VM (this will save state and deallocate)
az vm deallocate --resource-group VM-RG-TARGET --name DesktopVM --hibernate

# Resume from hibernation
az vm start --resource-group VM-RG-TARGET --name DesktopVM
```

## 🔧 PowerShell Alternative Commands

### PowerShell Implementation
```powershell
# Login and set context
Connect-AzAccount -Tenant "66d51e14-99b9-435a-8c05-449dc0c91710"
Set-AzContext -Subscription "30748a75-b2b8-4e4f-b5df-e87aa4ceef7b"

# Stop VM
Stop-AzVM -ResourceGroupName "VM-RG-TARGET" -Name "DesktopVM" -Force

# Update OS disk
$disk = Get-AzDisk -ResourceGroupName "VM-RG-TARGET" -DiskName "DesktopVM-OS-Managed"
$disk.SupportsHibernation = $True
Update-AzDisk -ResourceGroupName "VM-RG-TARGET" -DiskName "DesktopVM-OS-Managed" -Disk $disk

# Enable hibernation on VM
$vm = Get-AzVM -ResourceGroupName "VM-RG-TARGET" -Name "DesktopVM"
Update-AzVM -ResourceGroupName "VM-RG-TARGET" -VM $vm -HibernationEnabled

# Start VM
Start-AzVM -ResourceGroupName "VM-RG-TARGET" -Name "DesktopVM"
```

## 📝 Expected Results

After successful hibernation enablement:

1. **VM Configuration**:
   - `hibernationEnabled`: `true`
   - VM size: Dsv5-series (compatible)
   - Status: Running

2. **OS Disk Configuration**:
   - `supportsHibernation`: `true`
   - Disk maintains all existing data

3. **Guest OS Configuration**:
   - Windows hibernation automatically configured via Azure extension
   - Page file moved to C: drive (if not already there)
   - Hibernation available in Windows power options

## ⚠️ Important Notes

- **VM Size**: Ensure VM is Dsv5-series (hibernation-compatible)
- **Page File**: Must be on C: drive for hibernation to work
- **Extension**: `Microsoft.CPlat.Core.WindowsHibernateExtension` will be automatically installed
- **Downtime**: VM will be offline during the hibernation enablement process
- **Testing**: Always test hibernation functionality after enablement

## 🐛 Troubleshooting

### Common Issues:
1. **VM size not compatible**: Verify VM is resized to Dsv5-series
2. **OS disk doesn't support hibernation**: Run disk update command
3. **Page file location**: Ensure page file is on C: drive in guest OS
4. **Extension issues**: Check VM extensions in Azure portal

### Validation Commands:
```bash
# Check VM hibernation capability
az vm show --resource-group VM-RG-TARGET --name DesktopVM --query "additionalCapabilities" -o json

# Check installed extensions
az vm extension list --resource-group VM-RG-TARGET --vm-name DesktopVM --query "[].{Name:name,Publisher:publisher,Type:typeHandlerVersion}" -o table
```

## 🎯 Next Steps

After hibernation is enabled:
1. Test hibernation functionality with `az vm deallocate --hibernate`
2. Verify resume functionality with `az vm start`
3. Configure hibernation policies in guest OS if needed
4. Monitor hibernation behavior and costs