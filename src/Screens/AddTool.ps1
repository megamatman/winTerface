# AddTool.ps1 - Add Tool Wizard (two paths: search and guided)

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
    UpdateOverride = ''
    Path           = ''   # 'Search' | 'Guided'
}

# Background search jobs
$script:ChocoSearchJob    = $null
$script:WingetSearchJob   = $null
$script:ChocoSearchResults  = @()
$script:WingetSearchResults = @()

# Guided step definitions
$script:GuidedSteps = @(
    @{ Title = 'Display name';               Desc = 'What should this tool be called? (e.g. ripgrep, lazygit)';                  Key = 'DisplayName';    Type = 'text';   Required = $true;  Next = 'GuidedManager' }
    @{ Title = 'Package manager';            Desc = 'Which package manager installs this tool?';                                  Key = 'PackageManager'; Type = 'select'; Required = $true;  Next = 'GuidedPackageId'; Options = @('choco','winget','pipx','manual') }
    @{ Title = 'Package ID';                 Desc = 'Package name or ID used to install (e.g. ripgrep, junegunn.fzf)';           Key = 'PackageId';      Type = 'text';   Required = $true;  Next = 'GuidedVerify' }
    @{ Title = 'Verify command';             Desc = 'Command that confirms installation (e.g. rg, fzf, delta)';                  Key = 'VerifyCommand';  Type = 'text';   Required = $true;  Next = 'GuidedAlias' }
    @{ Title = 'Profile alias (optional)';   Desc = 'Alias or config to add to profile.ps1 (e.g. Set-Alias lg lazygit)';        Key = 'ProfileAlias';   Type = 'text';   Required = $false; Next = 'GuidedUpdate' }
    @{ Title = 'Update override (optional)'; Desc = 'Custom update command if not handled by standard update script';            Key = 'UpdateOverride'; Type = 'text';   Required = $false; Next = 'Confirmation' }
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
        'GuidedUpdate'    { Build-WizardGuidedStep -Container $Container -StepIndex 5 }
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
        'GuidedUpdate'    { $script:WizardStep = 'GuidedAlias' }
        'Confirmation'    {
            if ($script:WizardData.Path -eq 'Search') { $script:WizardStep = 'ReviewFields' }
            else { $script:WizardStep = 'GuidedUpdate' }
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
        VerifyCommand = ''; ProfileAlias = ''; UpdateOverride = ''
        Path = ''
    }
    Stop-WizardSearchJobs
    $script:ChocoSearchResults  = @()
    $script:WingetSearchResults = @()
}

function Stop-WizardSearchJobs {
    <#
    .SYNOPSIS
        Cancels any running package search jobs.
    #>
    foreach ($jobVar in @('ChocoSearchJob', 'WingetSearchJob')) {
        $job = Get-Variable -Name $jobVar -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if ($job) {
            try { Stop-Job $job -ErrorAction SilentlyContinue } catch {}
            try { Remove-Job $job -Force -ErrorAction SilentlyContinue } catch {}
            Set-Variable -Name $jobVar -Value $null -Scope Script
        }
    }
}

# ---------------------------------------------------------------------------
# Step 1: Choose path
# ---------------------------------------------------------------------------

function Build-WizardChoosePath {
    param($Container)

    Add-WizardHeader -Container $Container -Breadcrumb ''

    $prompt = [Terminal.Gui.Label]::new("  Choose how to add a new tool:")
    $prompt.X = 0; $prompt.Y = 2; $prompt.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($prompt)

    $options = [System.Collections.Generic.List[string]]::new()
    $options.Add("  Search package managers")
    $options.Add("  Guided wizard")

    $optList = [Terminal.Gui.ListView]::new($options)
    $optList.X = 2; $optList.Y = 4
    $optList.Width = [Terminal.Gui.Dim]::Fill(2); $optList.Height = 2
    $optList.AllowsMarking = $false
    if ($script:Colors.Menu) { $optList.ColorScheme = $script:Colors.Menu }

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

    Add-WizardHint -Container $Container -Y 7 -Text "Enter to select, Escape to cancel"

    $Container.Add($optList)
    $script:Layout.MenuList = $optList
    $optList.SetFocus()
}

# ---------------------------------------------------------------------------
# Path A: Package search
# ---------------------------------------------------------------------------

