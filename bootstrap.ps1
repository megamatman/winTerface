<#
.SYNOPSIS
    One-line bootstrap for winTerface on a machine with winSetup installed.

.DESCRIPTION
    Handles PowerShell 7 verification, winSetup dependency check, git
    installation (via winget if needed), repository cloning, WINTERFACE
    environment variable setup, and invocation of Install-WinTerface.ps1.
    Runs without admin rights.

    Usage:
      irm "https://raw.githubusercontent.com/megamatman/winTerface/refs/tags/v1.2.0/bootstrap.ps1" | iex

    Or clone the repo first and run:
      .\bootstrap.ps1

.PARAMETER InstallPath
    Directory where winTerface should be cloned. Defaults to
    $env:USERPROFILE\winTerface.

.PARAMETER Launch
    Skip the interactive prompt and launch winTerface immediately
    after install. Pass $false to skip.

.EXAMPLE
    .\bootstrap.ps1

.EXAMPLE
    .\bootstrap.ps1 -InstallPath "D:\Tools\winTerface"

.EXAMPLE
    .\bootstrap.ps1 -Launch:$false
#>

[CmdletBinding()]
param(
    [string]$InstallPath,
    [Nullable[bool]]$Launch
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# Security notice (before any action)
# ============================================================================

Write-Host ""
Write-Host "=== winTerface Bootstrap ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This script will:" -ForegroundColor Yellow
Write-Host "    1. Verify winSetup is installed"
Write-Host "    2. Install git via winget if not already present"
Write-Host "    3. Clone https://github.com/megamatman/winTerface.git"
Write-Host "    4. Set the WINTERFACE environment variable"
Write-Host "    5. Run Install-WinTerface.ps1"
Write-Host ""
Write-Host "  Review the source before running:" -ForegroundColor Yellow
Write-Host "    https://github.com/megamatman/winTerface/blob/main/bootstrap.ps1"
Write-Host ""

$response = Read-Host "  Continue? [Y/n]"
if ($response -and $response -notin @('y', 'Y', 'yes', 'Yes', '')) {
    Write-Host "  Cancelled." -ForegroundColor DarkGray
    exit 0
}

# ============================================================================
# Step 1: PowerShell version check
# ============================================================================

Write-Host ""
Write-Host "[1/5] PowerShell version" -ForegroundColor Cyan

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "  winTerface requires PowerShell 7+." -ForegroundColor Red
    Write-Host "  Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host "  Download: https://aka.ms/powershell" -ForegroundColor Yellow
    exit 1
}

Write-Host "  PowerShell $($PSVersionTable.PSVersion) -- OK" -ForegroundColor Green

# ============================================================================
# Step 2: winSetup dependency check
# ============================================================================

Write-Host ""
Write-Host "[2/5] winSetup" -ForegroundColor Cyan

if (-not $env:WINSETUP -or -not (Test-Path $env:WINSETUP)) {
    Write-Host "  winSetup is not installed." -ForegroundColor Red
    Write-Host "  winTerface requires winSetup. Install it first:" -ForegroundColor Yellow
    Write-Host '    irm "https://raw.githubusercontent.com/megamatman/winSetup/refs/tags/v1.2.0/bootstrap.ps1" | iex' -ForegroundColor Yellow
    Write-Host "  Then re-run this script." -ForegroundColor Yellow
    exit 1
}

Write-Host "  winSetup: $env:WINSETUP -- OK" -ForegroundColor Green

# Dot-source Helpers.ps1 for Write-Step/Issue/Section output conventions
$helpersPath = Join-Path $env:WINSETUP 'Helpers.ps1'
if (Test-Path $helpersPath) {
    . $helpersPath
}

# ============================================================================
# Step 3: Git check and install
# ============================================================================

Write-Host ""
Write-Host "[3/5] Git" -ForegroundColor Cyan

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  git not found. Attempting install via winget..." -ForegroundColor Yellow

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "  winget is not available. Install git manually:" -ForegroundColor Red
        Write-Host "    https://git-scm.com/downloads/win" -ForegroundColor Yellow
        Write-Host "  Then re-run this script." -ForegroundColor Yellow
        exit 1
    }

    & winget install --id Git.Git --exact --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  winget install Git.Git failed (exit code $LASTEXITCODE)." -ForegroundColor Red
        Write-Host "  Install git manually: https://git-scm.com/downloads/win" -ForegroundColor Yellow
        exit 1
    }

    # Refresh PATH so git is discoverable
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User') +
                ';' +
                $env:PATH

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "  git installed but not on PATH. Restart your terminal and re-run." -ForegroundColor Red
        exit 1
    }

    Write-Host "  git installed" -ForegroundColor Green
} else {
    Write-Host "  git found -- OK" -ForegroundColor Green
}

# ============================================================================
# Step 4: Clone repository
# ============================================================================

Write-Host ""
Write-Host "[4/5] Clone winTerface" -ForegroundColor Cyan

# Check for existing installation
$existingPath = $null
if ($env:WINTERFACE -and (Test-Path $env:WINTERFACE)) {
    $existingPath = $env:WINTERFACE
} else {
    $candidates = @(
        (Join-Path $env:USERPROFILE 'winTerface')
        (Join-Path $env:USERPROFILE 'Documents\winTerface')
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'winTerface.ps1')) {
            $existingPath = $c
            break
        }
    }
}

if ($existingPath) {
    Write-Host "  winTerface already present at: $existingPath" -ForegroundColor DarkGray
    $clonePath = $existingPath
} else {
    # Determine install path
    $defaultPath = Join-Path $env:USERPROFILE 'winTerface'
    if ($InstallPath) {
        $clonePath = $InstallPath
    } else {
        $input = Read-Host "  Install location [$defaultPath]"
        $clonePath = if ($input) { $input } else { $defaultPath }
    }

    Write-Host "  Cloning to $clonePath..." -ForegroundColor Yellow
    & git clone https://github.com/megamatman/winTerface.git $clonePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  git clone failed (exit code $LASTEXITCODE)." -ForegroundColor Red
        Write-Host "  Check your network connection and try again." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "  Cloned successfully" -ForegroundColor Green
}

# ============================================================================
# Step 5: Set WINTERFACE, install, and launch
# ============================================================================

Write-Host ""
Write-Host "[5/5] Install and configure" -ForegroundColor Cyan

[System.Environment]::SetEnvironmentVariable('WINTERFACE', $clonePath, 'User')
$env:WINTERFACE = $clonePath
Write-Host "  WINTERFACE set to: $clonePath" -ForegroundColor Green

# Run Install-WinTerface.ps1
$installScript = Join-Path $clonePath 'Install-WinTerface.ps1'
if (-not (Test-Path $installScript)) {
    Write-Host "  Install-WinTerface.ps1 not found at $installScript" -ForegroundColor Red
    exit 1
}

Write-Host ""
& $installScript

Write-Host ""
Write-Host "=== winTerface is ready ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Repository:  $clonePath" -ForegroundColor DarkGray
Write-Host "  WINTERFACE:  $env:WINTERFACE" -ForegroundColor DarkGray
Write-Host ""

# Launch decision
if ($null -ne $Launch) {
    $doLaunch = $Launch
} else {
    $answer = Read-Host "  Launch winTerface now? [Y/n]"
    $doLaunch = (-not $answer) -or ($answer -in @('y', 'Y', 'yes', 'Yes'))
}

if ($doLaunch) {
    Write-Host ""
    & (Join-Path $clonePath 'winTerface.ps1')
} else {
    Write-Host "  To launch later, run 'wti' from any terminal." -ForegroundColor Yellow
    Write-Host ""
}
