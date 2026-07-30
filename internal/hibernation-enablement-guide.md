# VM Hibernation Enablement Guide

This guide applies to the VM currently configured in the repo-root
`config.json`. It supersedes the earlier Germany/`VM-RG-TARGET` instructions.

## Prerequisites

- Azure CLI installed.
- Permission to update the configured VM and its OS disk.
- A VM size and Windows edition supported by Azure hibernation.
- Page file located on the persistent OS disk, not the Azure temporary disk.
- No active user workload: enabling/testing hibernation is disruptive.

## Automated setup

From the repo root:

```powershell
.\internal\enable-hibernation.ps1
```

The script reads:

- tenant ID
- subscription ID
- resource group
- VM name

from `config.json`, and dynamically resolves the OS disk name from the VM.

It then:

1. Selects the correct Azure tenant/subscription.
2. Checks the current power and hibernation state.
3. Deallocates the VM if required.
4. Enables `supportsHibernation` on the OS disk.
5. Enables VM hibernation.
6. Starts the VM.
7. Performs a hibernate/resume test.

## Manual verification

```powershell
$config = Get-Content .\config.json -Raw | ConvertFrom-Json
$rg = $config.azure.target.resourceGroup
$vm = $config.azure.target.vmName

az vm show -g $rg -n $vm `
  --query "{name:name,size:hardwareProfile.vmSize,hibernation:additionalCapabilities.hibernationEnabled,power:instanceView.statuses[1].displayStatus}" `
  -o json

$disk = az vm show -g $rg -n $vm --query "storageProfile.osDisk.name" -o tsv
az disk show -g $rg -n $disk `
  --query "{name:name,supportsHibernation:supportsHibernation}" `
  -o json
```

Expected:

- VM `hibernation` is `true`.
- OS disk `supportsHibernation` is `true`.

## Page-file failure

If `AzureHibernateExtension` reports that the page file is on the temporary
disk, follow `internal/fix-pagefile-hibernation.md`, restart Windows, then
rerun the enablement script.

## Automatic hibernation

Azure capability enablement and automatic policy are separate:

- Capability/setup: `internal/enable-hibernation.ps1`
- Internal/external monitor policy: `config.json`
- Monitor deployment/operations: `internal/auto-hibernate-guide.md`
