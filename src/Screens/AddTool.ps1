# AddTool.ps1 - Add Tool Wizard: dispatcher, shared state, and shared helpers
#
# The wizard has two paths, each in its own file:
#   AddTool-Search.ps1  -- search wizard path (job management, result display)
#   AddTool-Guided.ps1  -- guided wizard path (field input, validation)
# Both paths share the state, navigation, confirmation, and UI helpers below.

# ---------------------------------------------------------------------------
# Wizard state
# ---------------------------------------------------------------------------

$script:WizardStep = 'ChoosePath'
$script:WizardData = @{
    DisplayName    = ''
    PackageManager = ''
    PackageId      = ''
    VerifyCommand  = ''
    ProfileAlias   = ''
    Path           = ''   # 'Search' | 'Guided'
}

# Background search jobs
$script:ChocoSearchJob      = $null
$script:WingetSearchJob     = $null
$script:PyPISearchJob       = $null
$script:ChocoSearchResults  = @()
$script:WingetSearchResults = @()
$script:PyPISearchResults   = @()

# Lazy description fetch job (for choco/winget results without descriptions)
$script:DescriptionJob    = $null
$script:_DescriptionResult = $null

# Guided step definitions
# AllowedPattern: field-specific character allowlists to prevent code injection.
# Values are validated before advancing the wizard step.
$script:GuidedSteps = @(
    @{ Title = 'Display name';               Desc = 'A friendly name for the tool (e.g. ripgrep, lazygit).';                                            Key = 'DisplayName';    Type = 'text';   Required = $true;  Next = 'GuidedManager';   AllowedPattern = '^[a-zA-Z0-9\-\._\s]+$' }
    @{ Title = 'Package manager';            Desc = 'Which package manager installs this tool?';                                                         Key = 'PackageManager'; Type = 'select'; Required = $true;  Next = 'GuidedPackageId'; Options = @('choco','winget','pipx','manual') }
    @{ Title = 'Package ID';                 Desc = 'The exact package ID used by the package manager (e.g. BurntSushi.ripgrep.MSVC for winget).';      Key = 'PackageId';      Type = 'text';   Required = $true;  Next = 'GuidedVerify';    AllowedPattern = '^[a-zA-Z0-9\-\.\_\/]+$' }
    @{ Title = 'Verify command';             Desc = 'The command used to verify installation (e.g. rg --version).';                                      Key = 'VerifyCommand';  Type = 'text';   Required = $true;  Next = 'GuidedAlias';     AllowedPattern = '^[a-zA-Z0-9\-\.\_]+$' }
    @{ Title = 'Profile alias (optional)';   Desc = 'Optional. An alias or config line to add to your PowerShell profile (e.g. Set-Alias rg ripgrep).'; Key = 'ProfileAlias';   Type = 'text';   Required = $false; Next = 'Confirmation';    AllowedPattern = '^[a-zA-Z0-9\-\_\s\$\=\.\(\)''\"\\:,\|]+$' }
)

# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

function Build-AddToolScreen {
    <#
    .SYNOPSIS
        Entry point for the Add Tool wizard. Dispatches to the current step.
    .PARAMETER Container
        The parent view to add screen elements to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    switch ($script:WizardStep) {
        'ChoosePath'      { Build-WizardChoosePath    -Container $Container }
        'SearchInput'     { Build-WizardSearchInput   -Container $Container }
        'Searching'       { Build-WizardSearching     -Container $Container }
        'SearchResults'   { Build-WizardSearchResults  -Container $Container }
        'ReviewFields'    { Build-WizardReviewFields   -Container $Container }
        'GuidedName'      { Build-WizardGuidedStep -Container $Container -StepIndex 0 }
        'GuidedManager'   { Build-WizardGuidedStep -Container $Container -StepIndex 1 }
        'GuidedPackageId' { Build-WizardGuidedStep -Container $Container -StepIndex 2 }
        'GuidedVerify'    { Build-WizardGuidedStep -Container $Container -StepIndex 3 }
        'GuidedAlias'     { Build-WizardGuidedStep -Container $Container -StepIndex 4 }
        'Confirmation'    { Build-WizardConfirmation  -Container $Container }
        default           { Build-WizardChoosePath    -Container $Container }
    }
}

# ---------------------------------------------------------------------------
# Step navigation
# ---------------------------------------------------------------------------

