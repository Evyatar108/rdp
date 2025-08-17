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
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

function Get-LastInputTime {
    # Get last input time using Windows API
    try {
        $signature = '[DllImport("user32.dll")]public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);public struct LASTINPUTINFO{public uint cbSize;public uint dwTime;}'
        $type = Add-Type -MemberDefinition $signature -Name Win32Utils -Namespace GetLastInputTime -PassThru
        $lastInputInfo = New-Object GetLastInputTime.Win32Utils+LASTINPUTINFO
        $lastInputInfo.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($lastInputInfo)
        
        if ($type::GetLastInputInfo([ref]$lastInputInfo)) {
            $uptime = [Environment]::TickCount
            $idleTime = $uptime - $lastInputInfo.dwTime
            return [math]::Round($idleTime / 1000) # Return idle time in seconds
        }
    } catch {
        Write-Log "Warning: Could not get last input time, using fallback method"
        return 0
    }
    return 0
}

function Test-UserActivity {
    # Check for active RDP sessions
    try {
        $rdpSessions = quser 2>$null | Where-Object { $_ -match "Active|Disc" }
        if ($rdpSessions) {
            foreach ($session in $rdpSessions) {
                if ($session -match "Active") {
                    return $true  # Active RDP session found
                }
            }
        }
    } catch {
        Write-Log "Warning: Could not check RDP sessions"
    }
    
    # Check for running user processes (browsers, office apps, etc.)
    $userProcesses = @("chrome", "firefox", "edge", "winword", "excel", "powerpnt", "notepad", "code", "devenv")
    foreach ($process in $userProcesses) {
        if (Get-Process -Name $process -ErrorAction SilentlyContinue) {
            return $true  # User process is running
        }
    }
    
    return $false
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
Write-Log "🔍 VM Internal Hibernation Monitor Started"
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
        $idleSeconds = Get-LastInputTime
        $hasUserActivity = Test-UserActivity
        
        if ($hasUserActivity -or $idleSeconds -lt $inactivityThresholdSeconds) {
            if ($consecutiveInactiveChecks -gt 0) {
                Write-Log "User activity detected, resetting inactivity counter"
                $consecutiveInactiveChecks = 0
            }
        } else {
            $consecutiveInactiveChecks++
            $idleMinutes = [math]::Round($idleSeconds / 60, 1)
            Write-Log "No activity detected for $idleMinutes minutes (check $consecutiveInactiveChecks/$requiredInactiveChecks)"
            
            if ($consecutiveInactiveChecks -ge $requiredInactiveChecks) {
                Write-Log "Inactivity threshold reached, hibernating VM..."
                
                if (Invoke-VMHibernation) {
                    Write-Log "VM hibernation initiated successfully"
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
    Write-Log "VM Internal Hibernation Monitor stopped"
}