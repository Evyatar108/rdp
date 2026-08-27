# VM Internal Hibernation Monitor
# Runs inside the VM to hibernate after detecting user inactivity
# This provides backup hibernation when external RDP monitoring isn't available

param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$InactivityTimeoutMinutes,
    [ValidateRange(1, 2147483647)]
    [int]$CheckIntervalSeconds = 60,
    [string]$LogFile = "C:\VMHibernation\hibernation-monitor.log",
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,
    [Parameter(Mandatory = $true)]
    [string]$VMName,
    [string]$AzureConfigPath = "C:\VMHibernation\.azure-managed-identity"
)

$ErrorActionPreference = 'Continue'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogFile -Value "[$timestamp] $Message" -Encoding UTF8
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

            $idleMilliseconds = ($currentTicks - $lastInputTicks) % 4294967296
            
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
    $previousAzureConfigPath = $env:AZURE_CONFIG_DIR

    try {
        New-Item -Path $AzureConfigPath -ItemType Directory -Force | Out-Null
        $env:AZURE_CONFIG_DIR = $AzureConfigPath

        $loginOutput = az login --identity --allow-no-subscriptions --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: Managed identity login failed. Output: $($loginOutput -join ' ')"
            return $false
        }

        $accountOutput = az account set --subscription $SubscriptionId 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: Could not select subscription $SubscriptionId. Output: $($accountOutput -join ' ')"
            return $false
        }

        Write-Host "Hibernating VM using Azure CLI..." -ForegroundColor Green
        Write-Host "Running: az vm deallocate -g $ResourceGroup -n $VMName --hibernate true" -ForegroundColor Gray
        
        $hibernateOutput = az vm deallocate -g $ResourceGroup -n $VMName --hibernate true 2>&1
        $hibernateExitCode = $LASTEXITCODE
        
        if ($hibernateExitCode -eq 0) {
            Write-Host "VM hibernated successfully!" -ForegroundColor Green
            Write-Log "Azure accepted the hibernation request."
            return $true
        }
        else {
            Write-Host "Azure hibernation failed with exit code: $hibernateExitCode" -ForegroundColor Red
            Write-Host "Output: $hibernateOutput" -ForegroundColor Yellow
            Write-Log "ERROR: Azure hibernation failed with exit code $hibernateExitCode. Output: $($hibernateOutput -join ' ')"
            return $false
        }
    }
    catch {
        Write-Host "Error during hibernation: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "ERROR during hibernation: $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($null -eq $previousAzureConfigPath) {
            Remove-Item Env:\AZURE_CONFIG_DIR -ErrorAction SilentlyContinue
        }
        else {
            $env:AZURE_CONFIG_DIR = $previousAzureConfigPath
        }
    }
}
# Main monitoring loop
$inactivityThresholdSeconds = $InactivityTimeoutMinutes * 60
$lastStatusLog = [datetime]::MinValue

try {
    Write-Log "Monitor started for $ResourceGroup/$VMName with a $InactivityTimeoutMinutes minute timeout and a $CheckIntervalSeconds second check interval."

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

        if (((Get-Date) - $lastStatusLog).TotalMinutes -ge 5) {
            Write-Log "Idle for $idleSeconds seconds; threshold is $inactivityThresholdSeconds seconds."
            $lastStatusLog = Get-Date
        }

        if ($idleSeconds -ge $inactivityThresholdSeconds) {
            try { Write-Progress -Activity "VM Auto-Hibernation Monitor" -Completed -ErrorAction SilentlyContinue } catch {}
            Write-Host ""
            Write-Host "Idle threshold reached. Triggering hibernation..." -ForegroundColor Yellow
            Write-Log "Idle threshold reached. Requesting hibernation."
            
            $hibernationResult = Invoke-VMHibernation
            
            if ($hibernationResult) {
                Write-Host "Hibernation command sent successfully." -ForegroundColor Green
                Write-Host "Resetting countdown timer to prevent immediate re-hibernation." -ForegroundColor Cyan
                Write-Host "Monitor will continue with fresh idle time tracking..." -ForegroundColor Yellow
                
                # Reset the idle time tracking by waiting for user activity
                # This prevents immediate re-hibernation if the VM resumes quickly
                $resetWaitTime = 300
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
catch [System.Management.Automation.PipelineStoppedException] {
    Write-Log "Monitor stopped."
}
catch {
    Write-Log "FATAL: Monitor stopped unexpectedly: $($_.Exception.Message)"
    throw
}
finally {
    try { Write-Progress -Activity "VM Auto-Hibernation Monitor" -Completed -ErrorAction SilentlyContinue } catch {}
}
