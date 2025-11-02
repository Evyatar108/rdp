# 🛌 Hibernation Quick Reference

## 🚀 Quick Start
To enable hibernation on your copied VM, simply run:
```powershell
.\enable-hibernation.ps1
```

## 📊 Your VM Configuration
- **VM Name**: [`DesktopVM`](copied-vm-arm.json:27)
- **Resource Group**: [`VM-RG-TARGET`](copied-vm-arm.json:10) 
- **Subscription**: [`30748a75-b2b8-4e4f-b5df-e87aa4ceef7b`](copied-vm-arm.json:10)
- **VM Size**: Dsv5-series ✅ (hibernation-compatible)
- **OS Disk**: [`DesktopVM-OS-Managed`](copied-vm-arm.json:10)

## 📋 Manual Steps (Alternative to Script)

### 1. Login & Context
```bash
az login --tenant 66d51e14-99b9-435a-8c05-449dc0c91710
az account set --subscription 30748a75-b2b8-4e4f-b5df-e87aa4ceef7b
```

### 2. Enable Hibernation
```bash
# Deallocate VM
az vm deallocate --resource-group VM-RG-TARGET --name DesktopVM

# Update OS disk
az disk update --resource-group VM-RG-TARGET --name DesktopVM-OS-Managed --set supportsHibernation=true

# Enable hibernation on VM
az vm update --resource-group VM-RG-TARGET --name DesktopVM --enable-hibernation true

# Start VM
az vm start --resource-group VM-RG-TARGET --name DesktopVM
```

### 3. Test Hibernation
```bash
# Hibernate VM
az vm deallocate --resource-group VM-RG-TARGET --name DesktopVM --hibernate

# Resume from hibernation
az vm start --resource-group VM-RG-TARGET --name DesktopVM
```

## ✅ Success Criteria
- [`hibernationEnabled`](hibernation-doc.md:110): `true`
- [`supportsHibernation`](hibernation-doc.md:138): `true` (OS disk)
- VM can hibernate and resume successfully
- Windows hibernation extension installed automatically

## 🔧 Files Created
1. [`hibernation-enablement-guide.md`](hibernation-enablement-guide.md) - Comprehensive guide
2. [`enable-hibernation.ps1`](enable-hibernation.ps1) - Automated script
3. [`hibernation-quick-reference.md`](hibernation-quick-reference.md) - This file

## 🎯 Benefits After Hibernation
- **Cost Savings**: No compute charges while hibernated
- **Fast Resume**: Restore exact VM state in ~60 seconds
- **State Preservation**: All applications and data preserved
- **Flexible Scheduling**: Hibernate during non-business hours