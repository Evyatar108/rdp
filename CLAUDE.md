# CLAUDE.md — Notes for AI agents & contributors working on this repo

This repo automates connecting to, hibernating, and (more recently) proxying
network traffic for a single Azure VM (`DesktopVM`) used for RDP work. This
file captures non-obvious gotchas discovered while building/debugging the
system, so future sessions (human or AI) don't have to rediscover them the
hard way.

> A Copilot CLI agent skill covering the same operational knowledge in
> quick-reference form lives at
> [`.github/skills/azure-vm-rdp-ops/SKILL.md`](.github/skills/azure-vm-rdp-ops/SKILL.md) —
> keep both in sync when things change here.

## Environment identifiers (current, as of this writing)

- **VM:** `DesktopVM`, resource group `VM-RG-ISRAEL`, region **Israel Central**
  (moved here from `germanywestcentral`/`VM-RG-TARGET` via cross-region
  snapshot copy — that Germany environment was deleted on 2026-09-24; only
  safety snapshots remain, see "Germany environment" below).
- **Subscription/tenant:** see `config.json` → `azure.target` (do not hardcode
  elsewhere; always read from config).
- **VM login user:** `shabi108` (local admin on the VM).
- **VM repo clone:** `C:\repos\rdp` — kept in sync via `git pull`, see gotcha
  below about running git as SYSTEM.
- **GitHub repo:** `Evyatar108/rdp` (public-facing/official repo).

## Pushing to GitHub: two-account dance

This machine's **default** `gh`/git identity is a different account than the
one that owns the repo. To push:
```powershell
gh auth switch -u Evyatar108
git push origin master
gh auth switch -u evmitran_microsoft   # or whatever the default account is here
```
Forgetting the switch-back leaves `gh`/git pointed at the wrong account for
later unrelated work — always switch back immediately after pushing.

## Running commands on the VM

We use `az vm run-command invoke -g VM-RG-ISRAEL -n DesktopVM --command-id
RunPowerShellScript` extensively instead of interactive RDP, since it can be
scripted from here. Several sharp edges:

- **Prefer `--scripts "@path\to\file.ps1"` over inline `--scripts "..."`.**
  Complex inline strings (nested quotes, `$` variables, embedded `{}`) are
  frequently mis-parsed or silently produce empty output. Write the script to
  a local temp file and pass it by `@`-reference instead.
- **PowerShell string interpolation happens LOCALLY first.** If you build the
  `--scripts` value as a double-quoted PowerShell string containing
  `$env:SOMETHING`, your **local** shell expands it before it's ever sent to
  the VM. Use single-quoted strings or (better) the `@file` pattern above.
- **Output is truncated to ~4KB, keeping the END, not the start.** Verbose
  output (e.g. `Format-Table -Wrap`, big `Get-EventLog` dumps) silently loses
  its beginning. Keep scripts' `Write-Output` calls terse and targeted, or
  redirect to a VM-local file and read it back in a follow-up small command
  instead of trying to return everything through stdout.
- **`az vm run-command` runs as SYSTEM in a non-interactive Session 0.**
  - `git` commands on `C:\repos\rdp` need `git -c safe.directory=C:/repos/rdp
    -C C:\repos\rdp ...` or they fail with an "unsafe repository" ownership
    error.
  - **GUI apps (Chrome, Edge, Rivhit) are unreliable when launched this way.**
    They may exit immediately, or crash with odd exit codes (we saw Edge
    exit 1002 due to `SystemProfile\...\Crashpad` path errors — a Session-0/
    SYSTEM-profile artifact, not a real bug). Don't treat a GUI app's failure
    to run via `run-command` as proof of anything — validate the underlying
    mechanism with a CLI tool (`curl.exe`) or headless mode instead, and
    treat true interactive-session testing as something only the actual user
    can do over RDP.
  - Only **one** `run-command` can run at a time — issuing a second one while
    the first is still executing server-side returns `(Conflict) Run command
    extension execution is in progress`, even if you've locally stopped
    waiting on the first one. Wait it out (or poll) rather than retrying
    immediately.

## VM Desktop is OneDrive-redirected

Desktop shortcuts **must** be created in
`C:\Users\shabi108\OneDrive\Desktop`, **not** `C:\Users\shabi108\Desktop` —
the latter is the wrong, unused folder on this VM. A shortcut placed there
silently doesn't show up. Always verify with `Test-Path` before writing.
Use `scripts/deploy-vm-shortcuts.ps1` instead of one-off shortcut scripts so
the VM desktop state remains reproducible from the repo.