function Build-WizardSearchInput {
    param($Container)

    Add-WizardHeader -Container $Container -Breadcrumb 'Search'

    $prompt = [Terminal.Gui.Label]::new("  Enter a tool name to search for:")
    $prompt.X = 0; $prompt.Y = 2; $prompt.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($prompt)

    # $tf is function-local and resolves to $null in .NET event handlers.
    # Stored as $script:_SearchInput before registering the KeyPress handler.
    # See CONTRIBUTING.md -- dialog input fields must use $script: scope.
    $script:_SearchInput = [Terminal.Gui.TextField]::new("")
    $script:_SearchInput.X = 4; $script:_SearchInput.Y = 4
    $script:_SearchInput.Width = [Terminal.Gui.Dim]::Fill(4); $script:_SearchInput.Height = 1
    if ($script:Colors.CommandBar) { $script:_SearchInput.ColorScheme = $script:Colors.CommandBar }

    $script:_SearchInput.add_KeyPress({
        param($e)
        if ($e.KeyEvent.Key -eq [Terminal.Gui.Key]::Enter) {
            $term = $script:_SearchInput.Text.ToString().Trim()
            if ($term.Length -gt 0) {
                Start-WizardSearch -SearchTerm $term
            }
            $e.Handled = $true
        }
        if ($e.KeyEvent.Key -eq [Terminal.Gui.Key]::Esc) {
            Step-WizardBack
            $e.Handled = $true
        }
    })

    Add-WizardHint -Container $Container -Y 6 -Text "Enter to search, Escape to go back"

    $Container.Add($script:_SearchInput)
    $script:Layout.MenuList = $null
    $script:_SearchInput.SetFocus()
}

function Start-WizardSearch {
    <#
    .SYNOPSIS
        Launches concurrent choco and winget search jobs.
    .PARAMETER SearchTerm
        The text to search for.
    #>
    param([string]$SearchTerm)

    $pkgMgrScript = Join-Path $script:WinTerfaceRoot 'src' 'Services' 'PackageManager.ps1'

    $script:ChocoSearchJob = Start-Job -ScriptBlock {
        param($sp, $term)
        . $sp
        Search-ChocolateyPackage -Name $term
    } -ArgumentList $pkgMgrScript, $SearchTerm

    $script:WingetSearchJob = Start-Job -ScriptBlock {
        param($sp, $term)
        . $sp
        Search-WingetPackage -Name $term
    } -ArgumentList $pkgMgrScript, $SearchTerm

    $script:WizardStep = 'Searching'
    Switch-Screen -ScreenName 'AddTool'
}

function Build-WizardSearching {
    param($Container)

    Add-WizardHeader -Container $Container -Breadcrumb 'Search'

    $status = [Terminal.Gui.Label]::new("  Searching...")
    $status.X = 0; $status.Y = 2; $status.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $status.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($status)

    $chocoState  = if ($script:ChocoSearchJob)  { 'searching...' } else { 'done' }
    $wingetState = if ($script:WingetSearchJob) { 'searching...' } else { 'done' }

    $c1 = [Terminal.Gui.Label]::new("  Chocolatey   $chocoState")
    $c1.X = 0; $c1.Y = 4; $c1.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($c1)

    $c2 = [Terminal.Gui.Label]::new("  Winget       $wingetState")
    $c2.X = 0; $c2.Y = 5; $c2.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($c2)

    Add-WizardHint -Container $Container -Y 7 -Text "Escape to cancel"
}

function Update-SearchJobStatus {
    <#
    .SYNOPSIS
        Polls the search background jobs.  Called by the 500 ms timer.
    #>
    if (-not $script:ChocoSearchJob -and -not $script:WingetSearchJob) { return }

    $bothDone = $true

    if ($script:ChocoSearchJob) {
        if ($script:ChocoSearchJob.State -ne 'Running') {
            try { $script:ChocoSearchResults = @(Receive-Job $script:ChocoSearchJob -ErrorAction SilentlyContinue) }
            catch { $script:ChocoSearchResults = @() }
            try { Remove-Job $script:ChocoSearchJob -Force } catch {}
            $script:ChocoSearchJob = $null
        } else { $bothDone = $false }
    }

    if ($script:WingetSearchJob) {
        if ($script:WingetSearchJob.State -ne 'Running') {
            try { $script:WingetSearchResults = @(Receive-Job $script:WingetSearchJob -ErrorAction SilentlyContinue) }
            catch { $script:WingetSearchResults = @() }
            try { Remove-Job $script:WingetSearchJob -Force } catch {}
            $script:WingetSearchJob = $null
        } else { $bothDone = $false }
    }

    if ($bothDone -and $script:WizardStep -eq 'Searching') {
        $script:WizardStep = 'SearchResults'
        Switch-Screen -ScreenName 'AddTool'
    }
}

