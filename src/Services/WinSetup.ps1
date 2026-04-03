# WinSetup.ps1 - Interface to winSetup scripts and functions

$script:UpdateRunJob       = $null
$script:UpdateRunStartTime = $null

# Queued per-package update state
$script:UpdatePackageQueue   = @()
$script:UpdatePackageIndex   = -1
$script:UpdatePackageResults = @{}
$script:IsQueuedUpdate       = $false

# Profile management state
$script:ProfileRedeployJob    = $null
$script:ProfileRedeployOutput = ''

# Expected profile sections -- mirrors Test-ProfileHealth in winSetup
$script:ExpectedProfileSections = [ordered]@{
    'SSH Agent'           = 'ssh-agent'
    'Chocolatey'          = 'chocolateyProfile'
    'winSetup'            = 'WINSETUP'
    'Python Tools'        = 'Setup-PythonTools'
    'fzf'                 = 'FZF_DEFAULT_COMMAND'
    'PSFzf'               = 'Import-Module PSFzf'
    'PSReadLine'          = 'PredictionSource'
    'zoxide'              = 'zoxide init'
    'zoxide OMP fix'      = '__zoxide_omp_prompt'
    'pyenv-win'           = 'PYENV'
    'lazygit alias'       = 'Set-Alias lg lazygit'
    'delta'               = 'DELTA_FEATURES'
    'bat alias'           = 'Set-Alias cat bat'
    'Ctrl+F binding'      = 'Ctrl\+f'
    'Git aliases'         = 'function gs'
    'gl alias fix'        = 'Remove-Alias.*gl'
    'gc alias fix'        = 'Remove-Alias.*gc'
    'Oh My Posh'          = 'oh-my-posh init'
    'Test-ProfileHealth'  = 'function Test-ProfileHealth'
    'Invoke-DevSetup'     = 'function Invoke-DevSetup'
    'Invoke-DevUpdate'    = 'function Invoke-DevUpdate'
    'Show-DevEnvironment' = 'function Show-DevEnvironment'
}

# Human-readable suggestion for each missing section
$script:ProfileSuggestions = @{
    'SSH Agent'           = 'SSH agent auto-start block is missing. It loads your key on terminal open.'
    'Chocolatey'          = 'Chocolatey profile import is missing. Tab completion for choco will not work.'
    'winSetup'            = 'winSetup environment variable block is missing. Other profile sections depend on it.'
    'Python Tools'        = 'Python tools auto-setup function is missing. Periodic tool checks will not run.'
    'fzf'                 = 'fzf environment configuration is missing. Fzf defaults will be used instead.'
    'PSFzf'               = 'PSFzf module import is missing. Ctrl+T and Ctrl+R fuzzy bindings will not work.'
    'PSReadLine'          = 'PSReadLine predictive config is missing. History-based autosuggestions will not appear.'
    'zoxide'              = 'zoxide initialization is missing. The z command will not be available.'
    'zoxide OMP fix'      = 'zoxide prompt hook is missing. Without it zoxide will not record directory visits.'
    'pyenv-win'           = 'pyenv-win PATH setup is missing. pyenv commands will not be found.'
    'lazygit alias'       = 'lazygit alias is missing. The lg shorthand will not work.'
    'delta'               = 'delta environment variables are missing. Git diff will not use side-by-side layout.'
    'bat alias'           = 'bat alias is missing. The cat command will use the default system tool.'
    'Ctrl+F binding'      = 'Ctrl+F file finder is missing. The fzf file picker shortcut will not work.'
    'Git aliases'         = 'Git alias functions are missing. gs, ga, gc, gp, gl shortcuts will not work.'
    'gl alias fix'        = "gl alias removal is missing. PowerShell's built-in gl will shadow the git log function."
    'gc alias fix'        = "gc alias removal is missing. PowerShell's built-in gc will shadow the git commit function."
    'Oh My Posh'          = 'Oh My Posh init line is missing. Your prompt will fall back to the default PS prompt.'
    'Test-ProfileHealth'  = 'Test-ProfileHealth function is missing. Profile health checks will not be available.'
    'Invoke-DevSetup'     = 'Invoke-DevSetup function is missing. The dev setup convenience command will not work.'
    'Invoke-DevUpdate'    = 'Invoke-DevUpdate function is missing. The dev update convenience command will not work.'
    'Show-DevEnvironment' = 'Show-DevEnvironment function is missing. Environment status display will not work.'
}

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

# ---------------------------------------------------------------------------
# Profile management
# ---------------------------------------------------------------------------