## VM-side automatic hibernation

The VM-side `VMHibernationMonitor` scheduled task is the primary automatic
hibernation mechanism; `hibernation.external.enabled` is deliberately `false`.
The task runs as `shabi108` in the interactive session because
`GetLastInputInfo` is session-specific.

Do not use a human Azure CLI login for unattended hibernation. Refresh tokens
expire and leave the VM running. The monitor logs into Azure with DesktopVM's
system-assigned managed identity using the isolated CLI state directory
`C:\VMHibernation\.azure-managed-identity`. Its custom role,
`DesktopVM Self Hibernate Operator`, is assigned only on this VM and permits
only:

- `Microsoft.Compute/virtualMachines/read`
- `Microsoft.Compute/virtualMachines/deallocate/action`

The deployed monitor is
`C:\VMHibernation\vm-internal-hibernation-monitor.ps1`; its log is
`C:\VMHibernation\hibernation-monitor.log`. Confirm a completed run with
`az vm get-instance-view`; a real hibernation reports
`HibernationState/Hibernated`, not only `PowerState/deallocated`.

## Cost alerting

`scripts/deploy-cost-alert.ps1` maintains a monthly Azure Consumption budget
that emails when subscription spend crosses `costAlert.monthlyAmountUsd` in
`config.json`. It registers both an **Actual** and a **Forecasted** alert; the
forecast one fires days earlier and is the one that actually prevents a
surprise bill.

Gotchas found while building it:

- **`az consumption budget create` cannot attach email notifications.** It has
  no `--contact-email` style parameter, so the script PUTs to the Consumption
  REST API (`Microsoft.Consumption/budgets`, api-version `2021-10-01`)
  instead. Do not "simplify" it back to the CLI command.
- **Inline JSON bodies get mangled by PowerShell quoting.** The script writes
  the payload to a temp file and passes `--body "@file"`. Same class of
  problem as the `--scripts "@file"` rule for `az vm run-command` above.
- **Do not force a global CLI context switch for a single-subscription
  script.** `Ensure-AzureCLIAuthenticated` runs `az login --tenant` whenever
  the active context is a different tenant, which opens a browser and
  repoints this machine's default subscription — disruptive when the operator
  is working in another tenant. This script instead probes
  `az account show --subscription <id>` first and only signs in when the
  subscription is genuinely unreachable, passing `--subscription` explicitly
  on every call.
- **A new budget reports `0` spend** until Azure's first evaluation cycle
  (up to ~24h). That is not a deployment failure.
- Azure requires a monthly budget to start on the **first day of a month**.
  The script preserves the existing start date on re-runs so the budget's
  history is not reset.

## Known pending items

- `VM-RG-TARGET` retains `desktopvm-os-final-20260924` and
  `desktopvm-data0-final-20260924`. These hold the only copy of anything
  written on the Germany VM between 2026-07-30 and 2026-08-27. Confirm that
  window is not needed before deleting them.

## PowerShell `Start-Process -ArgumentList` quoting

