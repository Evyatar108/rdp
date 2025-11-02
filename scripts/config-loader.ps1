# Configuration Loader for VM RDP Scripts
# Loads and validates configuration from config.json

function Get-VMRdpConfig {
    param(
        [string]$ConfigPath = $null
    )
    
    # Determine config file path
    if (-not $ConfigPath) {
        # Get the root directory (go up one level from scripts folder)
        $scriptDirectory = Split-Path -Parent $PSScriptRoot
        if ($scriptDirectory -and (Test-Path $scriptDirectory)) {
            $rootDirectory = $scriptDirectory
        }
        else {
            # Fallback: use the directory where the calling script is located
            $callingScript = $MyInvocation.PSCommandPath
            if ($callingScript) {
                $rootDirectory = Split-Path -Parent $callingScript
            }
            else {
                $rootDirectory = Get-Location
            }
        }
        $ConfigPath = Join-Path $rootDirectory "config.json"
    }
    
    # Check if config file exists
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "❌ Configuration file not found at: $ConfigPath" -ForegroundColor Red
        Write-Host "💡 Please ensure config.json exists in the root directory" -ForegroundColor Yellow
        throw "Configuration file not found"
    }
    
    try {
        # Load and parse JSON configuration
        $configContent = Get-Content $ConfigPath -Raw -Encoding UTF8
        $config = $configContent | ConvertFrom-Json
        
        # Validate required configuration sections
        $requiredSections = @("azure", "hibernation", "autoUpdate")
        foreach ($section in $requiredSections) {
            if (-not $config.$section) {
                throw "Missing required configuration section: $section"
            }
        }
        
        # Validate Azure configuration
        if (-not $config.azure.target) {
            throw "Missing required configuration: azure.target"
        }
        
        $requiredAzureFields = @("tenantId", "subscriptionId", "resourceGroup", "vmName")
        foreach ($field in $requiredAzureFields) {
            if (-not $config.azure.target.$field) {
                throw "Missing required Azure configuration: azure.target.$field"
            }
        }
        
        # Set default values for optional fields
        if (-not $config.hibernation.timing) {
            $config.hibernation | Add-Member -Type NoteProperty -Name "timing" -Value @{}
        }
        if (-not $config.hibernation.timing.delayAfterRdpCloseSeconds) {
            $config.hibernation.timing | Add-Member -Type NoteProperty -Name "delayAfterRdpCloseSeconds" -Value 120
        }
        if (-not $config.hibernation.timing.progressUpdateIntervalSeconds) {
            $config.hibernation.timing | Add-Member -Type NoteProperty -Name "progressUpdateIntervalSeconds" -Value 1
        }
        if (-not $config.hibernation.timing.hibernationResumeWaitSeconds) {
            $config.hibernation.timing | Add-Member -Type NoteProperty -Name "hibernationResumeWaitSeconds" -Value 30
        }
        
        if (-not (Get-Member -InputObject $config.hibernation -Name "showMonitorWindow" -MemberType Properties)) {
            $config.hibernation | Add-Member -Type NoteProperty -Name "showMonitorWindow" -Value $true
        }
        
        if (-not $config.autoUpdate.enabled) {
            $config.autoUpdate | Add-Member -Type NoteProperty -Name "enabled" -Value $true
        }
        
        if (-not $config.rdp) {
            $config | Add-Member -Type NoteProperty -Name "rdp" -Value @{}
        }
        if (-not $config.rdp.connection) {
            $config.rdp | Add-Member -Type NoteProperty -Name "connection" -Value @{}
        }
        
        if (-not $config.logging) {
            $config | Add-Member -Type NoteProperty -Name "logging" -Value @{}
        }
        if (-not $config.logging.verboseOutput) {
            $config.logging | Add-Member -Type NoteProperty -Name "verboseOutput" -Value $true
        }
        
        return $config
    }
    catch {
        Write-Host "❌ Error loading configuration: $_" -ForegroundColor Red
        Write-Host "💡 Please check that config.json is valid JSON format" -ForegroundColor Yellow
        throw "Configuration loading failed: $_"
    }
}

# Function is available after dot-sourcing this script
# No Export-ModuleMember needed for dot-sourced scripts