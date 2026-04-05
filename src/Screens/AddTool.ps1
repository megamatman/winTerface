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
    Path           = ''   # 'Search' | 'Guided'
}

# Background search jobs
$script:ChocoSearchJob      = $null
$script:WingetSearchJob     = $null
$script:PyPISearchJob       = $null
$script:ChocoSearchResults  = @()
$script:WingetSearchResults = @()
$script:PyPISearchResults   = @()

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
        Cancels any running package search jobs.
    #>
    foreach ($jobVar in @('ChocoSearchJob', 'WingetSearchJob', 'PyPISearchJob')) {
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

    # Dynamic description label -- updates when the highlighted option changes.
    # Stored at $script: scope so the SelectedItemChanged handler can update it.
    # Description uses Base colour (white text, no highlight) to appear
    # subordinate to the Menu-coloured option list which highlights on focus.
    $script:_ChoosePathDesc = [Terminal.Gui.Label]::new("")
    $script:_ChoosePathDesc.X = 4; $script:_ChoosePathDesc.Y = 7
    $script:_ChoosePathDesc.Width = [Terminal.Gui.Dim]::Fill(4); $script:_ChoosePathDesc.Height = 2
    if ($script:Colors.Base) { $script:_ChoosePathDesc.ColorScheme = $script:Colors.Base }
    $Container.Add($script:_ChoosePathDesc)

    $script:_ChoosePathDescriptions = @(
        "Search choco, winget, and PyPI to find and register a tool`nautomatically. Best for well-known CLI tools."
        "Provide the tool name, package ID, and profile settings yourself.`nBest for tools not in package manager search."
    )
    # Show description for the initially selected item
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
# Path A: Package search
# ---------------------------------------------------------------------------

function Build-WizardSearchInput {
    <#
    .SYNOPSIS
        Builds the search input step where the user types a tool name.
    .DESCRIPTION
        Displays a text field for entering a package search term. Enter
        launches concurrent choco and winget search jobs.
    #>
    param($Container)

    Add-WizardHeader -Container $Container -Breadcrumb 'Search'

    $context = [Terminal.Gui.Label]::new("  Enter a search term to find the tool across package managers.")
    $context.X = 0; $context.Y = 2; $context.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($context)

    $src1 = [Terminal.Gui.Label]::new("    Chocolatey   Windows system tools and CLI utilities")
    $src1.X = 0; $src1.Y = 4; $src1.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($src1)
    $src2 = [Terminal.Gui.Label]::new("    Winget       Windows apps and developer tools")
    $src2.X = 0; $src2.Y = 5; $src2.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($src2)
    $src3 = [Terminal.Gui.Label]::new("    PyPI         Python CLI tools via pipx (exact package name)")
    $src3.X = 0; $src3.Y = 6; $src3.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($src3)

    # $tf is function-local and resolves to $null in .NET event handlers.
    # Stored as $script:_SearchInput before registering the KeyPress handler.
    # See CONTRIBUTING.md -- dialog input fields must use $script: scope.
    $searchFrame = [Terminal.Gui.FrameView]::new("Search")
    $searchFrame.X = 2; $searchFrame.Y = 8
    $searchFrame.Width = [Terminal.Gui.Dim]::Fill(2); $searchFrame.Height = 3
    if ($script:Colors.Base) { $searchFrame.ColorScheme = $script:Colors.Base }

    $script:_SearchInput = [Terminal.Gui.TextField]::new("")
    $script:_SearchInput.X = 0; $script:_SearchInput.Y = 0
    $script:_SearchInput.Width = [Terminal.Gui.Dim]::Fill(); $script:_SearchInput.Height = 1
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

    $searchFrame.Add($script:_SearchInput)
    Add-WizardHint -Container $Container -Y 11 -Text "Enter to search, Escape to go back"

    $Container.Add($searchFrame)
    $script:Layout.MenuList = $null
    $script:_SearchInput.SetFocus()
}

function Start-WizardSearch {
    <#
    .SYNOPSIS
        Launches concurrent choco, winget, and PyPI search jobs.
    .PARAMETER SearchTerm
        The text to search for.
    #>
    param([string]$SearchTerm)

    $pkgMgrScript = Join-Path $script:WinTerfaceRoot 'src' 'Services' 'PackageManager.ps1'

    $script:ChocoSearchJob = Start-Job -ScriptBlock {
        param($sp, $term)
        try {
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                        ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH', 'User')
            . $sp
            Search-ChocolateyPackage -Name $term
        } catch {
            Write-Error "Job failed: $_"
        }
    } -ArgumentList $pkgMgrScript, $SearchTerm

    $script:WingetSearchJob = Start-Job -ScriptBlock {
        param($sp, $term)
        try {
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                        ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH', 'User')
            . $sp
            Search-WingetPackage -Name $term
        } catch {
            Write-Error "Job failed: $_"
        }
    } -ArgumentList $pkgMgrScript, $SearchTerm

    $script:PyPISearchJob = Start-Job -ScriptBlock {
        param($sp, $term)
        try {
            . $sp
            Search-PyPI -Term $term
        } catch {
            Write-Error "Job failed: $_"
        }
    } -ArgumentList $pkgMgrScript, $SearchTerm

    $script:WizardStep = 'Searching'
    Switch-Screen -ScreenName 'AddTool'
}

function Build-WizardSearching {
    <#
    .SYNOPSIS
        Builds the in-progress screen shown while search jobs are running.
    .DESCRIPTION
        Displays status labels for the choco, winget, and PyPI search jobs.
        The 500ms timer advances to SearchResults when all three complete.
    #>
    param($Container)

    Add-WizardHeader -Container $Container -Breadcrumb 'Search'

    $status = [Terminal.Gui.Label]::new("  Searching...")
    $status.X = 0; $status.Y = 2; $status.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $status.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($status)

    $chocoState  = if ($script:ChocoSearchJob)  { 'searching...' } else { 'done' }
    $wingetState = if ($script:WingetSearchJob) { 'searching...' } else { 'done' }
    $pypiState   = if ($script:PyPISearchJob)   { 'searching...' } else { 'done' }

    $c1 = [Terminal.Gui.Label]::new("  Chocolatey   $chocoState")
    $c1.X = 0; $c1.Y = 4; $c1.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($c1)

    $c2 = [Terminal.Gui.Label]::new("  Winget       $wingetState")
    $c2.X = 0; $c2.Y = 5; $c2.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($c2)

    $c3 = [Terminal.Gui.Label]::new("  PyPI         $pypiState")
    $c3.X = 0; $c3.Y = 6; $c3.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($c3)

    Add-WizardHint -Container $Container -Y 8 -Text "Escape to cancel"
}

function Update-SearchJobStatus {
    <#
    .SYNOPSIS
        Polls the search background jobs.  Called by the 500 ms timer.
    #>
    if (-not $script:ChocoSearchJob -and -not $script:WingetSearchJob -and -not $script:PyPISearchJob) { return }

    $allDone = $true

    if ($script:ChocoSearchJob) {
        if ($script:ChocoSearchJob.State -ne 'Running') {
            try { $script:ChocoSearchResults = @(Receive-Job $script:ChocoSearchJob -ErrorAction SilentlyContinue) }
            catch { $script:ChocoSearchResults = @() }
            try { Remove-Job $script:ChocoSearchJob -Force } catch {}
            $script:ChocoSearchJob = $null
        } else { $allDone = $false }
    }

    if ($script:WingetSearchJob) {
        if ($script:WingetSearchJob.State -ne 'Running') {
            try { $script:WingetSearchResults = @(Receive-Job $script:WingetSearchJob -ErrorAction SilentlyContinue) }
            catch { $script:WingetSearchResults = @() }
            try { Remove-Job $script:WingetSearchJob -Force } catch {}
            $script:WingetSearchJob = $null
        } else { $allDone = $false }
    }

    if ($script:PyPISearchJob) {
        if ($script:PyPISearchJob.State -ne 'Running') {
            try { $script:PyPISearchResults = @(Receive-Job $script:PyPISearchJob -ErrorAction SilentlyContinue) }
            catch { $script:PyPISearchResults = @() }
            try { Remove-Job $script:PyPISearchJob -Force } catch {}
            $script:PyPISearchJob = $null
        } else { $allDone = $false }
    }

    if ($allDone -and $script:WizardStep -eq 'Searching') {
        $script:WizardStep = 'SearchResults'
        Switch-Screen -ScreenName 'AddTool'
    }
}

# ---------------------------------------------------------------------------
# Search results helpers
# ---------------------------------------------------------------------------

# $script: references for search result section ListViews (closure safety)
$script:_SearchLists     = @()   # ordered array: choco, winget, pypi ListViews
$script:_SearchResults   = @()   # ordered array: choco, winget, pypi result arrays
$script:_SearchManagers  = @()   # ordered array: 'choco', 'winget', 'pipx'
$script:_ResultDescView  = $null # description panel TextView

function Add-SearchResultSection {
    <#
    .SYNOPSIS
        Builds one search result section (FrameView + ListView) and adds it to the container.
    .DESCRIPTION
        Creates a framed ListView for a single package manager source. Wires
        OpenSelectedItem to populate WizardData and advance the wizard. Wires
        SelectedItemChanged to update the description panel. Returns the ListView.
    .PARAMETER Container
        Parent view.
    .PARAMETER Title
        FrameView title (e.g. "Chocolatey (5)").
    .PARAMETER Results
        Array of result hashtables from the search.
    .PARAMETER Manager
        Package manager identifier: 'choco', 'winget', or 'pipx'.
    .PARAMETER Y
        Y position for the FrameView.
    .PARAMETER SectionHeight
        Total height of the FrameView (ListView rows + 2 for borders).
    .PARAMETER ListIndex
        Index of this list in $script:_SearchLists (for Tab navigation).
    #>
    param($Container, [string]$Title, [array]$Results, [string]$Manager, [int]$Y, [int]$SectionHeight, [int]$ListIndex)

    $frame = [Terminal.Gui.FrameView]::new($Title)
    $frame.X = 0; $frame.Y = $Y
    $frame.Width = [Terminal.Gui.Dim]::Fill(); $frame.Height = $SectionHeight
    if ($script:Colors.Base) { $frame.ColorScheme = $script:Colors.Base }

    $listStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $Results) {
        $name = "$($r.Name)".PadRight(30)
        $ver  = "$($r.Version)"
        $listStrings.Add(" $name $ver")
    }
    if ($listStrings.Count -eq 0) { $listStrings.Add(" (no results)") }

    $listView = [Terminal.Gui.ListView]::new($listStrings)
    $listView.X = 0; $listView.Y = 0
    $listView.Width = [Terminal.Gui.Dim]::Fill(); $listView.Height = [Terminal.Gui.Dim]::Fill()
    $listView.AllowsMarking = $false
    if ($script:Colors.Menu) { $listView.ColorScheme = $script:Colors.Menu }

    # Helper: find this list's index at event time (avoids closure over $ListIndex)
    # Uses reference equality against the $script:_SearchLists array.

    # Selection handler -- populate WizardData and advance
    $listView.add_OpenSelectedItem({
        param($e)
        # Determine which list fired by finding the focused list in the array
        $li = -1
        for ($i = 0; $i -lt $script:_SearchLists.Count; $i++) {
            if ($script:_SearchLists[$i] -eq $e.Source -or
                $script:_SearchLists[$i].HasFocus) { $li = $i; break }
        }
        if ($li -lt 0) { return }
        $mgr     = $script:_SearchManagers[$li]
        $results = $script:_SearchResults[$li]
        if ($results.Count -gt 0 -and $e.Item -lt $results.Count) {
            $sel = $results[$e.Item]
            $script:WizardData.DisplayName    = $sel.Name
            $script:WizardData.PackageManager = $mgr
            $script:WizardData.PackageId      = if ($sel.PackageId) { $sel.PackageId } else { $sel.Id }
            $script:WizardData.VerifyCommand  = ($sel.Name.ToLower() -replace '\s.*', '')
            $script:WizardStep = 'ReviewFields'
            Switch-Screen -ScreenName 'AddTool'
        }
    })

    # Highlight change -- update description panel
    $listView.add_SelectedItemChanged({
        param($e)
        if (-not $script:_ResultDescView) { return }
        $li = -1
        for ($i = 0; $i -lt $script:_SearchLists.Count; $i++) {
            if ($script:_SearchLists[$i].HasFocus) { $li = $i; break }
        }
        if ($li -lt 0) { return }
        $results = $script:_SearchResults[$li]
        $lv = $script:_SearchLists[$li]
        if (-not $lv) { return }
        $idx = $lv.SelectedItem
        if ($results.Count -gt 0 -and $idx -ge 0 -and $idx -lt $results.Count) {
            $desc = $results[$idx].Description
            $script:_ResultDescView.Text = if ($desc) { $desc } else { 'No description available.' }
        } else {
            $script:_ResultDescView.Text = ''
        }
        try { $script:_ResultDescView.SetNeedsDisplay() } catch {}
    })

    # Tab / Shift+Tab navigation between sections; Escape goes back
    $listView.add_KeyPress({
        param($e)
        $key = $e.KeyEvent.Key
        if ($key -eq [Terminal.Gui.Key]::Tab) {
            $li = -1
            for ($i = 0; $i -lt $script:_SearchLists.Count; $i++) {
                if ($script:_SearchLists[$i].HasFocus) { $li = $i; break }
            }
            if ($li -ge 0) {
                $nextIdx = ($li + 1) % $script:_SearchLists.Count
                $script:_SearchLists[$nextIdx].SetFocus()
            }
            $e.Handled = $true; return
        }
        if ($key -eq [Terminal.Gui.Key]::BackTab) {
            $li = -1
            for ($i = 0; $i -lt $script:_SearchLists.Count; $i++) {
                if ($script:_SearchLists[$i].HasFocus) { $li = $i; break }
            }
            if ($li -ge 0) {
                $prevIdx = ($li - 1 + $script:_SearchLists.Count) % $script:_SearchLists.Count
                $script:_SearchLists[$prevIdx].SetFocus()
            }
            $e.Handled = $true; return
        }
        if ($key -eq [Terminal.Gui.Key]::Esc) {
            Step-WizardBack
            $e.Handled = $true
        }
    })

    $frame.Add($listView)
    $Container.Add($frame)
    return $listView
}

