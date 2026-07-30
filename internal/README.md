# Internal Documentation Index

The `internal` folder contains both maintained runbooks and historical
migration artifacts. Use this index to avoid applying old Germany/cross-tenant
instructions to the current Israel Central VM.

## Current maintained runbooks

- `auto-hibernate-guide.md` - current internal/external monitor behavior and
  `config.json` settings.
- `hibernation-enablement-guide.md` - enable or repair Azure hibernation for
  the VM currently selected in `config.json`.
- `hibernation-quick-reference.md` - concise hibernate/resume commands.
- `fix-pagefile-hibernation.md` - repair the Windows page-file prerequisite.
- `vm-internal-hibernation-guide.md` - detailed VM-side monitor operations.
- `proxy-point-operations.md` - Proxy Point and ProxiFyre usage,
  verification, rebuild, and troubleshooting.
- `israel-region-migration-record.md` - completed Germany-to-Israel cutover
  record and pending cleanup inventory.
- `disable-rdp-manual-steps.md` - RDP policy/manual configuration notes.

## Current setup scripts

- `enable-hibernation.ps1` - config-driven Azure hibernation enablement and
  test cycle. This deallocates/hibernates/restarts the current VM.

Most other active automation lives in the repo-root `scripts` folder.

## Historical artifacts - do not run against the current VM

- `task.md` - original cross-tenant subscription-copy objective.
- `copy-vm.ps1` - original cross-tenant/AzCopy migration script, hardcoded to
  the old Germany target. It is retained only as history.
- `original-vm-arm.json`, `copied-vm-arm.json`, `full-rg-arm.json` - ARM
  snapshots from the older migration.
- `hibernation-doc.md` - archived 2024 Microsoft Learn source snapshot with
  documentation-build includes that do not resolve in this repo.

The current VM identifiers must always come from the repo-root `config.json`.
See the repo-root `README.md`, `CLAUDE.md`, and
`.github/skills/azure-vm-rdp-ops/SKILL.md` for the current operational model.
