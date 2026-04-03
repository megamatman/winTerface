<#
.SYNOPSIS
    Installs winTerface and configures it for use.

.DESCRIPTION
    Sets up winTerface by:
    1. Checking dependencies (PowerShell 7+, ConsoleGuiTools module)
    2. Installing ConsoleGuiTools if missing
    3. Creating the config directory (~\.winTerface\)
    4. Setting WINTERFACE User environment variable
    5. Adding a profile alias so 'wt' launches winTerface from any terminal

.PARAMETER ProfilePath
    Path to the PowerShell profile to update. Defaults to $PROFILE.

.PARAMETER NoAlias
    Skip adding the 'wt' alias to the profile.

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

Write-Host "`n=== Installing winTerface ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Step 1 -- PowerShell version check
# ---------------------------------------------------------------------------

Write-Host "`n[1/5] PowerShell version" -ForegroundColor Cyan
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "  winTerface requires PowerShell 7+." -ForegroundColor Red
    Write-Host "  Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host "  Download: https://aka.ms/powershell" -ForegroundColor Yellow
    exit 1
}
Write-Host "  PowerShell $($PSVersionTable.PSVersion) -- OK" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 2 -- ConsoleGuiTools module
# ---------------------------------------------------------------------------

Write-Host "`n[2/5] Microsoft.PowerShell.ConsoleGuiTools" -ForegroundColor Cyan
$module = Get-Module -ListAvailable -Name Microsoft.PowerShell.ConsoleGuiTools
if ($module) {
    Write-Host "  Already installed: v$($module[0].Version)" -ForegroundColor DarkGray
} else {
    Write-Host "  Installing ConsoleGuiTools..." -ForegroundColor Yellow
    Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser -Force
    Write-Host "  Installed" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 3 -- Config directory
# ---------------------------------------------------------------------------

Write-Host "`n[3/5] Config directory" -ForegroundColor Cyan
$configDir = Join-Path $env:USERPROFILE '.winTerface'
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir | Out-Null
    Write-Host "  Created: $configDir" -ForegroundColor Green
} else {
    Write-Host "  Already exists: $configDir" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Step 4 -- WINTERFACE environment variable
# ---------------------------------------------------------------------------

Write-Host "`n[4/5] WINTERFACE environment variable" -ForegroundColor Cyan
[System.Environment]::SetEnvironmentVariable('WINTERFACE', $PSScriptRoot, 'User')
$env:WINTERFACE = $PSScriptRoot
Write-Host "  WINTERFACE set to: $PSScriptRoot" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 5 -- Profile alias
# ---------------------------------------------------------------------------

Write-Host "`n[5/5] Profile alias" -ForegroundColor Cyan
if ($NoAlias) {
    Write-Host "  Skipped (-NoAlias)" -ForegroundColor DarkGray
} else {
    $aliasBlock = @"

# winTerface launcher
function Invoke-WinTerface {
    & "`$env:WINTERFACE\winTerface.ps1" @args
}
Set-Alias wt Invoke-WinTerface
"@

    # Check if alias already exists in profile
    $profileDir = Split-Path $ProfilePath -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    if (Test-Path $ProfilePath) {
        $content = Get-Content $ProfilePath -Raw
        if ($content -match 'Invoke-WinTerface') {
            Write-Host "  Alias already present in profile" -ForegroundColor DarkGray
        } else {
            # Back up before editing
            $backup = "$ProfilePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item $ProfilePath $backup
            Write-Host "  Backed up: $backup" -ForegroundColor DarkGray

            Add-Content -Path $ProfilePath -Value $aliasBlock -Encoding UTF8
            Write-Host "  Added 'wt' alias to profile" -ForegroundColor Green
        }
    } else {
        Set-Content -Path $ProfilePath -Value $aliasBlock -Encoding UTF8
        Write-Host "  Created profile with 'wt' alias" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

Write-Host "`n=== winTerface installed ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Run 'wt' from any terminal to launch winTerface."
Write-Host "  Restart your terminal for the alias to take effect."
Write-Host ""
Write-Host "  Config directory: $configDir" -ForegroundColor DarkGray
Write-Host "  WINTERFACE:       $PSScriptRoot" -ForegroundColor DarkGray
Write-Host ""