function Add-SearchResultDescriptionPanel {
    <#
    .SYNOPSIS
        Adds the description panel below the search result sections.
    .DESCRIPTION
        Creates a framed read-only TextView for showing the description of
        the currently highlighted search result. Stores a reference in
        $script:_ResultDescView for handlers to update.
    .PARAMETER Container
        Parent view.
    .PARAMETER Y
        Y position for the FrameView.
    .PARAMETER Height
        Total height of the FrameView.
    #>
    param($Container, [int]$Y, [int]$Height)

    $frame = [Terminal.Gui.FrameView]::new("Description")
    $frame.X = 0; $frame.Y = $Y
    $frame.Width = [Terminal.Gui.Dim]::Fill(); $frame.Height = $Height
    if ($script:Colors.Base) { $frame.ColorScheme = $script:Colors.Base }

    $tv = [Terminal.Gui.TextView]::new()
    $tv.X = 0; $tv.Y = 0
    $tv.Width = [Terminal.Gui.Dim]::Fill(); $tv.Height = [Terminal.Gui.Dim]::Fill()
    $tv.ReadOnly = $true
    $tv.WordWrap = $true
    if ($script:Colors.Base) { $tv.ColorScheme = $script:Colors.Base }

    $frame.Add($tv)
    $Container.Add($frame)
    $script:_ResultDescView = $tv
}