function Step-WizardBack {
    <#
    .SYNOPSIS
        Navigates to the previous wizard step.
    #>
    switch ($script:WizardStep) {
        'SearchInput'     { $script:WizardStep = 'ChoosePath' }
        'Searching'       { Stop-WizardSearchJobs; $script:WizardStep = 'SearchInput' }
        'SearchResults'   { $script:WizardStep = 'SearchInput' }
        'ReviewFields'    { $script:WizardStep = 'SearchResults' }
        'GuidedName'      { $script:WizardStep = 'ChoosePath' }
        'GuidedManager'   { $script:WizardStep = 'GuidedName' }
        'GuidedPackageId' { $script:WizardStep = 'GuidedManager' }
        'GuidedVerify'    { $script:WizardStep = 'GuidedPackageId' }
        'GuidedAlias'     { $script:WizardStep = 'GuidedVerify' }
        'Confirmation'    {
            if ($script:WizardData.Path -eq 'Search') { $script:WizardStep = 'ReviewFields' }
            else { $script:WizardStep = 'GuidedAlias' }
        }
        default { $script:WizardStep = 'ChoosePath' }
    }
    Switch-Screen -ScreenName 'AddTool'
}

function Reset-WizardState {
    <#
    .SYNOPSIS
        Resets all wizard state to defaults.
    #>
    $script:WizardStep = 'ChoosePath'
    $script:WizardData = @{
        DisplayName = ''; PackageManager = ''; PackageId = ''
        VerifyCommand = ''; ProfileAlias = ''
        Path = ''
    }
    Stop-WizardSearchJobs
    $script:ChocoSearchResults  = @()
    $script:WingetSearchResults = @()
    $script:PyPISearchResults   = @()
}

function Stop-WizardSearchJobs {
    <#
    .SYNOPSIS
        Cancels any running package search or description fetch jobs.
    #>
    foreach ($jobVar in @('ChocoSearchJob', 'WingetSearchJob', 'PyPISearchJob', 'DescriptionJob')) {
        $job = Get-Variable -Name $jobVar -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if ($job) {
            try { Stop-Job $job -ErrorAction SilentlyContinue } catch {}
            try { Remove-Job $job -Force -ErrorAction SilentlyContinue } catch {}
            Set-Variable -Name $jobVar -Value $null -Scope Script
        }
    }
}

# ---------------------------------------------------------------------------
# Step 1: Choose path (shared entry point for both paths)
# ---------------------------------------------------------------------------

function Build-WizardChoosePath {
    <#
    .SYNOPSIS
        Builds the initial wizard step where the user chooses Search or Guided.
    .DESCRIPTION
        Presents a two-option list: search package managers or enter details
        manually via the guided wizard. Sets WizardData.Path and advances.
    #>
    param($Container)

    Add-WizardHeader -Container $Container -Breadcrumb ''

    $prompt = [Terminal.Gui.Label]::new("  Choose how to add a new tool:")
    $prompt.X = 0; $prompt.Y = 2; $prompt.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($prompt)

    $options = [System.Collections.Generic.List[string]]::new()
    $options.Add("  Search package managers")
    $options.Add("  Enter tool details manually")

    $optList = [Terminal.Gui.ListView]::new($options)
    $optList.X = 2; $optList.Y = 4
    $optList.Width = [Terminal.Gui.Dim]::Fill(2); $optList.Height = 2
    $optList.AllowsMarking = $false
    if ($script:Colors.Menu) { $optList.ColorScheme = $script:Colors.Menu }

    # Dynamic description label
    $script:_ChoosePathDesc = [Terminal.Gui.Label]::new("")
    $script:_ChoosePathDesc.X = 4; $script:_ChoosePathDesc.Y = 7
    $script:_ChoosePathDesc.Width = [Terminal.Gui.Dim]::Fill(4); $script:_ChoosePathDesc.Height = 2
    if ($script:Colors.Dim) { $script:_ChoosePathDesc.ColorScheme = $script:Colors.Dim }
    $Container.Add($script:_ChoosePathDesc)

    $script:_ChoosePathDescriptions = @(
        "Search choco, winget, and PyPI to find and register a tool`nautomatically. Best for well-known CLI tools."
        "Provide the tool name, package ID, and profile settings yourself.`nBest for tools not in package manager search."
    )
    $script:_ChoosePathDesc.Text = $script:_ChoosePathDescriptions[0]

    $optList.add_SelectedItemChanged({
        param($e)
        $idx = $script:Layout.MenuList.SelectedItem
        if ($idx -ge 0 -and $idx -lt $script:_ChoosePathDescriptions.Count) {
            $script:_ChoosePathDesc.Text = $script:_ChoosePathDescriptions[$idx]
            $script:_ChoosePathDesc.SetNeedsDisplay()
        }
    })

    $optList.add_OpenSelectedItem({
        param($e)
        if ($e.Item -eq 0) {
            $script:WizardData.Path = 'Search'
            $script:WizardStep = 'SearchInput'
        } else {
            $script:WizardData.Path = 'Guided'
            $script:WizardStep = 'GuidedName'
        }
        Switch-Screen -ScreenName 'AddTool'
    })

    Add-WizardHint -Container $Container -Y 10 -Text "Enter to select, Escape to cancel"

    $Container.Add($optList)
    $script:Layout.MenuList = $optList
    $optList.SetFocus()
}

