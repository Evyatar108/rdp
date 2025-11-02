# Auto-Update Script for VM RDP Scripts
# Performs git pull and checks for updates, installs Git if needed

$ErrorActionPreference = "Continue"

Write-Host " Auto-Update Script" -ForegroundColor Green
Write-Host "=====================" -ForegroundColor Green

# Load configuration
try {
    . (Join-Path $PSScriptRoot "config-loader.ps1")
    $config = Get-VMRdpConfig
    $AUTO_UPDATE_ENABLED = $config.autoUpdate.enabled
    $AUTO_INSTALL_GIT = $config.autoUpdate.git.autoInstall
    $GIT_INSTALL_PATHS = $config.autoUpdate.git.installPaths
    $verboseOutput = $config.logging.verboseOutput
} catch {
    # Fallback if config loading fails
    Write-Host " Could not load configuration, using defaults" -ForegroundColor Yellow
    $AUTO_UPDATE_ENABLED = $true
    $AUTO_INSTALL_GIT = $true
    $GIT_INSTALL_PATHS = @("C:\Program Files\Git\cmd", "C:\Program Files (x86)\Git\cmd")
    $verboseOutput = $true
}

if ($verboseOutput) {
    Write-Host " Auto-update settings:" -ForegroundColor Cyan
    Write-Host "   Update enabled: $AUTO_UPDATE_ENABLED" -ForegroundColor Gray
    Write-Host "   Auto-install Git: $AUTO_INSTALL_GIT" -ForegroundColor Gray
    Write-Host ""
}

# Function to check if Git is available
function Test-GitAvailable {
    try {
        $gitVersion = git --version 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

# Function to install Git using winget
function Install-Git {
    if (-not $AUTO_INSTALL_GIT) {
        Write-Host " Git not found and auto-install is disabled" -ForegroundColor Yellow
        Write-Host "   Please install Git manually from https://git-scm.com/" -ForegroundColor Gray
        return $false
    }
    
    Write-Host " Git not found. Installing Git using winget..." -ForegroundColor Yellow
    
    try {
        # Check if winget is available
        $wingetVersion = winget --version 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host " winget is not available. Please install Git manually from https://git-scm.com/" -ForegroundColor Red
            return $false
        }
        
        Write-Host " Installing Git..." -ForegroundColor Cyan
        $installResult = winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host " Git installed successfully!" -ForegroundColor Green
            
            # Add Git to the current session PATH using configured paths
            Write-Host " Adding Git to current session PATH..." -ForegroundColor Cyan
            $gitFound = $false
            
            foreach ($gitPath in $GIT_INSTALL_PATHS) {
                if (Test-Path $gitPath) {
                    $env:Path += ";" + $gitPath
                    Write-Host "Git path added to current session: $gitPath" -ForegroundColor Green
                    $gitFound = $true
                    break
                }
            }
            
            if (-not $gitFound) {
                Write-Host " Git installation path not found in configured locations:" -ForegroundColor Yellow
                foreach ($path in $GIT_INSTALL_PATHS) {
                    Write-Host "   $path" -ForegroundColor Gray
                }
            }
            
            # Wait a moment for the installation to complete
            Start-Sleep -Seconds 3
            
            # Test if Git is now available
            if (Test-GitAvailable) {
                Write-Host " Git is now available and ready to use!" -ForegroundColor Green
                return $true
            } else {
                Write-Host " Git installed but not immediately available" -ForegroundColor Yellow
                Write-Host "   You may need to restart PowerShell for full functionality" -ForegroundColor Gray
                return $false
            }
        } else {
            Write-Host " Git installation failed. Output: $installResult" -ForegroundColor Red
            Write-Host "   Please install Git manually from https://git-scm.com/" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host " Error during Git installation: $_" -ForegroundColor Red
        Write-Host "   Please install Git manually from https://git-scm.com/" -ForegroundColor Yellow
        return $false
    }
}

# Auto-update check
if ($AUTO_UPDATE_ENABLED) {
    Write-Host " Checking for script updates..." -ForegroundColor Yellow
    
    # Check if Git is available, install if needed
    if (-not (Test-GitAvailable)) {
        $gitInstalled = Install-Git
        if (-not $gitInstalled) {
            Write-Host " Skipping auto-update due to Git unavailability" -ForegroundColor Yellow
            Write-Host "   Continuing with current scripts..." -ForegroundColor Gray
            return $false
        }
    } else {
        if ($verboseOutput) {
            Write-Host " Git is available" -ForegroundColor Green
        }
    }
    
    # Get script directory (go up one level from scripts folder)
    $scriptDirectory = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $currentLocation = Get-Location
    
    try {
        # Check if we're in a git repository
        Set-Location $scriptDirectory
        $isGitRepo = git rev-parse --is-inside-work-tree 2>$null
        
        if ($isGitRepo -eq "true") {
            # Get current commit hash before pull
            $beforeHash = git rev-parse HEAD 2>$null
            
            # Perform git pull
            Write-Host " Pulling latest updates..." -ForegroundColor Cyan
            $pullResult = git pull --force 2>&1
            $pullExitCode = $LASTEXITCODE
            
            # Get commit hash after pull
            $afterHash = git rev-parse HEAD 2>$null
            
            # Check if any changes were pulled
            if ($beforeHash -ne $afterHash) {
                Write-Host " Scripts updated successfully!" -ForegroundColor Green
                if ($verboseOutput) {
                    Write-Host " Changes pulled from repository" -ForegroundColor Gray
                }
                return $true  # Scripts were updated
            } elseif ($pullExitCode -eq 0) {
                Write-Host " Scripts are already up to date" -ForegroundColor Green
                return $false  # No updates needed
            } else {
                Write-Host " Git pull encountered issues but continuing..." -ForegroundColor Yellow
                if ($verboseOutput) {
                    Write-Host "   Output: $pullResult" -ForegroundColor Gray
                }
                return $false  # Treat as no updates
            }
        } else {
            Write-Host " Not a git repository - skipping update check" -ForegroundColor Gray
            return $false  # No git repo, no updates
        }
    } catch {
        Write-Host " Auto-update check failed: $_" -ForegroundColor Yellow
        Write-Host "   Continuing with current scripts..." -ForegroundColor Gray
        return $false  # Error, treat as no updates
    } finally {
        Set-Location $currentLocation
    }
} else {
    Write-Host "Auto-update disabled - using current scripts" -ForegroundColor Gray
    return $false  # Updates disabled
}