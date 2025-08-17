# VM Internal Hibernation Monitor
# Runs inside the VM to hibernate after detecting user inactivity
# This provides backup hibernation when external RDP monitoring isn't available

param(
    [int]$InactivityTimeoutMinutes = 10,
    [int]$CheckIntervalSeconds = 60,
    [string]$LogFile = "C:\VMHibernation\hibernation-monitor.log"
)

$ErrorActionPreference = 'Continue'
# Ensure log directory exists
try {
    $logDir = Split-Path -Parent $LogFile
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
} catch { }

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage -ForegroundColor Cyan
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue -Encoding UTF8
}

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
        } else {
            # If the API call fails, get the last Win32 error for logging
            $win32Error = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw (New-Object System.ComponentModel.Win32Exception $win32Error)
        }
    } catch {
        Write-Log "ERROR getting idle time: $($_.Exception.Message). Assuming activity to be safe."
        return 0 # Fail safe: if we can't get idle time, assume the user is active.
    }
}

function Invoke-VMHibernation {
    Write-Log "Initiating VM hibernation due to inactivity..."
    
    try {
        # First try the direct PowerShell method
        Write-Log "Attempting hibernation via PowerShell..."
        Stop-Computer -Force -Hibernate -ErrorAction Stop
        
    } catch {
        Write-Log "PowerShell hibernation failed, trying alternative method..."
        
        try {
            # Try using shutdown command
            & shutdown /h /f
            Write-Log "Hibernation command executed successfully"
            
        } catch {
            Write-Log "ERROR: Failed to hibernate VM - $_"
            
            # As a last resort, try using rundll32
            try {
                & rundll32.exe powrprof.dll,SetSuspendState 1,1,0
                Write-Log "Alternative hibernation method attempted"
            } catch {
                Write-Log "ERROR: All hibernation methods failed"
                return $false
            }
        }
    }
    
    return $true
}

# Main monitoring loop
Write-Log "VM Internal Hibernation Monitor Started"
Write-Log "   Inactivity timeout: $InactivityTimeoutMinutes minutes"
Write-Log "   Check interval: $CheckIntervalSeconds seconds"
Write-Log "   Log file: $LogFile"
Write-Log ""

$inactivityThresholdSeconds = $InactivityTimeoutMinutes * 60
$consecutiveInactiveChecks = 0
$requiredInactiveChecks = [math]::Max(1, [math]::Floor($inactivityThresholdSeconds / $CheckIntervalSeconds))

Write-Log "Monitoring for inactivity... (Press Ctrl+C to stop)"

try {
    while ($true) {
        $idleSeconds = Get-SystemIdleTimeSeconds
        $idleMinutes = [math]::Round($idleSeconds / 60, 2)
        Write-Log "System idle for $idleMinutes minutes."

        if ($idleSeconds -lt $inactivityThresholdSeconds) {
            # Activity detected, reset counter
            if ($consecutiveInactiveChecks -gt 0) {
                Write-Log "Inactivity counter reset."
                $consecutiveInactiveChecks = 0
            }
            # Clear progress bar when activity is detected
            try { Write-Progress -Activity "VM Hibernation Monitor" -Completed -ErrorAction SilentlyContinue } catch {}
        } else {
            # No activity, increment counter and update progress
            $consecutiveInactiveChecks++
            Write-Log "Inactivity threshold met. Hibernation check $consecutiveInactiveChecks/$requiredInactiveChecks."
            
            # Show countdown progress bar
            $remainingSeconds = $inactivityThresholdSeconds - $idleSeconds
            $percentComplete = [math]::Min(100, [math]::Round(($idleSeconds / $inactivityThresholdSeconds) * 100, 1))
            $remainingMinutes = [math]::Round($remainingSeconds / 60, 1)
            Write-Progress -Activity "VM Hibernation Monitor" -Status "Hibernating in $remainingMinutes minutes ($remainingSeconds seconds remaining)" -PercentComplete $percentComplete
            
            if ($consecutiveInactiveChecks -ge $requiredInactiveChecks) {
                Write-Log "Hibernation threshold reached. Initiating hibernation..."
                try { Write-Progress -Activity "VM Hibernation Monitor" -Completed -ErrorAction SilentlyContinue } catch {}
                
                if (Invoke-VMHibernation) {
                    Write-Log "VM hibernation initiated successfully."
                    break
                } else {
                    Write-Log "Failed to hibernate VM, continuing monitoring..."
                    $consecutiveInactiveChecks = 0  # Reset to avoid repeated failed attempts
                }
            }
        }
        
        Start-Sleep -Seconds $CheckIntervalSeconds
    }
    
} catch {
    Write-Log "Monitoring interrupted: $_"
} finally {
    Write-Progress -Activity "VM Hibernation Monitor" -Completed
    Write-Log "VM Internal Hibernation Monitor stopped"
}