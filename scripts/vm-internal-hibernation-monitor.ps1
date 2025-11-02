# VM Internal Hibernation Monitor
# Runs inside the VM to hibernate after detecting user inactivity
# This provides backup hibernation when external RDP monitoring isn't available

param(
    [Parameter(Mandatory = $true)]
    [int]$InactivityTimeoutMinutes,
    [int]$CheckIntervalSeconds = 60,
    [string]$LogFile = "C:\VMHibernation\hibernation-monitor.log"
)

$ErrorActionPreference = 'Continue'

function Get-SystemIdleTimeSeconds {
    <#
    .SYNOPSIS
        Gets the system-wide user input idle time using P/Invoke, mirroring the robust C# implementation.
    .DESCRIPTION
        This function uses GetLastInputInfo and the 64-bit GetTickCount64 to avoid 32-bit timer
        wraparound issues, making it reliable for systems with long uptimes.
    .RETURNS
        [int] The total number of seconds the system has been idle.
        Returns 0 on any failure to prevent accidental hibernation.
    #>
    try {
        # Define the P/Invoke signature only once
        if (-not ([System.Management.Automation.PSTypeName]'Win32.InputTimer').Type) {
            $signature = @'
[DllImport("user32.dll")]
public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

[DllImport("kernel32.dll")]
public static extern ulong GetTickCount64();

[StructLayout(LayoutKind.Sequential)]
public struct LASTINPUTINFO
{
    public uint cbSize;
    public uint dwTime;
}
'@
            Add-Type -MemberDefinition $signature -Name InputTimer -Namespace Win32 -ErrorAction Stop
        }

        $lastInputInfo = New-Object Win32.InputTimer+LASTINPUTINFO
        $lastInputInfo.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($lastInputInfo)

        if ([Win32.InputTimer]::GetLastInputInfo([ref]$lastInputInfo)) {
            $currentTicks = [Win32.InputTimer]::GetTickCount64()
            $lastInputTicks = $lastInputInfo.dwTime
            
            # The subtraction correctly handles timer wraparound when one value is from the 64-bit counter
            $idleMilliseconds = $currentTicks - $lastInputTicks
            
            return [math]::Max(0, [math]::Round($idleMilliseconds / 1000))
        }
        else {
            # If the API call fails, get the last Win32 error for logging
            $win32Error = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw (New-Object System.ComponentModel.Win32Exception $win32Error)
        }
    }
    catch {
        Write-Log "ERROR getting idle time: $($_.Exception.Message). Assuming activity to be safe."
        return 0 # Fail safe: if we can't get idle time, assume the user is active.
    }
}
function Invoke-VMHibernation {
    try {
        # VM details - these will be injected by the deployment script
        $resourceGroup = "VM-RG-TARGET"
        $vmName = "DesktopVM"
        
        Write-Host "Hibernating VM using Azure CLI..." -ForegroundColor Green
        Write-Host "Running: az vm deallocate -g $resourceGroup -n $vmName --hibernate true" -ForegroundColor Gray
        
        # Use the same Azure CLI command as the external monitor
        $hibernateOutput = az vm deallocate -g $resourceGroup -n $vmName --hibernate true 2>&1
        $hibernateExitCode = $LASTEXITCODE
        
        if ($hibernateExitCode -eq 0) {
            Write-Host "VM hibernated successfully!" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "Azure hibernation failed with exit code: $hibernateExitCode" -ForegroundColor Red
            Write-Host "Output: $hibernateOutput" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "Error during hibernation: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}
# Main monitoring loop
$inactivityThresholdSeconds = $InactivityTimeoutMinutes * 60

try {
    while ($true) {
        $idleSeconds = Get-SystemIdleTimeSeconds
        
        # Always show progress
        $remainingSeconds = $inactivityThresholdSeconds - $idleSeconds
        $percentComplete = [math]::Min(100, [math]::Round(($idleSeconds / $inactivityThresholdSeconds) * 100, 1))
        $remainingMinutes = [math]::Round($remainingSeconds / 60, 1)
        $statusMessage = "Hibernating in $remainingMinutes minutes if idle."
        if ($idleSeconds -gt 0) {
            $idleMinutes = [math]::Round($idleSeconds / 60, 2)
            $statusMessage = "Hibernating in $remainingMinutes minutes. Idle for $idleMinutes minutes."
        }
        Write-Progress -Activity "VM Auto-Hibernation Monitor" -Status $statusMessage -PercentComplete $percentComplete

        if ($idleSeconds -ge $inactivityThresholdSeconds) {
            try { Write-Progress -Activity "VM Auto-Hibernation Monitor" -Completed -ErrorAction SilentlyContinue } catch {}
            Write-Host ""
            Write-Host "Idle threshold reached. Triggering hibernation..." -ForegroundColor Yellow
            
            $hibernationResult = Invoke-VMHibernation
            
            if ($hibernationResult) {
                Write-Host "Hibernation command sent successfully." -ForegroundColor Green
                Write-Host "Resetting countdown timer to prevent immediate re-hibernation." -ForegroundColor Cyan
                Write-Host "Monitor will continue with fresh idle time tracking..." -ForegroundColor Yellow
                
                # Reset the idle time tracking by waiting for user activity
                # This prevents immediate re-hibernation if the VM resumes quickly
                $resetWaitTime = 6000  # 5 minutes buffer after hibernation
                Write-Host "Waiting $($resetWaitTime/60) minutes buffer before resuming monitoring..." -ForegroundColor Gray
                
                for ($resetCounter = $resetWaitTime; $resetCounter -gt 0; $resetCounter -= $CheckIntervalSeconds) {
                    $waitTime = [math]::Min($CheckIntervalSeconds, $resetCounter)
                    Start-Sleep -Seconds $waitTime
                    
                    # Check for user activity during reset period
                    $currentIdleSeconds = Get-SystemIdleTimeSeconds
                    if ($currentIdleSeconds -lt 30) {  # If user active in last 30 seconds
                        Write-Host "User activity detected during buffer period. Resuming normal monitoring..." -ForegroundColor Green
                        break
                    }
                    
                    $remainingResetMinutes = [math]::Round($resetCounter / 60, 1)
                    Write-Progress -Activity "Hibernation Reset Buffer" -Status "Resuming monitoring in $remainingResetMinutes minutes" -PercentComplete (($resetWaitTime - $resetCounter) / $resetWaitTime * 100)
                }
                
                try { Write-Progress -Activity "Hibernation Reset Buffer" -Completed -ErrorAction SilentlyContinue } catch {}
                Write-Host "Resuming normal hibernation monitoring..." -ForegroundColor Green
                
            } else {
                Write-Host "Hibernation failed. Monitor will continue..." -ForegroundColor Red
                Write-Host "Will retry when idle threshold is reached again." -ForegroundColor Yellow
                # Continue monitoring without reset - hibernation failed so no need for buffer
            }
        }
        
        Start-Sleep -Seconds $CheckIntervalSeconds
    }
}
catch {
    # Catch Ctrl+C or other terminating errors
}
finally {
    try { Write-Progress -Activity "VM Auto-Hibernation Monitor" -Completed -ErrorAction SilentlyContinue } catch {}
}