function Build-WizardSearchResults {
    <#
    .SYNOPSIS
        Builds the three-section search results view with description panel.
    .DESCRIPTION
        Displays choco, winget, and PyPI results in vertically stacked
        sections. Tab moves focus between sections. Enter selects a result
        and advances to ReviewFields. A description panel shows detail for
        the highlighted item.
    #>
    param($Container)

    # Section layout constants
    $listRows      = 4     # visible rows per ListView
    $sectionHeight = $listRows + 2  # +2 for FrameView borders
    $descHeight    = 5     # description panel FrameView height
    $section1Y     = 2     # below header (Y=0) and context (Y=1)
    $section2Y     = $section1Y + $sectionHeight
    $section3Y     = $section2Y + $sectionHeight
    $descY         = $section3Y + $sectionHeight
    $hintY         = $descY + $descHeight

    Add-WizardHeader -Container $Container -Breadcrumb 'Search Results'

    $context = [Terminal.Gui.Label]::new("  Select a result to use as the basis for this tool.")
    $context.X = 0; $context.Y = 1; $context.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($context)

    # Prepare result arrays and managers for $script: scope
    $script:_SearchResults  = @($script:ChocoSearchResults, $script:WingetSearchResults, $script:PyPISearchResults)
    $script:_SearchManagers = @('choco', 'winget', 'pipx')

    # Description panel (must exist before sections wire SelectedItemChanged)
    Add-SearchResultDescriptionPanel -Container $Container -Y $descY -Height $descHeight

    # Build sections
    $chocoList = Add-SearchResultSection -Container $Container `
        -Title "Chocolatey ($($script:ChocoSearchResults.Count))" `
        -Results $script:ChocoSearchResults -Manager 'choco' `
        -Y $section1Y -SectionHeight $sectionHeight -ListIndex 0

    $wingetList = Add-SearchResultSection -Container $Container `
        -Title "Winget ($($script:WingetSearchResults.Count))" `
        -Results $script:WingetSearchResults -Manager 'winget' `
        -Y $section2Y -SectionHeight $sectionHeight -ListIndex 1

    $pypiList = Add-SearchResultSection -Container $Container `
        -Title "PyPI - exact name ($($script:PyPISearchResults.Count))" `
        -Results $script:PyPISearchResults -Manager 'pipx' `
        -Y $section3Y -SectionHeight $sectionHeight -ListIndex 2

    # Store list references for Tab navigation and closure access
    $script:_SearchLists = @($chocoList, $wingetList, $pypiList)

    Add-WizardHint -Container $Container -Y $hintY `
        -Text "Tab: next source  Enter: select  Escape: back"

    # Set initial focus and description
    $script:Layout.MenuList = $chocoList
    $chocoList.SetFocus()

    # Show description for first choco result if available
    if ($script:ChocoSearchResults.Count -gt 0 -and $script:ChocoSearchResults[0].Description) {
        $script:_ResultDescView.Text = $script:ChocoSearchResults[0].Description
    } elseif ($script:ChocoSearchResults.Count -gt 0) {
        $script:_ResultDescView.Text = 'No description available.'
    }
}

