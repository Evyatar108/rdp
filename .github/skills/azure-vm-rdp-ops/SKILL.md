---
name: azure-vm-rdp-ops
description: >
  Operate the Evyatar108/rdp repo's Azure VM (DesktopVM in VM-RG-ISRAEL,
  Israel Central): connecting via RDP, managing hibernation, running commands
  on the VM via az vm run-command, pushing changes to the GitHub repo under
  the Evyatar108 account, and managing the Proxy Point (reverse SSH SOCKS
  tunnel) / ProxiFyre (per-app transparent proxy for Rivhit/Chrome/Edge)
  features. Use when the user mentions this VM, DesktopVM, the rdp repo,
  connect-vm-rdp.ps1, Proxy Point, or ProxiFyre.
---

# Azure VM RDP Ops (Evyatar108/rdp)

This skill lives inside the repo it documents:
`https://github.com/Evyatar108/rdp` at `.github/skills/azure-vm-rdp-ops/SKILL.md`.
See the repo's own `README.md` and `CLAUDE.md` (repo root) for full details —
this skill is a quick-reference for the recurring operational patterns, not a
replacement for reading those files when making changes. Keep this file in
sync with `CLAUDE.md` when things change.

## Known-good environment

- **VM:** `DesktopVM`, resource group `VM-RG-ISRAEL`, region **Israel
  Central** (moved here from `germanywestcentral`/`VM-RG-TARGET`; the old
  Germany RG/snapshots may still exist pending cleanup — check before
  assuming they're gone).
- **VM login user:** `shabi108` (local admin).
- **VM repo clone:** `C:\repos\rdp`.
- **Subscription/tenant/RG/VM name:** always read from `config.json` →
  `azure.target` in the repo — don't hardcode IDs in scripts or answers.
- **This machine's default gh/git account** is NOT the account that owns the
  GitHub repo (`Evyatar108`) — see push workflow below.

## Pushing changes to GitHub

```powershell
cd D:\general-efforts\move
gh auth switch -u Evyatar108
git add <files>
git commit -m "..."
git push origin master
gh auth switch -u evmitran_microsoft   # verify actual default account name first if unsure
```
Always switch back after pushing — forgetting leaves later unrelated git/gh
operations pointed at the wrong account.

## Running commands on the VM (az vm run-command)

```powershell
az vm run-command invoke -g VM-RG-ISRAEL -n DesktopVM --command-id RunPowerShellScript --scripts "@C:\path\to\local\script.ps1" --query "value[0].message" -o tsv
```

Sharp edges (see repo `CLAUDE.md` for full detail):
- **Prefer `--scripts "@path"` (a script file) over inline strings.** Inline
  quoting with `$`, nested quotes, or `{}` frequently breaks or silently
  produces empty output.
- **Local PowerShell expands `$env:...`/variables in a double-quoted
  `--scripts` argument BEFORE sending it.** Use single quotes or the `@file`
  pattern to avoid accidentally baking in local values.
- **Output truncates at ~4KB, keeping the tail, not the head.** For verbose
  diagnostics, write to a file on the VM (or redirect the whole
  `run-command` invocation to a local file with `> out.json 2>&1`) and
  inspect that instead of relying on the returned message text.
- **Runs as SYSTEM, non-interactive Session 0.**
  - Git needs `-c safe.directory=C:/repos/rdp` or it errors on ownership.
  - GUI apps (Chrome, Edge, Rivhit) are unreliable here — may exit
    immediately or crash with misleading exit codes (Session-0/SYSTEM
    profile artifacts, e.g. Crashpad path errors). Validate mechanisms with
    CLI tools (`curl.exe`) or headless flags instead of trusting a GUI app's
    behavior under `run-command`; ask the user to verify interactively over
    RDP for anything GUI-dependent.
  - Only one `run-command` executes at a time server-side — a second
    invocation while the first is still running returns `(Conflict) Run
    command extension execution is in progress`, even after you've locally
    given up waiting on the first. Wait and retry rather than assuming it's
    free.

## VM Desktop is OneDrive-redirected

Any desktop shortcut must be written to
`C:\Users\shabi108\OneDrive\Desktop`, not `C:\Users\shabi108\Desktop` (the
latter is unused and shortcuts placed there are invisible to the user).
Always `Test-Path` first to confirm. Prefer the repo's idempotent
`scripts/deploy-vm-shortcuts.ps1` instead of creating one-off shortcuts.

## Proxy Point (reverse SSH SOCKS tunnel)

The **PC** (not the VM) runs `ssh -R 1080 user@vm-ip`, making the VM's
`localhost:1080` a SOCKS5 proxy that egresses from the PC's network.
`scripts/connect-vm-rdp.ps1` auto-starts this tunnel on every connect (if
`config.json`'s `proxyPoint.enabled` is true) — but the tunnel alone doesn't
route any app's traffic; something has to be configured to actually use
`localhost:1080`.

## ProxiFyre (transparent per-app/per-folder proxying)

Installed via `scripts/deploy-proxifyre.ps1`; toggled via
`scripts/vm-start-app-proxy.ps1` / `vm-stop-app-proxy.ps1` (or the "Start/Stop
App Proxy" desktop shortcuts). Currently covers Rivhit (`C:\Rivhit\`, whole
folder so helper processes with different exe names are included) plus
`chrome.exe` and `msedge.exe` (all windows/profiles of each browser).
The deploy script also recreates the desktop shortcuts through
`scripts/deploy-vm-shortcuts.ps1`.

Critical gotchas:
- **Service name is `ProxiFyreService`, not `ProxiFyre`.**
- **Requires Windows Firewall allow rules for `ProxiFyre.exe`** (inbound +
  outbound) or matched traffic silently hangs/times out with zero visible
  error anywhere. `deploy-proxifyre.ps1` adds these automatically — don't
  skip this if reinstalling manually.
- Service is deliberately `StartType=Manual` and left stopped after
  install/deploy — app-level proxying here is opt-in by design, unlike the
  tunnel which auto-starts.
- Matches by process name/path, not parent→child relationship — a
  same-named process is covered automatically, a differently-named child
  process needs its own `appNames` entry (or a path-based folder match).

## Quick diagnostic recipes

Check tunnel running on the PC:
```powershell
Get-Process ssh -ErrorAction SilentlyContinue | ForEach-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine }
```

Check ProxiFyre service + firewall rules on the VM:
```powershell
az vm run-command invoke -g VM-RG-ISRAEL -n DesktopVM --command-id RunPowerShellScript --scripts "Get-Service ProxiFyreService; Get-NetFirewallRule -DisplayName 'ProxiFyre*' | Select DisplayName,Enabled" --query "value[0].message" -o tsv
```

Verify proxied egress IP from the VM (through the tunnel):
```powershell
az vm run-command invoke -g VM-RG-ISRAEL -n DesktopVM --command-id RunPowerShellScript --scripts "curl.exe -s --max-time 15 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org" --query "value[0].message" -o tsv
```

Detailed user-facing operations and recovery steps:
`internal/proxy-point-operations.md`.

Migration history and cleanup inventory:
`internal/israel-region-migration-record.md`.

Use `internal/README.md` to distinguish maintained runbooks from retired
cross-tenant/Germany migration artifacts. Never run `internal/copy-vm.ps1`
for the current VM.