function Build-WizardSearchResults {
    param($Container)

    Add-WizardHeader -Container $Container -Breadcrumb 'Search Results'

    # --- Chocolatey pane (left) ---
    $chocoFrame = [Terminal.Gui.FrameView]::new("Chocolatey ($($script:ChocoSearchResults.Count))")
    $chocoFrame.X = 0; $chocoFrame.Y = 2
    $chocoFrame.Width = [Terminal.Gui.Dim]::Percent(50)
    $chocoFrame.Height = [Terminal.Gui.Dim]::Fill(3)

    $chocoStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $script:ChocoSearchResults) {
        $chocoStrings.Add(" $($r.Name)  $($r.Version)")
    }
    if ($chocoStrings.Count -eq 0) { $chocoStrings.Add(" (no results)") }

    $chocoList = [Terminal.Gui.ListView]::new($chocoStrings)
    $chocoList.X = 0; $chocoList.Y = 0
    $chocoList.Width = [Terminal.Gui.Dim]::Fill(); $chocoList.Height = [Terminal.Gui.Dim]::Fill()
    $chocoList.AllowsMarking = $false
    if ($script:Colors.Menu) { $chocoList.ColorScheme = $script:Colors.Menu }

    $chocoList.add_OpenSelectedItem({
        param($e)
        if ($script:ChocoSearchResults.Count -gt 0 -and $e.Item -lt $script:ChocoSearchResults.Count) {
            $sel = $script:ChocoSearchResults[$e.Item]
            $script:WizardData.DisplayName    = $sel.Name
            $script:WizardData.PackageManager = 'choco'
            $script:WizardData.PackageId      = $sel.PackageId
            $script:WizardData.VerifyCommand  = $sel.Name.ToLower()
            $script:WizardStep = 'ReviewFields'
            Switch-Screen -ScreenName 'AddTool'
        }
    })
    $chocoFrame.Add($chocoList)
    $Container.Add($chocoFrame)

    # --- Winget pane (right) ---
    $wingetFrame = [Terminal.Gui.FrameView]::new("Winget ($($script:WingetSearchResults.Count))")
    $wingetFrame.X = [Terminal.Gui.Pos]::Percent(50); $wingetFrame.Y = 2
    $wingetFrame.Width = [Terminal.Gui.Dim]::Fill()
    $wingetFrame.Height = [Terminal.Gui.Dim]::Fill(3)

    $wingetStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $script:WingetSearchResults) {
        $wingetStrings.Add(" $($r.Name)  $($r.Version)")
    }
    if ($wingetStrings.Count -eq 0) { $wingetStrings.Add(" (no results)") }

    $wingetList = [Terminal.Gui.ListView]::new($wingetStrings)
    $wingetList.X = 0; $wingetList.Y = 0
    $wingetList.Width = [Terminal.Gui.Dim]::Fill(); $wingetList.Height = [Terminal.Gui.Dim]::Fill()
    $wingetList.AllowsMarking = $false
    if ($script:Colors.Menu) { $wingetList.ColorScheme = $script:Colors.Menu }

    $wingetList.add_OpenSelectedItem({
        param($e)
        if ($script:WingetSearchResults.Count -gt 0 -and $e.Item -lt $script:WingetSearchResults.Count) {
            $sel = $script:WingetSearchResults[$e.Item]
            $script:WizardData.DisplayName    = $sel.Name
            $script:WizardData.PackageManager = 'winget'
            $script:WizardData.PackageId      = $sel.PackageId
            $script:WizardData.VerifyCommand  = $sel.Name.ToLower() -replace '\s.*', ''
            $script:WizardStep = 'ReviewFields'
            Switch-Screen -ScreenName 'AddTool'
        }
    })
    $wingetFrame.Add($wingetList)
    $Container.Add($wingetFrame)

    Add-WizardHint -Container $Container -Y ([Terminal.Gui.Pos]::AnchorEnd(2)) `
        -Text "Tab to switch panes, Enter to select, Escape to go back"

    $script:Layout.MenuList = $chocoList
    $chocoList.SetFocus()
}

# ---------------------------------------------------------------------------
# Review auto-populated fields (after search)
# ---------------------------------------------------------------------------

function Build-WizardReviewFields {
    param($Container)

    Add-WizardHeader -Container $Container -Breadcrumb 'Review'

    $y = 2
    $fields = @(
        @{ Label = 'Display name';    Value = $script:WizardData.DisplayName }
        @{ Label = 'Package manager'; Value = $script:WizardData.PackageManager }
        @{ Label = 'Package ID';      Value = $script:WizardData.PackageId }
        @{ Label = 'Verify command';  Value = $script:WizardData.VerifyCommand }
        @{ Label = 'Profile alias';   Value = if ($script:WizardData.ProfileAlias) { $script:WizardData.ProfileAlias } else { '(none)' } }
        @{ Label = 'Update override'; Value = if ($script:WizardData.UpdateOverride) { $script:WizardData.UpdateOverride } else { '(none)' } }
    )

    foreach ($f in $fields) {
        $lbl = [Terminal.Gui.Label]::new("  $($f.Label.PadRight(20)) $($f.Value)")
        $lbl.X = 0; $lbl.Y = $y; $lbl.Width = [Terminal.Gui.Dim]::Fill()
        $Container.Add($lbl)
        $y++
    }

    $actions = [System.Collections.Generic.List[string]]::new()
    $actions.Add("  Continue to preview")
    $actions.Add("  Edit fields")

    $actionList = [Terminal.Gui.ListView]::new($actions)
    $actionList.X = 2; $actionList.Y = $y + 1
    $actionList.Width = [Terminal.Gui.Dim]::Fill(2); $actionList.Height = 2
    $actionList.AllowsMarking = $false
    if ($script:Colors.Menu) { $actionList.ColorScheme = $script:Colors.Menu }

    $actionList.add_OpenSelectedItem({
        param($e)
        if ($e.Item -eq 0) {
            $script:WizardStep = 'Confirmation'
        } else {
            $script:WizardStep = 'GuidedName'
            $script:WizardData.Path = 'Guided'
        }
        Switch-Screen -ScreenName 'AddTool'
    })

    $actionList.add_KeyPress({
        param($e)
        if ($e.KeyEvent.Key -eq [Terminal.Gui.Key]::Esc) {
            Step-WizardBack
            $e.Handled = $true
        }
    })

    Add-WizardHint -Container $Container -Y ($y + 4) -Text "Enter to continue, Escape to go back"

    $Container.Add($actionList)
    $script:Layout.MenuList = $actionList
    $actionList.SetFocus()
}

# ---------------------------------------------------------------------------
# Path B: Guided wizard (generic step builder)
# ---------------------------------------------------------------------------

function Build-WizardGuidedStep {
    <#
    .SYNOPSIS
        Builds a single step of the guided wizard.
    .PARAMETER Container
        Parent view.
    .PARAMETER StepIndex
        Zero-based index into $script:GuidedSteps.
    #>
    param($Container, [int]$StepIndex)

    $step = $script:GuidedSteps[$StepIndex]
    $stepNum = $StepIndex + 1
    $totalSteps = $script:GuidedSteps.Count

    Add-WizardHeader -Container $Container -Breadcrumb "Step $stepNum of $totalSteps"

    $titleLabel = [Terminal.Gui.Label]::new("  $($step.Title)")
    $titleLabel.X = 0; $titleLabel.Y = 2; $titleLabel.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $titleLabel.ColorScheme = $script:Colors.Header }
    $Container.Add($titleLabel)

    $descLabel = [Terminal.Gui.Label]::new("  $($step.Desc)")
    $descLabel.X = 0; $descLabel.Y = 3; $descLabel.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($descLabel)

    # $step is function-local and resolves to $null in .NET event handlers.
    # Stored as $script:_CurrentStep before registering OpenSelectedItem.
    # Also used by the guided text handler (Bug 3) for the same reason.
    $script:_CurrentStep = $step

    if ($step.Type -eq 'select') {
        # Selection list
        $optStrings = [System.Collections.Generic.List[string]]::new()
        foreach ($o in $step.Options) { $optStrings.Add("  $o") }

        $selList = [Terminal.Gui.ListView]::new($optStrings)
        $selList.X = 4; $selList.Y = 5
        $selList.Width = [Terminal.Gui.Dim]::Fill(4)
        $selList.Height = $step.Options.Count
        $selList.AllowsMarking = $false
        if ($script:Colors.Menu) { $selList.ColorScheme = $script:Colors.Menu }

        # Pre-select current value
        $currentVal = $script:WizardData[$step.Key]
        if ($currentVal) {
            $idx = $step.Options.IndexOf($currentVal)
            if ($idx -ge 0) { $selList.SelectedItem = $idx }
        }

        $selList.add_OpenSelectedItem({
            param($e)
            $script:WizardData[$script:_CurrentStep.Key] = $script:_CurrentStep.Options[$e.Item]
            $script:WizardStep = $script:_CurrentStep.Next
            Switch-Screen -ScreenName 'AddTool'
        })

        $selList.add_KeyPress({
            param($e)
            if ($e.KeyEvent.Key -eq [Terminal.Gui.Key]::Esc) {
                Step-WizardBack
                $e.Handled = $true
            }
        })

        $Container.Add($selList)
        $script:Layout.MenuList = $selList
        $selList.SetFocus()

    } else {
        # $tf is function-local and resolves to $null in .NET event handlers.
        # Stored as $script:_GuidedInput before registering the KeyPress handler.
        # $step is read via $script:_CurrentStep (same fix applied in Bug 2).
        $currentVal = $script:WizardData[$step.Key]
        $script:_GuidedInput = [Terminal.Gui.TextField]::new($(if ($currentVal) { $currentVal } else { '' }))
        $script:_GuidedInput.X = 4; $script:_GuidedInput.Y = 5
        $script:_GuidedInput.Width = [Terminal.Gui.Dim]::Fill(4); $script:_GuidedInput.Height = 1
        if ($script:Colors.CommandBar) { $script:_GuidedInput.ColorScheme = $script:Colors.CommandBar }

        $script:_GuidedInput.add_KeyPress({
            param($e)
            if ($e.KeyEvent.Key -eq [Terminal.Gui.Key]::Enter) {
                $val = $script:_GuidedInput.Text.ToString().Trim()
                if ($script:_CurrentStep.Required -and [string]::IsNullOrWhiteSpace($val)) {
                    # Don't advance if required and empty
                    $e.Handled = $true
                    return
                }
                $script:WizardData[$script:_CurrentStep.Key] = $val
                $script:WizardStep = $script:_CurrentStep.Next
                Switch-Screen -ScreenName 'AddTool'
                $e.Handled = $true
            }
            if ($e.KeyEvent.Key -eq [Terminal.Gui.Key]::Esc) {
                Step-WizardBack
                $e.Handled = $true
            }
        })

        $optionalHint = if (-not $step.Required) { ' (press Enter to skip)' } else { '' }
        Add-WizardHint -Container $Container -Y 7 `
            -Text "Enter to continue${optionalHint}, Escape to go back"

        $Container.Add($script:_GuidedInput)
        $script:Layout.MenuList = $null
        $script:_GuidedInput.SetFocus()
    }
}