# ---------------------------------------------------------------------------
# Review auto-populated fields (after search)
# ---------------------------------------------------------------------------

function Build-WizardReviewFields {
    <#
    .SYNOPSIS
        Builds the field review screen shown after a search selection.
    .DESCRIPTION
        Displays auto-populated fields from the search result. The user can
        continue to the diff preview or switch to guided editing.
    #>
    param($Container)

    Add-WizardHeader -Container $Container -Breadcrumb 'Review'

    $context = [Terminal.Gui.Label]::new("  Review and edit the tool details before registering.")
    $context.X = 0; $context.Y = 1; $context.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($context)

    $y = 3
    $fields = @(
        @{ Label = 'Display name';    Value = $script:WizardData.DisplayName }
        @{ Label = 'Package manager'; Value = $script:WizardData.PackageManager }
        @{ Label = 'Package ID';      Value = $script:WizardData.PackageId }
        @{ Label = 'Verify command';  Value = $script:WizardData.VerifyCommand }
        @{ Label = 'Profile alias';   Value = if ($script:WizardData.ProfileAlias) { $script:WizardData.ProfileAlias } else { '(none)' } }
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
    # Also used by the guided text KeyPress handler for the same reason.
    $script:_CurrentStep = $step

    if ($step.Type -eq 'select') {
        Add-GuidedSelectInput -Container $Container -Step $step
    } else {
        Add-GuidedTextInput -Container $Container -Step $step
    }
}

function Add-GuidedSelectInput {
    <#
    .SYNOPSIS
        Builds the selection list branch of a guided wizard step.
    #>
    param($Container, $Step)

    $optStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($o in $Step.Options) { $optStrings.Add("  $o") }

    $selList = [Terminal.Gui.ListView]::new($optStrings)
    $selList.X = 4; $selList.Y = 5
    $selList.Width = [Terminal.Gui.Dim]::Fill(4)
    $selList.Height = $Step.Options.Count
    $selList.AllowsMarking = $false
    if ($script:Colors.Menu) { $selList.ColorScheme = $script:Colors.Menu }

    $currentVal = $script:WizardData[$Step.Key]
    if ($currentVal) {
        $idx = $Step.Options.IndexOf($currentVal)
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
}

function Add-GuidedTextInput {
    <#
    .SYNOPSIS
        Builds the text input branch of a guided wizard step.
    #>
    param($Container, $Step)

    # $tf and $step are function-local and resolve to $null in .NET event
    # handlers. Stored as $script:_GuidedInput and $script:_CurrentStep.
    $currentVal = $script:WizardData[$Step.Key]
    $script:_GuidedInput = [Terminal.Gui.TextField]::new($(if ($currentVal) { $currentVal } else { '' }))
    $script:_GuidedInput.X = 4; $script:_GuidedInput.Y = 5
    $script:_GuidedInput.Width = [Terminal.Gui.Dim]::Fill(4); $script:_GuidedInput.Height = 1
    if ($script:Colors.CommandBar) { $script:_GuidedInput.ColorScheme = $script:Colors.CommandBar }

    $script:_GuidedInput.add_KeyPress({
        param($e)
        if ($e.KeyEvent.Key -eq [Terminal.Gui.Key]::Enter) {
            $val = $script:_GuidedInput.Text.ToString().Trim()
            if ($script:_CurrentStep.Required -and [string]::IsNullOrWhiteSpace($val)) {
                $e.Handled = $true
                return
            }
            # Validate against field-specific allowlist to prevent code injection
            if ($val -and $script:_CurrentStep.AllowedPattern -and
                $val -notmatch $script:_CurrentStep.AllowedPattern) {
                # Show inline error -- do not advance
                $script:_GuidedInput.Text = ''
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

    $optionalHint = if (-not $Step.Required) { ' (press Enter to skip)' } else { '' }
    Add-WizardHint -Container $Container -Y 7 `
        -Text "Enter to continue${optionalHint}, Escape to go back"

    $Container.Add($script:_GuidedInput)
    $script:Layout.MenuList = $null
    $script:_GuidedInput.SetFocus()
}

# ---------------------------------------------------------------------------
# Confirmation screen
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
    #>
    try {
        $wtWinSetup = Join-Path $script:WinTerfaceRoot 'src' 'Services' 'WinSetup.ps1'
        if (-not (Test-Path $wtWinSetup)) { return }

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
    } catch {}
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
        Save-NewToolRegistration
        $fileCount = $result.FilesWritten.Count
        $toolName  = $script:WizardData.DisplayName

        # Ask whether to install the tool now
        $script:_InstallNow = $false
        $installBtn = [Terminal.Gui.Button]::new("_Install now")
        $laterBtn   = [Terminal.Gui.Button]::new("_Later")
        $dialog = [Terminal.Gui.Dialog]::new("Tool registered", 54, 9,
            [Terminal.Gui.Button[]]@($installBtn, $laterBtn))
        $lbl = [Terminal.Gui.Label]::new(
            " '$toolName' registered ($fileCount files written).`n`n Install it now?")
        $lbl.X = 1; $lbl.Y = 1; $lbl.Width = [Terminal.Gui.Dim]::Fill(1); $lbl.Height = 3
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
                        Write-Host "[job] Running: & '$scriptPath' -InstallTool '$name'"
                        & $scriptPath -InstallTool $name 2>&1
                        Write-Host "[job] Exit code: $LASTEXITCODE"
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
