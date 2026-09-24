# DesktopVM Germany to Israel Central Migration Record

This is the durable repo record for the completed regional copy/cutover. It is
historical documentation, not an executable migration plan.

## Outcome

- **Current VM:** `DesktopVM`
- **Current resource group:** `VM-RG-ISRAEL`
- **Current region:** Israel Central
- **Current configuration source:** `config.json` -> `azure.target`
- **Previous resource group/region:** `VM-RG-TARGET`,
  `germanywestcentral`
- **Cutover date:** 2026-07-29

The official GitHub repo and connection scripts now target the Israel Central
VM. RDP and Proxy Point were verified against that VM.

## Migration method

The source and target were in the same subscription, so the move used Azure
incremental snapshots and cross-region snapshot copy (`az snapshot create
--copy-start`) rather than the older cross-tenant Storage Account/AzCopy flow
described in `internal/task.md` and `internal/copy-vm.ps1`.

High-level sequence:

1. Deallocate the Germany VM for disk consistency.
2. Snapshot the OS and data disks.
3. Copy snapshots to Israel Central.
4. Create managed disks from the copied snapshots.
5. Recreate networking with a Standard public IP.
6. Create the VM from the copied OS disk and attach the data disk at LUN 0.
7. Restore hibernation support.
8. Verify boot, RDP, data, and user access.
9. Update `config.json` and repo scripts to target `VM-RG-ISRAEL`.
10. Keep the Germany resources temporarily as rollback protection.

## Relevant repo changes

- `config.json` switched the target resource group to `VM-RG-ISRAEL`.
- Proxy Point and App Proxy automation were subsequently built and validated
  against the Israel Central VM.
- `CLAUDE.md` documents the current operational identifiers and agent gotchas.
- `.github/skills/azure-vm-rdp-ops/SKILL.md` contains the reusable Copilot CLI
  operational skill.

## Germany retirement (completed 2026-09-24)

The Germany environment was deleted on 2026-09-24 with explicit user approval.

### Why it needed a safety copy first

The Germany VM did not stay deallocated after the cutover. The Azure activity
log shows it was started again on 2026-07-30 10:22 UTC — the day after the
migration snapshots were taken — and it then ran continuously until
2026-08-27 14:37 UTC. During that window the launcher was failing on at least
one PC, and the RDP file downloaded from the Azure portal pointed at the
Germany VM, so real work may have been done there.

That means the Jul 29 migration snapshots no longer represented the Germany
disks' final state. Before deleting, the disks were captured as they stood.

### Deleted

- VM `DesktopVM` (germanywestcentral)
- disks `DesktopVM-OS-Managed` (127 GB), `DesktopVM-Data0-Managed` (32 GB)
- network `vnet-DesktopVM`, `nic-desktopvm`, `pip-desktopvm`
- storage account `vhdstgt830292774`, holding the orphaned original unmanaged
  VHDs `osdisk.vhd` and `datadisk0.vhd` (159 GB provisioned, untouched since
  2025-08-17, no lease)
- stale Jul 29 snapshots `os-snap-move-il`, `data0-snap-move-il`, which only
  duplicated what had already been copied to Israel

### Retained

Resource group `VM-RG-TARGET` still exists and holds only the final-state
safety snapshots:

- `desktopvm-os-final-20260924` (127 GB)
- `desktopvm-data0-final-20260924` (32 GB)

Both are full (non-incremental) `Standard_LRS` snapshots, so they are
independent of the now-deleted source disks and can be restored to managed
disks on their own. They are the only remaining route to anything written on
the Germany VM between 2026-07-30 and 2026-08-27.

Delete them only after confirming nothing from that window is needed.

## Israel migration snapshots

`os-snap-il` and `data0-snap-il` are still present in `VM-RG-ISRAEL`.

They are not required for the Israel VM to run. The live disks were created
from them with `createOption: Copy`, which produces a full independent copy;
`completionPercent` is null, confirming no copy operation is outstanding.
Deleting these snapshots does not affect the running VM. They are rollback
copies of the Jul 29 disk state only.