function Get-ProfileHealthResults {
    <#
    .SYNOPSIS
        Checks the deployed $PROFILE against the expected section patterns.
    .DESCRIPTION
        Reads $PROFILE and tests each pattern from $script:ExpectedProfileSections.
        Returns a structured array usable by the Profile screen.
    .OUTPUTS
        [hashtable] @{ Sections = array of @{ Section, Status, Pattern, Suggestion }; Error = string|$null }
    #>
    $profilePath = $PROFILE
    if (-not (Test-Path $profilePath)) {
        return @{ Sections = @(); Error = "No profile found at $profilePath" }
    }

    try {
        $content = Get-Content -Path $profilePath -Raw -ErrorAction Stop
    }
    catch {
        return @{ Sections = @(); Error = "Cannot read profile: $_" }
    }

    $results = @()
    foreach ($section in $script:ExpectedProfileSections.GetEnumerator()) {
        $found = $content -match $section.Value
        $suggestion = $script:ProfileSuggestions[$section.Key]
        if (-not $suggestion) {
            $suggestion = 'This section is missing from your deployed profile. Redeploy to restore it.'
        }
        $results += @{
            Section    = $section.Key
            Status     = if ($found) { 'Pass' } else { 'Fail' }
            Pattern    = $section.Value
            Suggestion = $suggestion
        }
    }

    return @{ Sections = $results; Error = $null }
}

function Get-ProfileDriftStatus {
    <#
    .SYNOPSIS
        Compares the deployed $PROFILE against $env:WINSETUP\profile.ps1.
    .OUTPUTS
        [hashtable] @{ Status = 'InSync'|'Drifted'|'SourceNotFound'; DiffText = string }
    #>
    $deployed = $PROFILE
    $source   = Join-Path $env:WINSETUP 'profile.ps1'

    if (-not (Test-Path $source)) {
        return @{ Status = 'SourceNotFound'; DiffText = "Source file not found: $source" }
    }
    if (-not (Test-Path $deployed)) {
        return @{ Status = 'Drifted'; DiffText = "Deployed profile does not exist at $deployed" }
    }

    try {
        $deployedRaw = (Get-Content -Path $deployed -Raw -ErrorAction Stop).TrimEnd()
        $sourceRaw   = (Get-Content -Path $source   -Raw -ErrorAction Stop).TrimEnd()
    }
    catch {
        return @{ Status = 'Drifted'; DiffText = "Error reading files: $_" }
    }

    if ($deployedRaw -eq $sourceRaw) {
        return @{ Status = 'InSync'; DiffText = '' }
    }

    # Build human-readable diff
    $deployedLines = $deployedRaw -split "`r?`n"
    $sourceLines   = $sourceRaw   -split "`r?`n"

    $diffs = Compare-Object -ReferenceObject $sourceLines -DifferenceObject $deployedLines
    $inDeployed = @($diffs | Where-Object { $_.SideIndicator -eq '=>' } | ForEach-Object { $_.InputObject })
    $inSource   = @($diffs | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject })

    $lines = @()
    $sep = [string]::new([char]0x2500, 56)
    $lines += "$sep"
    $lines += " Comparing deployed `$PROFILE vs `$env:WINSETUP\profile.ps1"
    $lines += "$sep"
    $lines += ''

    if ($inDeployed.Count -gt 0) {
        $lines += "Lines only in deployed profile (not in source):"
        foreach ($l in $inDeployed) {
            if (-not [string]::IsNullOrWhiteSpace($l)) { $lines += "  $l" }
        }
        $lines += ''
    }

    if ($inSource.Count -gt 0) {
        $lines += "Lines only in source (not in deployed profile):"
        foreach ($l in $inSource) {
            if (-not [string]::IsNullOrWhiteSpace($l)) { $lines += "  $l" }
        }
    }

    return @{ Status = 'Drifted'; DiffText = ($lines -join "`n") }
}

function Invoke-ProfileRedeploy {
    <#
    .SYNOPSIS
        Runs Apply-PowerShellProfile.ps1 from winSetup as a background job.
    .DESCRIPTION
        Starts the script which copies profile.ps1 to $PROFILE with a backup.
        The timer polls the job and streams output.
    .OUTPUTS
        [bool] True if the job was started.
    #>
    if ($script:ProfileRedeployJob) { return $false }

    $applyScript = Join-Path $env:WINSETUP 'Apply-PowerShellProfile.ps1'
    if (-not (Test-Path $applyScript)) { return $false }

    $script:ProfileRedeployOutput = ''
    $script:ProfileRedeployJob = Start-Job -ScriptBlock {
        param($scriptPath)
        & $scriptPath 2>&1
    } -ArgumentList $applyScript

    return $true
}

function Open-FileInVSCode {
    <#
    .SYNOPSIS
        Opens a file in VS Code.
    .PARAMETER Path
        The file path to open.
    .OUTPUTS
        [bool] True if VS Code was launched.
    #>
    param([string]$Path)

    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        & code $Path 2>$null
        return $true
    }
    catch { return $false }
}

function Open-FileDiffInVSCode {
    <#
    .SYNOPSIS
        Opens two files in VS Code diff view.
    .PARAMETER PathA
        Left-side file.
    .PARAMETER PathB
        Right-side file.
    .OUTPUTS
        [bool] True if VS Code was launched.
    #>
    param([string]$PathA, [string]$PathB)

    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        & code --diff $PathA $PathB 2>$null
        return $true
    }
    catch { return $false }
}
