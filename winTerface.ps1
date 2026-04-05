#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    winTerface - Terminal UI for managing a Windows 11 dev environment.
.DESCRIPTION
    Entry point. Checks dependencies, runs the first-run setup wizard if
    needed, dot-sources all modules, and launches the TUI.
.EXAMPLE
    ./winTerface.ps1
#>

param()

$ErrorActionPreference = 'Stop'
$script:WinTerfaceVersion = '1.0.0'
$script:WinTerfaceRoot    = $PSScriptRoot

# ───────────────────────────────────────────────────────────────────────────
# Dot-source all modules (order matters: helpers first, then core, services,
# screens, and finally the app which ties everything together)
# ───────────────────────────────────────────────────────────────────────────

# Helpers
. (Join-Path $PSScriptRoot 'src' 'Helpers' 'Elevation.ps1')
. (Join-Path $PSScriptRoot 'src' 'Helpers' 'UI.ps1')

# Core
. (Join-Path $PSScriptRoot 'src' 'Config.ps1')
. (Join-Path $PSScriptRoot 'src' 'Commands.ps1')
. (Join-Path $PSScriptRoot 'src' 'Navigation.ps1')

# Services
. (Join-Path $PSScriptRoot 'src' 'Services' 'WinSetup.ps1')
. (Join-Path $PSScriptRoot 'src' 'Services' 'PackageManager.ps1')
. (Join-Path $PSScriptRoot 'src' 'Services' 'UpdateCache.ps1')
. (Join-Path $PSScriptRoot 'src' 'Services' 'ToolWriter.ps1')

# Screens
. (Join-Path $PSScriptRoot 'src' 'Screens' 'Home.ps1')
. (Join-Path $PSScriptRoot 'src' 'Screens' 'Tools.ps1')
. (Join-Path $PSScriptRoot 'src' 'Screens' 'AddTool.ps1')
. (Join-Path $PSScriptRoot 'src' 'Screens' 'Updates.ps1')
. (Join-Path $PSScriptRoot 'src' 'Screens' 'Profile.ps1')
. (Join-Path $PSScriptRoot 'src' 'Screens' 'Config.ps1')
. (Join-Path $PSScriptRoot 'src' 'Screens' 'About.ps1')

# Application
. (Join-Path $PSScriptRoot 'src' 'App.ps1')

# ───────────────────────────────────────────────────────────────────────────
# Dependency check
# ───────────────────────────────────────────────────────────────────────────

function Test-Dependencies {
    <#
    .SYNOPSIS
        Verifies that all required modules are installed.
    .OUTPUTS
        [bool] $true if all dependencies are met, $false otherwise.
    #>
    $module = Get-Module Microsoft.PowerShell.ConsoleGuiTools -ListAvailable
    if (-not $module) {
        Write-Host ""
        Write-Host "  winTerface requires the Microsoft.PowerShell.ConsoleGuiTools module." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Install it by running:" -ForegroundColor White
        Write-Host "    Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Then re-run winTerface." -ForegroundColor White
        Write-Host ""
        return $false
    }
    return $true
}

# ───────────────────────────────────────────────────────────────────────────
# First-run wizard (console-based, runs before the TUI starts)
# ───────────────────────────────────────────────────────────────────────────

function Start-FirstRunWizard {
    <#
    .SYNOPSIS
        Prompts the user to configure the winSetup path on first run.
    .DESCRIPTION
        Asks for the winSetup directory, validates that Setup-DevEnvironment.ps1
        exists inside it, saves config.json, and sets $env:WINSETUP.
    .OUTPUTS
        [bool] $true if setup completed, $false if the user cancelled.
    #>
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |     Welcome to winTerface v$script:WinTerfaceVersion          |" -ForegroundColor Cyan
    Write-Host "  |     First-run setup                      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  winTerface needs to know where winSetup is located." -ForegroundColor White
    Write-Host "  (leave blank to cancel)" -ForegroundColor DarkGray
    Write-Host ""

    $maxAttempts = 3
    for ($i = 0; $i -lt $maxAttempts; $i++) {
        $path = Read-Host "  Enter the path to winSetup"
        $path = $path.Trim().Trim('"').Trim("'")

        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-Host "  Setup cancelled." -ForegroundColor Yellow
            return $false
        }

        if (-not (Test-Path $path)) {
            Write-Host "  Path does not exist: $path" -ForegroundColor Red
            continue
        }

        $setupScript = Join-Path $path 'Setup-DevEnvironment.ps1'
        if (-not (Test-Path $setupScript)) {
            Write-Host "  Setup-DevEnvironment.ps1 not found in: $path" -ForegroundColor Red
            Write-Host "  Make sure this is the root of your winSetup directory." -ForegroundColor Yellow
            continue
        }

        # Valid -- persist
        $config = @{
            winSetupPath             = $path
            lastUpdateCheck          = $null
            updateCheckIntervalHours = 24
        }

        try {
            Set-WinTerfaceConfig -Config $config
            $env:WINSETUP = $path
            Write-Host ""
            Write-Host "  winSetup path saved: $path" -ForegroundColor Green
            Write-Host "  Config file: $(Get-WinTerfaceConfigPath)" -ForegroundColor DarkGray
            Write-Host ""
            return $true
        }
        catch {
            Write-Host "  Failed to save configuration: $_" -ForegroundColor Red
            return $false
        }
    }

    Write-Host "  Too many attempts. Check the path and try again." -ForegroundColor Red
    return $false
}

# ───────────────────────────────────────────────────────────────────────────
# Main
# ───────────────────────────────────────────────────────────────────────────

# 1. Dependencies
if (-not (Test-Dependencies)) { exit 1 }

# 2. Resolve winSetup path
$existingConfig = Get-WinTerfaceConfig

if (-not $env:WINSETUP -and -not $existingConfig) {
    # First run -- need the wizard
    if (-not (Start-FirstRunWizard)) { exit 0 }
}
elseif ($existingConfig -and -not $env:WINSETUP) {
    # Config exists but env var is missing -- restore it for this session
    $env:WINSETUP = $existingConfig.winSetupPath
}

# 3. Launch the TUI
Start-WinTerface