# ---------------------------------------------------------------------------
# Confirmation screen
# ---------------------------------------------------------------------------

function Build-WizardConfirmation {
    param($Container)

    Add-WizardHeader -Container $Container -Breadcrumb 'Confirmation'

    # Generate diff preview
    $diffText = Get-ToolDiffPreview -ToolData $script:WizardData

    $tv = [Terminal.Gui.TextView]::new()
    $tv.X = 1; $tv.Y = 2
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

function Invoke-WizardConfirm {
    <#
    .SYNOPSIS
        Executes the atomic write and shows the result.
    #>
    $result = Write-ToolChanges -ToolData $script:WizardData

    if ($result.Success) {
        $fileCount = $result.FilesWritten.Count
        $msg = "Tool '$($script:WizardData.DisplayName)' added successfully ($fileCount files written)."

        $okBtn = [Terminal.Gui.Button]::new("_OK")
        $okBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })
        $dialog = [Terminal.Gui.Dialog]::new("Success", 50, 8, [Terminal.Gui.Button[]]@($okBtn))
        $lbl = [Terminal.Gui.Label]::new(" $msg")
        $lbl.X = 1; $lbl.Y = 1; $lbl.Width = [Terminal.Gui.Dim]::Fill(1)
        $dialog.Add($lbl)
        [Terminal.Gui.Application]::Run($dialog)

        Reset-WizardState
        Switch-Screen -ScreenName 'Home'
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