# ---------------------------------------------------------------------------
# Confirmation screen (shared by both paths)
# ---------------------------------------------------------------------------

function Build-WizardConfirmation {
    <#
    .SYNOPSIS
        Builds the final confirmation screen with a diff preview of all changes.
    .DESCRIPTION
        Shows the generated code changes across Setup, Update, and profile files.
        The user presses C to confirm and write, or Escape to go back.
    #>
    param($Container)

    Add-WizardHeader -Container $Container -Breadcrumb 'Confirmation'

    $context = [Terminal.Gui.Label]::new("  Confirm the changes that will be made to your winSetup configuration.")
    $context.X = 0; $context.Y = 1; $context.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($context)

    # Generate diff preview
    $diffText = Get-ToolDiffPreview -ToolData $script:WizardData

    $tv = [Terminal.Gui.TextView]::new()
    $tv.X = 1; $tv.Y = 3
    $tv.Width  = [Terminal.Gui.Dim]::Fill(1)
    $tv.Height = [Terminal.Gui.Dim]::Fill(3)
    $tv.ReadOnly = $true
    $tv.Text = $diffText
    if ($script:Colors.Base) { $tv.ColorScheme = $script:Colors.Base }

    $tv.add_KeyPress({
        param($e)
        $key = $e.KeyEvent.Key

        # 'c' / 'C' -- confirm and write
        if ([int]$key -eq [int][char]'c' -or [int]$key -eq [int][char]'C') {
            Invoke-WizardConfirm
            $e.Handled = $true
            return
        }
        if ($key -eq [Terminal.Gui.Key]::Esc) {
            Step-WizardBack
            $e.Handled = $true
        }
    })

    $hints = [Terminal.Gui.Label]::new("  [C] Confirm and write    [Escape] Cancel")
    $hints.X = 0; $hints.Y = [Terminal.Gui.Pos]::AnchorEnd(2)
    $hints.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $hints.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($hints)

    $Container.Add($tv)
    $script:Layout.MenuList = $null
    $tv.SetFocus()
}

function Save-NewToolRegistration {
    <#
    .SYNOPSIS
        Appends the new tool to $script:KnownTools on disk and in memory.
    .DESCRIPTION
        Mirrors Uninstall-Tool.ps1 Step 5 in reverse. Backs up WinSetup.ps1
        before editing. Updates the in-memory array and invalidates cached
        inventory so the next Get-ToolInventory picks up the new tool.
    .OUTPUTS
        [string] Empty on success. Error message on failure.
    #>
    try {
        $wtWinSetup = Join-Path $script:WinTerfaceRoot 'src' 'Services' 'WinSetup.ps1'
        if (-not (Test-Path $wtWinSetup)) {
            return "WinSetup.ps1 not found at $wtWinSetup. Tool inventory will not include this tool until restarted."
        }

        $backup = "$wtWinSetup.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $wtWinSetup $backup -ErrorAction SilentlyContinue
        Remove-OldBackups -SourceFile $wtWinSetup -Keep 3

        # Escape single quotes in all user-supplied values before embedding in
        # generated code. Search-path values bypass AllowedPattern validation
        # and rely on this escaping for safety.
        $safeName    = $script:WizardData.DisplayName    -replace "'", "''"
        $safeCommand = $script:WizardData.VerifyCommand  -replace "'", "''"
        $safeManager = $script:WizardData.PackageManager -replace "'", "''"

        $wsContent = Get-Content $wtWinSetup
        $newEntry = "    @{ Name = '$safeName'; Command = '$safeCommand'; Manager = '$safeManager'; Desc = '$safeName tool.' }"
        $inserted = $false
        $newLines = [System.Collections.Generic.List[string]]::new()
        foreach ($l in $wsContent) {
            $newLines.Add($l)
            if (-not $inserted -and $l -match '^\)' -and $newLines.Count -gt 5) {
                $prev = $newLines[$newLines.Count - 2]
                if ($prev -match "Name\s*=") {
                    $newLines.Insert($newLines.Count - 1, $newEntry)
                    $inserted = $true
                }
            }
        }
        if ($inserted) { $newLines | Set-Content $wtWinSetup -Encoding UTF8 }

        # Update in-memory array and invalidate cached inventory
        $script:KnownTools += @{
            Name    = $script:WizardData.DisplayName
            Command = $script:WizardData.VerifyCommand
            Manager = $script:WizardData.PackageManager
            Desc    = "$($script:WizardData.DisplayName) tool."
        }
        $script:ToolInventoryData = $null
        return ''
    }
    catch {
        return "KnownTools update failed: $($_.Exception.Message). The tool was registered in winSetup but may not appear in the inventory until restarted."
    }
}

