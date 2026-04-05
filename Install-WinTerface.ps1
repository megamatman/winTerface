<#
.SYNOPSIS
    Installs winTerface and configures it for use.

.DESCRIPTION
    Sets up winTerface by:
    1. Checking dependencies (PowerShell 7+, ConsoleGuiTools module)
    2. Installing or upgrading ConsoleGuiTools if needed
    3. Creating the config directory (~\.winTerface\)
    4. Setting WINTERFACE User environment variable
    5. Adding a profile alias so 'wti' launches winTerface from any terminal

    Safe to run multiple times -- each step checks current state first.

.PARAMETER ProfilePath
    Path to the PowerShell profile to update. Defaults to $PROFILE.

.PARAMETER NoAlias
    Skip adding the 'wti' alias to the profile.

.EXAMPLE
    .\Install-WinTerface.ps1

.EXAMPLE
    .\Install-WinTerface.ps1 -NoAlias
#>

[CmdletBinding()]
param(
    [string]$ProfilePath = $PROFILE,
    [switch]$NoAlias
)

$ErrorActionPreference = 'Stop'

function Confirm-WinSetupCompatibility {
    <#
    .SYNOPSIS
        Verifies that a compatible winSetup installation is present.
    .DESCRIPTION
        Checks that $env:WINSETUP is set and points to a valid winSetup
        directory containing Uninstall-Tool.ps1 and a Setup-DevEnvironment.ps1
        that supports the -InstallTool parameter. Exits with error if any
        check fails.
    #>
    Write-Host "`n[1/6] winSetup compatibility" -ForegroundColor Cyan

    if (-not $env:WINSETUP -or -not (Test-Path $env:WINSETUP)) {
        Write-Host "  winSetup not found." -ForegroundColor Red
        Write-Host "  Install winSetup first: https://github.com/megamatman/winSetup" -ForegroundColor Yellow
        Write-Host "  Then run Setup-DevEnvironment.ps1 to set `$env:WINSETUP." -ForegroundColor Yellow
        exit 1
    }

    $uninstallScript = Join-Path $env:WINSETUP 'Uninstall-Tool.ps1'
    if (-not (Test-Path $uninstallScript)) {
        Write-Host "  Uninstall-Tool.ps1 not found in winSetup." -ForegroundColor Red
        Write-Host "  Update winSetup to the latest version." -ForegroundColor Yellow
        exit 1
    }

    $setupScript = Join-Path $env:WINSETUP 'Setup-DevEnvironment.ps1'
    $content = Get-Content $setupScript -Raw
    if ($content -notmatch '\-InstallTool') {
        Write-Host "  Setup-DevEnvironment.ps1 does not support -InstallTool." -ForegroundColor Red
        Write-Host "  Update winSetup to the latest version." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "  winSetup: $env:WINSETUP -- OK" -ForegroundColor Green
}

Write-Host "`n=== Installing winTerface ===" -ForegroundColor Cyan
Confirm-WinSetupCompatibility

# ---------------------------------------------------------------------------
# Step 2 -- PowerShell version check (fatal)
# ---------------------------------------------------------------------------

Write-Host "`n[2/6] PowerShell version" -ForegroundColor Cyan
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "  winTerface requires PowerShell 7+." -ForegroundColor Red
    Write-Host "  Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host "  Download: https://aka.ms/powershell" -ForegroundColor Yellow
    exit 1
}
Write-Host "  PowerShell $($PSVersionTable.PSVersion) -- OK" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 3 -- ConsoleGuiTools module (fatal if install fails)
# ---------------------------------------------------------------------------

Write-Host "`n[3/6] Microsoft.PowerShell.ConsoleGuiTools" -ForegroundColor Cyan
$module = Get-Module -ListAvailable -Name Microsoft.PowerShell.ConsoleGuiTools |
    Sort-Object Version -Descending | Select-Object -First 1
