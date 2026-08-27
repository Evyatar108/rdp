# Auto-Hibernation Operations

The current hibernation behavior is controlled entirely by `config.json`.
Do not edit constants inside the PowerShell scripts.

## Current modes

### Internal VM monitor

`hibernation.internal.enabled` controls the monitor that runs inside the VM
and hibernates it after the configured period without an active RDP session.

Current defaults:

```json
{
  "hibernation": {
    "internal": {
      "enabled": true,
      "inactivityTimeoutMinutes": 60,
      "checkIntervalSeconds": 60
    }
  }
}
```

Deploy or repair it from an elevated PowerShell session on the VM:

```powershell
Set-Location C:\repos\rdp
.\scripts\deploy-internal-monitor.ps1
```

The VM uses its system-assigned managed identity to request its own
hibernation. That identity needs only VM read and deallocate permissions on
this VM. The monitor stores managed-identity Azure CLI state separately under
`C:\VMHibernation\.azure-managed-identity`; it does not depend on a human
Azure CLI refresh token.

### External RDP-process monitor

`hibernation.external.enabled` controls the PC-side monitor launched by
`scripts/connect-vm-rdp.ps1`. When enabled, it waits for the local RDP client
process to close, then waits `hibernation.timing.delayAfterRdpCloseSeconds`
before hibernating the VM.

It is currently disabled in `config.json`; the internal monitor is the active
hibernation mechanism.

## Daily workflow

Run:

```powershell
.\vm-rdp.ps1
```

The launcher updates the repo, starts/resumes the VM, starts Proxy Point when
enabled, and opens RDP. Hibernation behavior then follows the two mode flags
above.

## Configuration

```json
{
  "hibernation": {
    "timing": {
      "delayAfterRdpCloseSeconds": 300,
      "progressUpdateIntervalSeconds": 1,
      "hibernationResumeWaitSeconds": 60
    },
    "showMonitorWindow": true,
    "external": {
      "enabled": false,
      "inactivityTimeoutMinutes": 60
    },
    "internal": {
      "enabled": true,
      "inactivityTimeoutMinutes": 60,
      "checkIntervalSeconds": 60
    }
  }
}
```

## Design decision

⟦def decision:vm-side-hibernation-primary⟧ Keep the VM-side inactivity
monitor as the primary automatic hibernation mechanism.

Rationale: hibernation must continue to work when RDP is opened outside this
repository's launcher or when the connecting PC exits before the timeout.

Rejected alternative: the PC-side RDP-process monitor remains disabled because
it depends on the launcher process and the connecting PC staying available.

Reversal condition: enable the external monitor only if the VM-side monitor
cannot be made reliable or the desired trigger changes from guest inactivity
to closing one specific local RDP window.

Set only one mechanism as authoritative unless you intentionally want both.
If both are enabled, either monitor may hibernate the VM first.

## Troubleshooting

- Verify current settings in `config.json`.
- Check the internal scheduled task:
  `Get-ScheduledTask -TaskName VMHibernationMonitor`.
- Review `C:\VMHibernation\hibernation-monitor.log`.
- Set `hibernation.showMonitorWindow` to `true` when debugging the external
  monitor.
- Confirm the VM and OS disk support hibernation with
  `internal\enable-hibernation.ps1`.