function Invoke-WizardConfirm {
    <#
    .SYNOPSIS
        Executes the atomic write, registers the tool, and offers to install.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()
    $result = Write-ToolChanges -ToolData $script:WizardData

    if ($result.Success) {
        $regError = Save-NewToolRegistration
        $fileCount = $result.FilesWritten.Count
        $toolName  = $script:WizardData.DisplayName

        # Ask whether to install the tool now
        $script:_InstallNow = $false
        $installBtn = [Terminal.Gui.Button]::new("_Install now")
        $laterBtn   = [Terminal.Gui.Button]::new("_Later")

        $dialogHeight = if ($regError) { 12 } else { 9 }
        $dialog = [Terminal.Gui.Dialog]::new("Tool registered", 62, $dialogHeight,
            [Terminal.Gui.Button[]]@($installBtn, $laterBtn))

        $msgText = " '$toolName' registered ($fileCount files written)."
        if ($regError) {
            $msgText += "`n`n Warning: $regError"
        }
        $msgText += "`n`n Install it now?"

        $lblHeight = if ($regError) { 6 } else { 3 }
        $lbl = [Terminal.Gui.Label]::new($msgText)
        $lbl.X = 1; $lbl.Y = 1; $lbl.Width = [Terminal.Gui.Dim]::Fill(1); $lbl.Height = $lblHeight
        $dialog.Add($lbl)

        $installBtn.add_Clicked({ $script:_InstallNow = $true; [Terminal.Gui.Application]::RequestStop() })
        $laterBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })

        $script:UpdateFlowActive = $true
        try { [Terminal.Gui.Application]::Run($dialog) } catch {}
        $script:UpdateFlowActive = $false

        Reset-WizardState

        if ($script:_InstallNow) {
            # Navigate to Tools screen and kick off the install
            Switch-Screen -ScreenName 'Tools'
            $setupScript = Join-Path $env:WINSETUP 'Setup-DevEnvironment.ps1'
            if (Test-Path $setupScript) {
                $script:ToolsOutputText = ''
                Add-ToolsOutput -Text "Installing $toolName..."
                $script:ToolActionJob = Start-Job -ScriptBlock {
                    param($scriptPath, $name)
                    try {
                        # Refresh PATH -- Start-Job runs with -NoProfile so
                        # choco/winget may not be on PATH.
                        $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                                    ';' +
                                    [System.Environment]::GetEnvironmentVariable('PATH', 'User')
                        $escaped = $scriptPath -replace "'", "''"
                        $output = pwsh -NoProfile -NonInteractive -Command "& '$escaped' -InstallTool '$name' -JobMode" 2>&1
                        $output | ForEach-Object { Write-Output $_ }
                    } catch {
                        Write-Error "Job failed: $_"
                    }
                } -ArgumentList $setupScript, $toolName
            }
        } else {
            Switch-Screen -ScreenName 'Home'
        }
    } else {
        $okBtn = [Terminal.Gui.Button]::new("_OK")
        $okBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })
        $dialog = [Terminal.Gui.Dialog]::new("Error", 60, 8, [Terminal.Gui.Button[]]@($okBtn))
        $lbl = [Terminal.Gui.Label]::new(" $($result.Error)")
        $lbl.X = 1; $lbl.Y = 1; $lbl.Width = [Terminal.Gui.Dim]::Fill(1)
        $dialog.Add($lbl)
        [Terminal.Gui.Application]::Run($dialog)
    }
}

# ---------------------------------------------------------------------------
# Shared wizard UI helpers
# ---------------------------------------------------------------------------

function Add-WizardHeader {
    <#
    .SYNOPSIS
        Adds the standard wizard header line.
    .PARAMETER Container
        Parent view.
    .PARAMETER Breadcrumb
        Trail text after "ADD TOOL" (e.g. "Search", "Step 3 of 6").
    #>
    param($Container, [string]$Breadcrumb)

    $text = if ($Breadcrumb) { "  ADD TOOL > $Breadcrumb" } else { "  ADD TOOL" }
    $header = [Terminal.Gui.Label]::new($text)
    $header.X = 0; $header.Y = 0; $header.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $header.ColorScheme = $script:Colors.Header }
    $Container.Add($header)
}

function Add-WizardHint {
    <#
    .SYNOPSIS
        Adds a hint label at the specified Y position.
    .PARAMETER Container
        Parent view.
    .PARAMETER Y
        Y position (int or Pos).
    .PARAMETER Text
        Hint text.
    #>
    param($Container, $Y, [string]$Text)

    $hint = [Terminal.Gui.Label]::new("  $Text")
    $hint.X = 0; $hint.Y = $Y; $hint.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $hint.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($hint)
}