if ($module) {
    # Check for updates
    try {
        $latest = Find-Module Microsoft.PowerShell.ConsoleGuiTools -ErrorAction SilentlyContinue
        if ($latest -and $latest.Version -gt $module.Version) {
            Write-Host "  Upgrading v$($module.Version) -> v$($latest.Version)..." -ForegroundColor Yellow
            Update-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser -Force
            Write-Host "  Upgraded" -ForegroundColor Green
        } else {
            Write-Host "  Installed: v$($module.Version) (up to date)" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "  Installed: v$($module.Version) (upgrade check failed)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  Installing ConsoleGuiTools..." -ForegroundColor Yellow
    try {
        Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser -Force
        Write-Host "  Installed" -ForegroundColor Green
    }
    catch {
        Write-Host "  FAILED to install ConsoleGuiTools: $_" -ForegroundColor Red
        Write-Host "  Run manually: Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser" -ForegroundColor Yellow
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Step 4 -- Config directory (non-fatal)
# ---------------------------------------------------------------------------

Write-Host "`n[4/6] Config directory" -ForegroundColor Cyan
$configDir = Join-Path $env:USERPROFILE '.winTerface'
if (-not (Test-Path $configDir)) {
    try {
        New-Item -ItemType Directory -Path $configDir | Out-Null
        Write-Host "  Created: $configDir" -ForegroundColor Green
    }
    catch {
        Write-Host "  WARNING: Could not create $configDir`: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Already exists: $configDir" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Step 5 -- WINTERFACE environment variable (non-fatal)
# ---------------------------------------------------------------------------

Write-Host "`n[5/6] WINTERFACE environment variable" -ForegroundColor Cyan
try {
    [System.Environment]::SetEnvironmentVariable('WINTERFACE', $PSScriptRoot, 'User')
    $env:WINTERFACE = $PSScriptRoot
    Write-Host "  WINTERFACE set to: $PSScriptRoot" -ForegroundColor Green
}
catch {
    Write-Host "  WARNING: Could not set WINTERFACE env var: $_" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 6 -- Profile alias (non-fatal)
# 'wti' avoids conflict with Windows Terminal's 'wt' binary on PATH.
# ---------------------------------------------------------------------------

Write-Host "`n[6/6] Profile alias" -ForegroundColor Cyan
if ($NoAlias) {
    Write-Host "  Skipped (-NoAlias)" -ForegroundColor DarkGray
} else {
    $aliasBlock = @"

# winTerface launcher
function Invoke-WinTerface {
    & "`$env:WINTERFACE\winTerface.ps1" @args
}
Set-Alias wti Invoke-WinTerface
"@

    $profileDir = Split-Path $ProfilePath -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    try {
        if (Test-Path $ProfilePath) {
            $content = Get-Content $ProfilePath -Raw
            if ($content -match 'Invoke-WinTerface') {
                Write-Host "  Alias already present in profile" -ForegroundColor DarkGray
            } else {
                $backup = "$ProfilePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item $ProfilePath $backup
                # Prune old backups, keep most recent 3
                $base = Split-Path $ProfilePath -Leaf
                Get-ChildItem (Split-Path $ProfilePath) -Filter "$base.bak-*" |
                    Sort-Object Name -Descending | Select-Object -Skip 3 |
                    Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Host "  Backed up: $backup" -ForegroundColor DarkGray
                Add-Content -Path $ProfilePath -Value $aliasBlock -Encoding UTF8
                Write-Host "  Added 'wti' alias to profile" -ForegroundColor Green
            }
        } else {
            Set-Content -Path $ProfilePath -Value $aliasBlock -Encoding UTF8
            Write-Host "  Created profile with 'wti' alias" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  WARNING: Could not update profile: $_" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

Write-Host "`n=== winTerface installed ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Run 'wti' from any terminal to launch winTerface."
Write-Host "  Restart your terminal for the alias to take effect."
Write-Host ""
Write-Host "  Config directory: $configDir" -ForegroundColor DarkGray
Write-Host "  WINTERFACE:       $PSScriptRoot" -ForegroundColor DarkGray
Write-Host ""
