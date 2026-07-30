# Hibernation Quick Reference

All Azure identifiers come from the repo-root `config.json`.

## Enable or repair Azure hibernation

From the repo root:

```powershell
.\internal\enable-hibernation.ps1
```

The script:

1. Authenticates to the configured tenant/subscription.
2. Resolves the current VM and OS disk dynamically.
3. Enables OS-disk hibernation support when needed.
4. Enables VM hibernation.
5. Starts and tests a hibernate/resume cycle.

This is disruptive: it deallocates/hibernates and restarts the VM. Do not run
it while another user is working in the VM.

## Check current state

```powershell
$config = Get-Content .\config.json -Raw | ConvertFrom-Json
$rg = $config.azure.target.resourceGroup
$vm = $config.azure.target.vmName

az vm show -g $rg -n $vm `
  --query "{hibernation:additionalCapabilities.hibernationEnabled,osDisk:storageProfile.osDisk.name}" `
  -o json

$disk = az vm show -g $rg -n $vm --query "storageProfile.osDisk.name" -o tsv
az disk show -g $rg -n $disk --query "supportsHibernation" -o tsv
```

## Hibernate and resume manually

```powershell
az vm deallocate -g $rg -n $vm --hibernate
az vm start -g $rg -n $vm
```

## Active automatic behavior

See `config.json`:

- `hibernation.internal.enabled`: VM-side inactivity monitor.
- `hibernation.external.enabled`: PC-side monitor after the RDP process closes.
- `hibernation.internal.inactivityTimeoutMinutes`: internal idle threshold.
- `hibernation.timing.delayAfterRdpCloseSeconds`: external grace period.

See `internal/auto-hibernate-guide.md` for operational details.
