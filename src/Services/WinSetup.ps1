# WinSetup.ps1 - Interface to winSetup scripts and functions

$script:UpdateRunJob       = $null
$script:UpdateRunStartTime = $null

# Queued per-package update state
$script:UpdatePackageQueue   = @()
$script:UpdatePackageIndex   = -1
$script:UpdatePackageResults = @{}
$script:IsQueuedUpdate       = $false

# ---------------------------------------------------------------------------
# Path and status helpers
# ---------------------------------------------------------------------------

function Test-WinSetupPath {
    <#
    .SYNOPSIS
        Validates that the configured winSetup path exists and contains
        the expected Setup-DevEnvironment.ps1 script.
    .OUTPUTS
        [bool] True if the path is valid.
    #>
    $path = $env:WINSETUP
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    if (-not (Test-Path $path)) { return $false }

    $setupScript = Join-Path $path 'Setup-DevEnvironment.ps1'
    return (Test-Path $setupScript)
}

function Get-WinSetupStatus {
    <#
    .SYNOPSIS
        Returns a status string for the winSetup connection.
    .OUTPUTS
        [hashtable] @{ Status = 'Ok'|'Error'; Message = string }
    #>
    if (Test-WinSetupPath) {
        return @{ Status = 'Ok'; Message = 'OK' }
    }

    if ([string]::IsNullOrWhiteSpace($env:WINSETUP)) {
        return @{ Status = 'Error'; Message = 'WINSETUP not set' }
    }

    return @{ Status = 'Error'; Message = 'Path invalid' }
}

function Get-PythonVersion {
    <#
    .SYNOPSIS
        Gets the active Python version from pyenv, falling back to python --version.
    .OUTPUTS
        [string] Python version string (e.g. "3.14.0") or "N/A".
    #>
    try {
        $output = & pyenv version 2>$null
        if ($LASTEXITCODE -eq 0 -and $output) {
            return ($output -split '\s')[0]
        }
    }
    catch {}

    try {
        $output = & python --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $output) {
            return ($output -replace 'Python\s*', '').Trim()
        }
    }
    catch {}

    return 'N/A'
}

# ---------------------------------------------------------------------------
# Profile health
# ---------------------------------------------------------------------------

function Get-ProfileHealthStatus {
    <#
    .SYNOPSIS
        Checks profile health by looking for winSetup's Test-ProfileHealth function.
    .DESCRIPTION
        Attempts to call Test-ProfileHealth if it is available in the current session.
        Returns a degraded status if winSetup is not configured or the function is
        not loaded.
    .OUTPUTS
        [hashtable] @{ Status = 'Ok'|'Warn'|'Error'; Message = string }
    #>
    if (-not (Test-WinSetupPath)) {
        return @{ Status = 'Warn'; Message = 'winSetup not configured' }
    }

    try {
        if (Get-Command 'Test-ProfileHealth' -ErrorAction SilentlyContinue) {
            $result = Test-ProfileHealth 2>$null
            if ($result) {
                return @{ Status = 'Ok'; Message = 'Healthy' }
            }
            return @{ Status = 'Warn'; Message = 'Issues detected' }
        }
        return @{ Status = 'Warn'; Message = 'Run profile check' }
    }
    catch {
        return @{ Status = 'Error'; Message = 'Check failed' }
    }
}

function Get-DevEnvironmentInfo {
    <#
    .SYNOPSIS
        Retrieves dev environment information from winSetup.
    .DESCRIPTION
        Attempts to call Show-DevEnvironment if available. Returns placeholder
        data when winSetup functions are not loaded.
    .OUTPUTS
        [hashtable] @{ Status = 'Ok'|'Unavailable'; Data = object|$null }
    #>
    try {
        if (Get-Command 'Show-DevEnvironment' -ErrorAction SilentlyContinue) {
            $info = Show-DevEnvironment 2>$null
            return @{ Status = 'Ok'; Data = $info }
        }
    }
    catch {}

    return @{ Status = 'Unavailable'; Data = $null }
}

# ---------------------------------------------------------------------------
# Update execution
# ---------------------------------------------------------------------------

