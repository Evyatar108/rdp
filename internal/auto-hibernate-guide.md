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
