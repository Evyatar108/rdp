# Reset Git History Script
# This will delete all commit history and create a fresh initial commit
# WARNING: This is destructive and cannot be undone!

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Red
Write-Host " Git History Reset Tool" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host ""
Write-Host "WARNING: This will DELETE ALL commit history!" -ForegroundColor Yellow
Write-Host "The current state of your files will be preserved as a single initial commit." -ForegroundColor Yellow
Write-Host ""

# Check if we're in a git repository
if (-not (Test-Path ".git")) {
    Write-Error "Not a git repository. Please run this from the root of your git repository."
    exit 1
}

# Get current branch name
$currentBranch = git branch --show-current
Write-Host "Current branch: $currentBranch" -ForegroundColor Cyan
Write-Host ""

# Ask for confirmation
Write-Host "Are you sure you want to reset all git history? (yes/no)" -ForegroundColor Yellow
$confirmation = Read-Host "Type 'yes' to continue"

if ($confirmation -ne "yes") {
    Write-Host "Operation cancelled." -ForegroundColor Gray
    exit 0
}

Write-Host ""
Write-Host "Step 1: Creating backup of current branch..." -ForegroundColor Cyan
git branch backup-before-reset

Write-Host "Step 2: Removing .git directory..." -ForegroundColor Cyan
Remove-Item -Path ".git" -Recurse -Force

Write-Host "Step 3: Initializing new git repository..." -ForegroundColor Cyan
git init

Write-Host "Step 4: Adding all files to staging..." -ForegroundColor Cyan
git add -A

Write-Host "Step 5: Creating initial commit..." -ForegroundColor Cyan
git commit -m "Initial commit"

Write-Host "Step 6: Renaming branch to $currentBranch..." -ForegroundColor Cyan
git branch -M $currentBranch

Write-Host ""
Write-Host "Local git history has been reset successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "To push this to GitHub and replace remote history:" -ForegroundColor Yellow
Write-Host "  git remote add origin <your-repo-url>" -ForegroundColor Gray
Write-Host "  git push -u --force origin $currentBranch" -ForegroundColor Gray
Write-Host ""
Write-Host "NOTE: If you already have a remote configured, you can push directly:" -ForegroundColor Yellow
Write-Host "  git push --force origin $currentBranch" -ForegroundColor Gray
Write-Host ""
Write-Host "WARNING: Force push will overwrite the remote repository!" -ForegroundColor Red