# WinSetup.ps1 - Interface to winSetup scripts and functions

$script:UpdateRunJob       = $null
$script:UpdateRunStartTime = $null

# Queued per-package update state
$script:UpdatePackageQueue   = @()
$script:UpdatePackageIndex   = -1
$script:UpdatePackageResults = @{}
$script:IsQueuedUpdate       = $false
# Blocks screen rebuilds during the update flow. Without this, the 500ms
# timer could call Switch-Screen('Updates') mid-dialog, destroying views
# the key handler still holds references to.
$script:UpdateFlowActive     = $false

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

# Plain-language descriptions of each profile section for display in the detail
# panel. Keyed by section name matching Test-ProfileHealth output. Avoids
# exposing regex patterns to the user.
$script:ProfileDescriptions = @{
    'SSH Agent'           = 'Starts the SSH agent and loads your key automatically when a terminal opens.'
    'Chocolatey'          = 'Imports the Chocolatey profile so tab completion works for choco commands.'
    'winSetup'            = 'Sets the $env:WINSETUP variable so other profile sections can find winSetup.'
    'Python Tools'        = 'Auto-checks and installs Python dev tools (pylint, ruff, mypy, etc.) periodically.'
    'fzf'                 = 'Configures fzf defaults: reverse layout, inline info, and 80% height.'
    'PSFzf'               = 'Imports PSFzf for Ctrl+T (file finder) and Ctrl+R (history search) bindings.'
    'PSReadLine'          = 'Enables predictive autosuggestions and dropdown menu completion in the prompt.'
    'zoxide'              = 'Initialises zoxide so the z command can jump to frequently used directories.'
    'zoxide OMP fix'      = 'Patches the zoxide prompt hook to work alongside Oh My Posh.'
    'pyenv-win'           = 'Adds pyenv-win to PATH so pyenv commands are available.'
    'lazygit alias'       = 'Creates the lg alias as a shorthand for lazygit.'
    'delta'               = 'Sets delta environment variables for side-by-side git diff display.'
    'bat alias'           = 'Aliases cat to bat for syntax-highlighted file viewing.'
    'Ctrl+F binding'      = 'Binds Ctrl+F to an fzf file picker with bat preview.'
    'Git aliases'         = 'Defines shorthand functions: gs (status), ga (add), gc (commit), gp (push), gl (log).'
    'gl alias fix'        = "Removes PowerShell's built-in gl alias so the git log function works."
    'gc alias fix'        = "Removes PowerShell's built-in gc alias so the git commit function works."
    'Oh My Posh'          = 'Initialises Oh My Posh with the gruvbox theme for a customised prompt.'
    'Test-ProfileHealth'  = 'Makes the Test-ProfileHealth command available to check profile completeness.'
    'Invoke-DevSetup'     = 'Makes the Invoke-DevSetup convenience command available.'
    'Invoke-DevUpdate'    = 'Makes the Invoke-DevUpdate convenience command available.'
    'Show-DevEnvironment' = 'Makes the Show-DevEnvironment command available to display environment status.'
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
    [OutputType([hashtable])]
    param()
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
        Lightweight profile health check using pattern matching.
    .DESCRIPTION
        Do not call winSetup's Test-ProfileHealth here. It uses Write-Host
        which corrupts Terminal.Gui's console driver. Pattern matching
        directly against $PROFILE content avoids the collision.
    .OUTPUTS
        [hashtable] @{ Status = 'Ok'|'Warn'|'Error'; Message = string }
    #>
    [OutputType([hashtable])]
    param()
    if (-not (Test-WinSetupPath)) {
        return @{ Status = 'Warn'; Message = 'winSetup not configured' }
    }

    if (-not (Test-Path $PROFILE)) {
        return @{ Status = 'Error'; Message = 'No profile found' }
    }

    try {
        if (-not $script:ExpectedProfileSections) {
            return @{ Status = 'Warn'; Message = 'Run profile check' }
        }
        $content = Get-Content -Path $PROFILE -Raw -ErrorAction Stop
        $missing = 0
        foreach ($section in $script:ExpectedProfileSections.GetEnumerator()) {
            if ($content -notmatch $section.Value) { $missing++ }
        }

        if ($missing -eq 0) {
            return @{ Status = 'Ok'; Message = 'Healthy' }
        }
        return @{ Status = 'Warn'; Message = "$missing sections missing" }
    }
    catch {
        return @{ Status = 'Error'; Message = 'Check failed' }
    }
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

    $script:UpdateFlowActive = $true
    try {
        [Terminal.Gui.Application]::Run($dialog)
    }
    catch {
        return $false
    }
    finally {
        $script:UpdateFlowActive = $false
    }
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()

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

    # Launch the job. Refresh PATH from Machine + User env vars because
    # Start-Job runs with -NoProfile so choco/winget may not be on PATH.
    $script:UpdateRunJob       = Start-Job -ScriptBlock {
        param($scriptPath)
        try {
            # Jobs don't inherit Start-Transcript -- all output goes to the
            # output pane via Receive-Job in the timer callback.
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                        ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH', 'User')
            Write-Host "[job] PATH: $($env:PATH -split ';' | Where-Object { $_ } | Select-Object -First 10 | Join-String -Separator ', ')..."
            $choco = Get-Command choco -ErrorAction SilentlyContinue
            $winget = Get-Command winget -ErrorAction SilentlyContinue
            Write-Host "[job] choco: $(if ($choco) { $choco.Source } else { 'NOT FOUND' })"
            Write-Host "[job] winget: $(if ($winget) { $winget.Source } else { 'NOT FOUND' })"
            Write-Host "[job] Running: & '$scriptPath' -NoWait"
            & $scriptPath -NoWait
            Write-Host "[job] Exit code: $LASTEXITCODE"
        } catch {
            Write-Error "[job] Failed: $_ $($_.ScriptStackTrace)"
        }
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()
    $pkg = $script:UpdatePackageQueue[$script:UpdatePackageIndex]

    $sep = [string]::new([char]0x2500, 42)
    Add-UpdateOutput -Text $sep
    Add-UpdateOutput -Text " Updating $($pkg.name)..."
    Add-UpdateOutput -Text $sep

    # Refresh PATH in the job -- same -NoProfile fix as the full update job.
    $updateScript = Join-Path $env:WINSETUP 'Update-DevEnvironment.ps1'
    $script:UpdateRunJob       = Start-Job -ScriptBlock {
        param($scriptPath, $packageName)
        try {
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                        ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH', 'User')
            Write-Host "[job] Running: & '$scriptPath' -Package '$packageName' -NoWait"
            & $scriptPath -Package $packageName -NoWait
            Write-Host "[job] Exit code: $LASTEXITCODE"
        } catch {
            Write-Error "[job] Failed: $_ $($_.ScriptStackTrace)"
        }
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

    Add-UpdateOutput -Text ''
    Add-UpdateOutput -Text "--- $succeeded updated, $failed failed ---"

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
    [OutputType([hashtable])]
    param()
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

function Remove-WinTerfaceLauncherBlock {
    <#
    .SYNOPSIS
        Strips the winTerface launcher block from profile content.
    .DESCRIPTION
        Install-WinTerface.ps1 appends a launcher function and wti alias to
        $PROFILE after winSetup deploys it. This block is a known managed
        addition and must be excluded from drift detection so it is not
        flagged as unmanaged drift on every machine with winTerface installed.
        The block is identified by the "# winTerface launcher" comment header
        and ends at the Set-Alias line that follows the closing brace.
    .PARAMETER Content
        The raw profile content string.
    .OUTPUTS
        [string] Content with the launcher block removed.
    #>
    param([string]$Content)
    # Match: optional leading blank lines, the comment header, the function
    # body through its closing brace, and the Set-Alias line.
    return $Content -replace '(?m)(\r?\n)*^# winTerface launcher\r?\n[\s\S]*?^Set-Alias wti Invoke-WinTerface\r?\n?', ''
}

function Get-ProfileDriftStatus {
    <#
    .SYNOPSIS
        Compares the deployed $PROFILE against $env:WINSETUP\profile.ps1.
    .OUTPUTS
        [hashtable] @{ Status = 'InSync'|'Drifted'|'SourceNotFound'; DiffText = string }
    #>
    [OutputType([hashtable])]
    param()
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

    # Strip known managed additions before comparing
    $deployedRaw = (Remove-WinTerfaceLauncherBlock -Content $deployedRaw).TrimEnd()

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
    # $PROFILE is not available inside Start-Job (-NoProfile). Pass it
    # explicitly and set it in the job so Apply-PowerShellProfile.ps1
    # knows where to deploy.
    $profilePath = $PROFILE
    $script:ProfileRedeployJob = Start-Job -ScriptBlock {
        param($scriptPath, $prof)
        try {
            $global:PROFILE = $prof
            & $scriptPath 2>&1
        } catch {
            Write-Error "Job failed: $_"
        }
    } -ArgumentList $applyScript, $profilePath

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

# ---------------------------------------------------------------------------
# Config management -- tool inventory, path update, cache operations
# ---------------------------------------------------------------------------

# Supplementary metadata for tools that cannot be fully derived from
# $PackageRegistry alone. Maps registry key to display Name, CLI Command,
# and description. Tools not listed here default to: Name = key,
# Command = key, Desc = '<key> tool.'
$script:ToolMetadata = @{
    'vscode'      = @{ Name = 'VS Code';    Command = 'code';       Desc = 'Code editor.' }
    'python'      = @{ Name = 'Python';      Command = 'python';     Desc = 'Python programming language.' }
    'git'         = @{ Name = 'Git';         Command = 'git';        Desc = 'Version control system.' }
    'ohmyposh'    = @{ Name = 'Oh My Posh';  Command = 'oh-my-posh'; Desc = 'Prompt theme engine.' }
    'gh'          = @{ Name = 'GitHub CLI';  Command = 'gh';         Desc = 'GitHub from the command line.' }
    'fzf'         = @{ Name = 'fzf';         Command = 'fzf';        Desc = 'Fuzzy finder.' }
    'ripgrep'     = @{ Name = 'ripgrep';     Command = 'rg';         Desc = 'Fast recursive search tool.' }
    'bat'         = @{ Name = 'bat';         Command = 'bat';        Desc = 'Syntax-highlighted cat replacement.' }
    'delta'       = @{ Name = 'delta';       Command = 'delta';      Desc = 'Git diff viewer.' }
    'lazygit'     = @{ Name = 'lazygit';     Command = 'lazygit';    Desc = 'Terminal UI for git.' }
    'zoxide'      = @{ Name = 'zoxide';      Command = 'zoxide';     Desc = 'Smarter cd command.' }
    'fd'          = @{ Name = 'fd';          Command = 'fd';         Desc = 'Fast file finder.' }
    'pyenv'       = @{ Name = 'pyenv';       Command = 'pyenv';      Desc = 'Python version manager.' }
    'ruff'        = @{ Name = 'ruff';        Command = 'ruff';       Desc = 'Python linter and formatter.' }
    'pylint'      = @{ Name = 'pylint';      Command = 'pylint';     Desc = 'Python code analysis.' }
    'mypy'        = @{ Name = 'mypy';        Command = 'mypy';       Desc = 'Python static type checker.' }
    'bandit'      = @{ Name = 'bandit';      Command = 'bandit';     Desc = 'Python security linter.' }
    'pre-commit'  = @{ Name = 'pre-commit';  Command = 'pre-commit'; Desc = 'Git hook manager.' }
    'cookiecutter'= @{ Name = 'cookiecutter';Command = 'cookiecutter';Desc = 'Project template tool.' }
}

# Tools not in $PackageRegistry that are managed separately
$script:BootstrapTools = @(
    @{ Name = 'Chocolatey'; Command = 'choco'; Manager = 'bootstrap'; PackageId = 'chocolatey'; Desc = 'Package manager for Windows.' }
    @{ Name = 'pipx';       Command = 'pipx';  Manager = 'pip';       PackageId = 'pipx';       Desc = 'Install Python CLI tools in isolation.' }
)

function Get-KnownToolsFromRegistry {
    <#
    .SYNOPSIS
        Parses $PackageRegistry from winSetup and returns tool objects.
    .DESCRIPTION
        Reads Update-DevEnvironment.ps1 from the configured winSetup path,
        extracts $PackageRegistry entries via regex (no Invoke-Expression),
        and merges with supplementary metadata to produce objects with Name,
        Command, Manager, and Desc properties. Falls back to an empty array
        if the file is unreadable. Excludes the PSFzf module entry since it
        is not a CLI tool.
    .OUTPUTS
        [array] Each element: @{ Name; Command; Manager; Desc }
    #>
    $results = @()

    # Start with bootstrap tools not in $PackageRegistry
    $results += $script:BootstrapTools

    $wsPath = $env:WINSETUP
    if (-not $wsPath) {
        $config = Get-WinTerfaceConfig
        if ($config -and $config.winSetupPath) { $wsPath = $config.winSetupPath }
    }

    if (-not $wsPath) {
        Write-Warning 'Cannot load KnownTools: winSetup path not configured.'
        return $results
    }

    $updateScript = Join-Path $wsPath 'Update-DevEnvironment.ps1'
    if (-not (Test-Path $updateScript)) {
        Write-Warning "Cannot load KnownTools: $updateScript not found."
        return $results
    }

    try {
        $content = Get-Content -Path $updateScript -Raw -ErrorAction Stop
        # Same regex pattern as Uninstall-Tool.ps1 (see INTERFACE.md)
        $pattern = '"([^"]+)"\s*=\s*@\{\s*Manager\s*=\s*"([^"]+)";\s*Id\s*=\s*"([^"]+)"\s*\}'
        $regMatches = [regex]::Matches($content, $pattern)
        foreach ($m in $regMatches) {
            $key     = $m.Groups[1].Value
            $manager = $m.Groups[2].Value
            $id      = $m.Groups[3].Value

            # Skip the PSFzf module entry -- it is not a CLI tool
            if ($manager -eq 'module') { continue }

            # Merge with supplementary metadata
            $meta = $script:ToolMetadata[$key]
            $results += @{
                Name      = if ($meta) { $meta.Name }    else { $key }
                Command   = if ($meta) { $meta.Command } else { $key }
                Manager   = $manager
                PackageId = $id
                Desc      = if ($meta) { $meta.Desc }    else { "$key tool." }
            }
        }
    }
    catch {
        Write-Warning "Failed to parse `$PackageRegistry from ${updateScript}: $_"
    }

    return $results
}

# Initialise $script:KnownTools from the registry at load time.
# Call sites (Get-ToolInventory, App.ps1 uninstall handler, AddTool.ps1)
# continue to reference $script:KnownTools directly.
$script:KnownTools = @(Get-KnownToolsFromRegistry)

$script:ToolInventoryJob  = $null
$script:ToolInventoryData = $null

function Get-ToolInventory {
    <#
    .SYNOPSIS
        Starts a background job that checks all known tools via Get-Command
        and --version.  Results are polled by the 500 ms timer.
    #>
    if ($script:ToolInventoryJob) { return }

    $tools = $script:KnownTools
    $script:ToolInventoryData = $null

    $script:ToolInventoryJob = Start-Job -ScriptBlock {
        param($toolList)
        try {
            # Refresh PATH from Machine + User env vars. Start-Job runs with
            # -NoProfile so tools added via the profile (pyenv-win, pipx) are
            # not on PATH by default.
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                        ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH', 'User')

            # Some tools store their PATH in the profile rather than the
            # registry. Add well-known locations as fallback.

            # pyenv-win: two install methods produce different directory layouts.
            # choco/winget: ~\.pyenv\pyenv-win\bin  (+ \shims)
            # pip:          ~\.pyenv\pyenv-win\pyenv-win\bin  (no shims)
            # Try both, use whichever exists.
            $pyenvBinCandidates = @(
                "$env:USERPROFILE\.pyenv\pyenv-win\bin"
                "$env:USERPROFILE\.pyenv\pyenv-win\pyenv-win\bin"
            )
            $pyenvBin = $pyenvBinCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($pyenvBin) {
                $pyenvRoot = Split-Path $pyenvBin -Parent
                if ($env:PATH -notmatch [regex]::Escape($pyenvBin)) {
                    $env:PATH = "$pyenvBin;$env:PATH"
                }
                # Shims dir exists on choco/winget installs, not pip
                $pyenvShims = Join-Path $pyenvRoot 'shims'
                if ((Test-Path $pyenvShims) -and $env:PATH -notmatch [regex]::Escape($pyenvShims)) {
                    $env:PATH = "$pyenvShims;$env:PATH"
                }
                $env:PYENV      = $pyenvRoot
                $env:PYENV_HOME = $pyenvRoot
            }

            # Other profile-injected tool paths
            $extraPaths = @(
                "$env:APPDATA\Python\Python*\Scripts"       # pipx user install
                "$env:LOCALAPPDATA\Programs\oh-my-posh\bin"
            )
            foreach ($p in $extraPaths) {
                $resolved = Resolve-Path $p -ErrorAction SilentlyContinue
                if ($resolved) {
                    foreach ($r in $resolved) {
                        if ($env:PATH -notmatch [regex]::Escape($r.Path)) {
                            $env:PATH = "$($r.Path);$env:PATH"
                        }
                    }
                }
            }

            $results = @()
            foreach ($t in $toolList) {
                $found   = $false
                $version = 'not found'
                $path    = ''
                try {
                    $cmd = Get-Command $t.Command -ErrorAction SilentlyContinue
                    if ($cmd) {
                        $found = $true
                        $path  = $cmd.Source
                        try {
                            $verOut = & $t.Command --version 2>$null | Select-Object -First 1
                            if ($verOut -and "$verOut" -match '(\d+\.\d+[\.\d]*)') {
                                $version = $matches[1]
                            } elseif ($verOut) {
                                $version = ("$verOut").Trim().Substring(0,
                                    [Math]::Min(("$verOut").Trim().Length, 30))
                            } else {
                                $version = 'installed'
                            }
                        } catch { $version = 'installed' }
                    }
                } catch {}

                $status = if (-not $found) { 'Error' }
                          elseif ($version -eq 'installed') { 'Warn' }
                          else { 'Ok' }

                $results += @{
                    Name = $t.Name; Command = $t.Command; Manager = $t.Manager
                    Desc = $t.Desc; Version = $version; Path = $path; Status = $status
                }
            }
            return $results
        } catch {
            Write-Error "Job failed: $_"
        }
    } -ArgumentList @(,$tools)
}

function Update-WinSetupPath {
    <#
    .SYNOPSIS
        Updates the winSetup path across config.json, User env var, and profile.ps1.
    .PARAMETER NewPath
        The new winSetup directory path.
    .OUTPUTS
        [hashtable] @{ Success = bool; Error = string }
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$NewPath
    )

    if (-not (Test-Path $NewPath)) {
        return @{ Success = $false; Error = "Path does not exist: $NewPath" }
    }
    if (-not (Test-Path (Join-Path $NewPath 'Setup-DevEnvironment.ps1'))) {
        return @{ Success = $false; Error = "Setup-DevEnvironment.ps1 not found in: $NewPath" }
    }

    $oldPath = $env:WINSETUP

    try {
        # 1. Update config.json
        $config = Get-WinTerfaceConfig
        $config.winSetupPath = $NewPath
        Set-WinTerfaceConfig -Config $config

        # 2. Set User environment variable
        [System.Environment]::SetEnvironmentVariable('WINSETUP', $NewPath, 'User')

        # 3. Update current session
        $env:WINSETUP = $NewPath

        # 4. Update profile.ps1 fallback path (back up first -- no exceptions)
        $profilePath = Join-Path $NewPath 'profile.ps1'
        if ($oldPath -and (Test-Path $profilePath)) {
            try {
                $backup = "$profilePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item $profilePath $backup -ErrorAction Stop
                Remove-OldBackups -SourceFile $profilePath -Keep 3
                $content = Get-Content -Path $profilePath -Raw -ErrorAction Stop
                if ($content -match [regex]::Escape($oldPath)) {
                    $updated = $content -replace [regex]::Escape($oldPath), $NewPath
                    Set-Content -Path $profilePath -Value $updated -Encoding UTF8 -ErrorAction Stop
                }
            }
            catch {
                return @{ Success = $true; Error = "Config updated but profile.ps1 edit failed: $_" }
            }
        }

        return @{ Success = $true; Error = '' }
    }
    catch {
        return @{ Success = $false; Error = "Update failed: $_" }
    }
}

function Read-UpdateCacheRaw {
    <#
    .SYNOPSIS
        Reads and returns parsed update-cache.json.
    .OUTPUTS
        [hashtable] Cache object. Returns empty structure if file does not exist.
    #>
    [OutputType([hashtable])]
    param()
    $cachePath = Join-Path $env:USERPROFILE '.winTerface' 'update-cache.json'
    if (-not (Test-Path $cachePath)) {
        return @{ lastChecked = $null; updates = @() }
    }
    try {
        $content = Get-Content -Path $cachePath -Raw -ErrorAction Stop
        $cache   = $content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($null -eq $cache.updates) { $cache.updates = @() }
        return $cache
    }
    catch {
        return @{ lastChecked = $null; updates = @() }
    }
}

function Clear-UpdateCacheFile {
    <#
    .SYNOPSIS
        Deletes update-cache.json so the home screen resets to 'Run /check-for-updates'.
    .OUTPUTS
        [bool] True if the file was deleted or already absent.
    #>
    $cachePath = Join-Path $env:USERPROFILE '.winTerface' 'update-cache.json'
    try {
        if (Test-Path $cachePath) { Remove-Item $cachePath -Force -ErrorAction Stop }
        return $true
    }
    catch { return $false }
}
