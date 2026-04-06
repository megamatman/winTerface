# AddTool-Search.ps1 - Search wizard path: search job management, result
#                      section building, description fetching, field review

# ---------------------------------------------------------------------------
# Search result state (closure-safe $script: references)
# ---------------------------------------------------------------------------

$script:_SearchLists     = @()   # ordered array: choco, winget, pypi ListViews
$script:_SearchResults   = @()   # ordered array: choco, winget, pypi result arrays
$script:_SearchManagers  = @()   # ordered array: 'choco', 'winget', 'pipx'
$script:_ResultDescView  = $null # description panel TextView

# ---------------------------------------------------------------------------
# Search input
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

# ---------------------------------------------------------------------------
# Search job management
# ---------------------------------------------------------------------------

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
# Description fetch
# ---------------------------------------------------------------------------

function Invoke-DescriptionFetch {
    <#
    .SYNOPSIS
        Shows or fetches a description for a search result item.
    .DESCRIPTION
        If the item already has a Description (PyPI results or previously
        cached), shows it immediately. Otherwise launches a background job
        to fetch from choco or winget. Cancels any in-flight fetch first.
        Called by SelectedItemChanged handlers and by Tab navigation to
        populate the description panel for the first item in a section.
    .PARAMETER ListIndex
        Index into $script:_SearchResults / $script:_SearchManagers.
    .PARAMETER ItemIndex
        Index of the item within the result array.
    #>
    param([int]$ListIndex, [int]$ItemIndex)

    if (-not $script:_ResultDescView) { return }
    if ($ListIndex -lt 0 -or $ListIndex -ge $script:_SearchResults.Count) { return }

    $results = $script:_SearchResults[$ListIndex]
    if (-not $results -or $ItemIndex -lt 0 -or $ItemIndex -ge $results.Count) {
        $script:_ResultDescView.Text = ''
        try { $script:_ResultDescView.SetNeedsDisplay() } catch {}
        return
    }

    $item = $results[$ItemIndex]

    # Already have a description (PyPI or previously cached)
    if ($item.Description) {
        $script:_ResultDescView.Text = $item.Description
        try { $script:_ResultDescView.SetNeedsDisplay() } catch {}
        return
    }

    # Cancel any in-flight description fetch
    if ($script:DescriptionJob) {
        try { Stop-Job $script:DescriptionJob -ErrorAction SilentlyContinue } catch {}
        try { Remove-Job $script:DescriptionJob -Force -ErrorAction SilentlyContinue } catch {}
        $script:DescriptionJob = $null
    }

    $mgr = $script:_SearchManagers[$ListIndex]
    $pkgId = if ($item.PackageId) { $item.PackageId } else { $item.Id }

    if ($mgr -eq 'choco' -or $mgr -eq 'winget') {
        $script:_ResultDescView.Text = 'Fetching description...'
        try { $script:_ResultDescView.SetNeedsDisplay() } catch {}

        $script:_DescriptionResult = @{ ListIndex = $ListIndex; ItemIndex = $ItemIndex }
        $pkgMgrScript = Join-Path $script:WinTerfaceRoot 'src' 'Services' 'PackageManager.ps1'
        $script:DescriptionJob = Start-Job -ScriptBlock {
            param($sp, $manager, $packageId)
            try {
                $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                            ';' +
                            [System.Environment]::GetEnvironmentVariable('PATH', 'User')
                . $sp
                if ($manager -eq 'choco') {
                    Get-ChocoPackageDescription -Id $packageId
                } else {
                    Get-WingetPackageDescription -Id $packageId
                }
            } catch {
                Write-Error "Job failed: $_"
            }
        } -ArgumentList $pkgMgrScript, $mgr, $pkgId
    } else {
        $script:_ResultDescView.Text = 'No description available.'
        try { $script:_ResultDescView.SetNeedsDisplay() } catch {}
    }
}

# ---------------------------------------------------------------------------
# Search result sections
# ---------------------------------------------------------------------------

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

    # Selection handler -- populate WizardData and advance
    $listView.add_OpenSelectedItem({
        param($e)
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
            $pkgId = if ($sel.PackageId) { $sel.PackageId } else { $sel.Id }
            $script:WizardData.PackageId      = $pkgId

            # Derive VerifyCommand from the package ID with source-appropriate
            # transforms. Winget IDs use Publisher.PackageName format; the
            # command is typically the last segment, lowercased. Choco and PyPI
            # IDs are already in command-name format.
            $verifyCmd = switch ($mgr) {
                'winget' {
                    $parts = $pkgId -split '\.'
                    if ($parts.Count -gt 1) { $parts[-1].ToLower() } else { $pkgId.ToLower() }
                }
                default { $pkgId.ToLower() }
            }
            # Fall back to first word of display name if derived value is empty
            if ([string]::IsNullOrWhiteSpace($verifyCmd)) {
                $verifyCmd = ($sel.Name.ToLower() -replace '\s.*', '')
            }
            $script:WizardData.VerifyCommand = $verifyCmd
            $script:WizardStep = 'ReviewFields'
            Switch-Screen -ScreenName 'AddTool'
        }
    })

    # Highlight change -- delegates to Invoke-DescriptionFetch
    $listView.add_SelectedItemChanged({
        param($e)
        $li = -1
        for ($i = 0; $i -lt $script:_SearchLists.Count; $i++) {
            if ($script:_SearchLists[$i].HasFocus) { $li = $i; break }
        }
        if ($li -lt 0) { return }
        $lv = $script:_SearchLists[$li]
        if (-not $lv) { return }
        Invoke-DescriptionFetch -ListIndex $li -ItemIndex $lv.SelectedItem
    })

    # Tab / Shift+Tab navigation between sections; Escape goes back.
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
                $nextLv = $script:_SearchLists[$nextIdx]
                Invoke-DescriptionFetch -ListIndex $nextIdx -ItemIndex $nextLv.SelectedItem
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
                $prevLv = $script:_SearchLists[$prevIdx]
                Invoke-DescriptionFetch -ListIndex $prevIdx -ItemIndex $prevLv.SelectedItem
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

# ---------------------------------------------------------------------------
# Search results display
# ---------------------------------------------------------------------------

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

    # Set initial focus and fetch description for item 0 of the first section
    $script:Layout.MenuList = $chocoList
    $chocoList.SetFocus()
    if ($script:ChocoSearchResults.Count -gt 0) {
        Invoke-DescriptionFetch -ListIndex 0 -ItemIndex 0
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