function Show-ElevationWarning {
    <#
    .SYNOPSIS
        Shows a modal warning dialog about missing Administrator privileges.
    .OUTPUTS
        [bool] True if the user chose to continue, false if cancelled.
    #>
    $script:_ElevWarningResult = $false

    $continueBtn = [Terminal.Gui.Button]::new("_Continue anyway")
    $cancelBtn   = [Terminal.Gui.Button]::new("Ca_ncel")

    $dialog = [Terminal.Gui.Dialog]::new(
        "Not running as Administrator",
        56, 11,
        [Terminal.Gui.Button[]]@($continueBtn, $cancelBtn)
    )

    $warn = [Terminal.Gui.Label]::new(
        " Chocolatey updates require elevation.`n" +
        " Without it, choco packages will be skipped."
    )
    $warn.X = 1; $warn.Y = 1
    $warn.Width = [Terminal.Gui.Dim]::Fill(1)
    $warn.Height = 3
    $dialog.Add($warn)

    $continueBtn.add_Clicked({
        $script:_ElevWarningResult = $true
        [Terminal.Gui.Application]::RequestStop()
    })
    $cancelBtn.add_Clicked({
        [Terminal.Gui.Application]::RequestStop()
    })

    [Terminal.Gui.Application]::Run($dialog)
    return $script:_ElevWarningResult
}

function Invoke-WinSetupUpdate {
    <#
    .SYNOPSIS
        Starts Update-DevEnvironment.ps1 from winSetup as a background job.
    .DESCRIPTION
        1. Checks elevation and shows a warning dialog if not elevated.
        2. Validates the winSetup path and script existence.
        3. Starts the update script in a background job.
        Returns immediately; output is polled by the 500 ms timer.
    .OUTPUTS
        [bool] True if the job was started, false if cancelled or missing.
    #>

    # Already running?
    if ($script:UpdateRunJob) { return $false }

    # Elevation check
    if (-not (Test-IsElevated)) {
        if (-not (Show-ElevationWarning)) { return $false }
    }

    # Validate path
    if (-not (Test-WinSetupPath)) { return $false }
    $updateScript = Join-Path $env:WINSETUP 'Update-DevEnvironment.ps1'
    if (-not (Test-Path $updateScript)) { return $false }

    # Launch the job
    $script:UpdateRunJob       = Start-Job -ScriptBlock {
        param($scriptPath)
        & $scriptPath 2>&1
    } -ArgumentList $updateScript
    $script:UpdateRunStartTime = Get-Date
    $script:IsQueuedUpdate     = $false

    return $true
}

# ---------------------------------------------------------------------------
# Per-package update queue
# ---------------------------------------------------------------------------

function Start-PackageUpdateQueue {
    <#
    .SYNOPSIS
        Initialises a queue of per-tool updates and starts the first one.
    .DESCRIPTION
        Each package is updated individually via Update-DevEnvironment.ps1
        -Package <name>.  The 500 ms timer advances the queue as each job
        completes.
    .PARAMETER Packages
        Array of hashtables, each with at least a 'name' key.
    .OUTPUTS
        [bool] True if the queue was started.
    #>
    param([array]$Packages)

    if ($script:UpdateRunJob) { return $false }
    if ($Packages.Count -eq 0) { return $false }

    # Elevation check once for the whole batch
    if (-not (Test-IsElevated)) {
        if (-not (Show-ElevationWarning)) { return $false }
    }
    if (-not (Test-WinSetupPath)) { return $false }

    $script:UpdatePackageQueue   = $Packages
    $script:UpdatePackageIndex   = 0
    $script:UpdatePackageResults = @{}
    $script:IsQueuedUpdate       = $true

    Start-NextPackageUpdate
    return $true
}

function Start-NextPackageUpdate {
    <#
    .SYNOPSIS
        Starts the background job for the current queue item.
    #>
    $pkg = $script:UpdatePackageQueue[$script:UpdatePackageIndex]

    $sep = [string]::new([char]0x2500, 42)
    Append-UpdateOutput -Text $sep
    Append-UpdateOutput -Text " Updating $($pkg.name)..."
    Append-UpdateOutput -Text $sep

    $updateScript = Join-Path $env:WINSETUP 'Update-DevEnvironment.ps1'
    $script:UpdateRunJob       = Start-Job -ScriptBlock {
        param($scriptPath, $packageName)
        & $scriptPath -Package $packageName 2>&1
    } -ArgumentList $updateScript, $pkg.name
    $script:UpdateRunStartTime = Get-Date
}

function Complete-PackageUpdateQueue {
    <#
    .SYNOPSIS
        Called when all queued per-package updates are finished.
    .DESCRIPTION
        Shows a summary line and triggers a cache refresh.
    #>
    $succeeded = @($script:UpdatePackageResults.Values | Where-Object { $_ -eq 'success' }).Count
    $failed    = @($script:UpdatePackageResults.Values | Where-Object { $_ -eq 'failed' }).Count

    Append-UpdateOutput -Text ''
    Append-UpdateOutput -Text "--- $succeeded updated, $failed failed ---"

    $script:UpdatePackageQueue   = @()
    $script:UpdatePackageIndex   = -1
    $script:UpdatePackageResults = @{}
    $script:IsQueuedUpdate       = $false

    Start-BackgroundUpdateCheck -Force
}
