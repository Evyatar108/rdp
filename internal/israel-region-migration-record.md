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

## Rollback and pending cleanup

The old Germany VM was left deallocated rather than immediately deleted.
Cleanup still requires explicit user approval.

Known cleanup candidates:

- resource group `VM-RG-TARGET`
- Germany snapshots `os-snap-move-il`, `data0-snap-move-il`
- Israel copy snapshots `os-snap-il`, `data0-snap-il`

Before deleting anything:

1. Confirm the Israel VM boots and RDP works.
2. Confirm the Rivhit application/data and attached data disk are intact.
3. Confirm hibernation/resume works.
4. Confirm no DNS, scripts, credentials, or integrations still reference the
   old Germany public IP or resource IDs.
5. Inventory the candidate resources with Azure CLI and obtain explicit user
   confirmation for the exact deletion list.

Do not treat this document as deletion authorization.