Any argument containing embedded spaces (e.g. Chrome's
`--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE 127.0.0.1`) gets mis-split
into multiple argv entries unless wrapped in escaped double quotes inside the
array element:
```powershell
"--host-resolver-rules=`"MAP * ~NOTFOUND , EXCLUDE 127.0.0.1`""
```

## ssh-keygen with an empty passphrase

`ssh-keygen -N '""'` in PowerShell creates a literal `""` string as the
passphrase (not an empty one). Use `cmd /c ssh-keygen -t ed25519 -f
"$keyPath" -N "" -C ... -q` to actually get no passphrase.

## Proxy Point (reverse SSH SOCKS tunnel)

Architecture: the **PC** (not the VM) runs `ssh -R 1080 user@vm-ip`, which
makes the VM's `localhost:1080` a SOCKS5 proxy whose traffic egresses from
the PC's own network. `scripts/connect-vm-rdp.ps1` auto-starts this tunnel
(if `proxyPoint.enabled` in `config.json`) before every RDP connection — but
starting the tunnel does **not**, by itself, make anything use it (see next
section).

Multi-PC ownership is tokenized and **latest connection wins**. Claim/release
operations use a VM-side exclusive file lock under
`C:\ProgramData\RdpProxyPoint`; the current token is stored in `owner.json`.
The old tunnel wrapper actively polls ownership while SSH is running, so it
exits after takeover instead of reclaiming the port. RDP-close release is
token-checked, preventing an old monitor from killing a newer tunnel. There is
no automatic fallback to an older still-open RDP session after the newest
owner disconnects; that PC must rerun `vm-rdp.ps1`.

## ProxiFyre (per-app / per-folder transparent proxying)

Used to route Rivhit + Chrome + Edge traffic through the Proxy Point tunnel
without needing browser-specific proxy flags. Non-obvious pitfalls:

- **The installed Windows service is named `ProxiFyreService`, NOT
  `ProxiFyre`** (the exe's name). `Get-Service -Name ProxiFyre` finds
  nothing; use `ProxiFyreService`.
- **`ProxiFyre.exe install` defaults the service to `StartType=Automatic`.**
  We deliberately force the Windows service to `Manual` (`sc.exe config
  ProxiFyreService start= demand`) so Windows boot never starts it by itself.
  Runtime behavior is selected by `proxyPoint.appProxyMode`: `automatic`
  starts it once the owning tunnel is ready and stops it on token-matched
  release; `manual` leaves it under `vm-start-app-proxy.ps1` /
  `vm-stop-app-proxy.ps1` control.
- **Windows Firewall silently breaks it if you don't add allow rules for
  `ProxiFyre.exe`.** Symptom: the driver correctly intercepts a matched
  process's traffic, but the redirected connection just hangs/times out
  forever with **no error anywhere** (not in ProxiFyre's own logs, not in
  the app). This cost significant debugging time — confirmed root cause via
  a plain `curl.exe` test with/without the firewall rule. `deploy-proxifyre.ps1`
  now adds these rules unconditionally; if you ever reinstall ProxiFyre
  manually, don't forget them.
- **Matching is by process name/path, not parent→child relationship.**
  Multiple instances of the *same* exe name are automatically covered, but a
  child process spawned under a *different* exe name is not — hence Rivhit
  is matched by its whole install folder (`C:\Rivhit\`, a path-form pattern)
  rather than just `rivhit125.exe`, so any helper it spawns (e.g.
  `icredit.exe`, `BatchEMV.exe`) is covered too.
- **Chrome/Edge matching is by exe name, so it's all-or-nothing per browser**
  — turning the toggle on proxies *every* window/profile of that browser,
  not just a dedicated one. (This is a deliberate choice made when this was
  built — see chat history if this needs revisiting.)
- New processes (or new tabs/reconnects in already-open ones) after the
  service starts are what get captured; already-established connections
  made before the driver attached will not retroactively be proxied.

User-facing operating/recovery instructions live in
`internal/proxy-point-operations.md`. The completed regional cutover and the
2026-09-24 Germany deletion are recorded in
`internal/israel-region-migration-record.md`.

The `internal` folder also contains historical migration artifacts. Read
`internal/README.md` before using anything there; in particular,
`internal/copy-vm.ps1` is the retired cross-tenant/Germany flow and must not
be used for the current VM.

## Germany environment: deleted 2026-09-24

The old `VM-RG-TARGET` environment is gone. The VM, its disks, its networking,
and the leftover unmanaged-VHD storage account were deleted on 2026-09-24
with explicit user approval.

The resource group still exists and holds only two full, independent
safety snapshots of the Germany disks as they stood at deletion:

- `desktopvm-os-final-20260924`
- `desktopvm-data0-final-20260924`

These matter because the Germany VM did not stay deallocated after the
cutover. It was restarted on 2026-07-30 and ran until 2026-08-27, so its
disks had drifted past the Jul 29 migration snapshots. Anything written in
that window exists only in these two snapshots. Do not delete them without
confirming that window is not needed.

The Israel migration snapshots `os-snap-il` and `data0-snap-il` were also
deleted on 2026-09-24. They were rollback copies only — the live disks were
made with `createOption: Copy` and are fully independent, so removing the
snapshots did not affect the running VM. `VM-RG-ISRAEL` now holds just the
live environment.

Cost note: with the Germany VM deleted the standing spend there drops by
about $11.59/month, plus $3.06/month from the Israel snapshots. Both VMs
having run 24/7 is what produced the $380.46 August usage (a $230 bill after
the $150 Visual Studio credit).
