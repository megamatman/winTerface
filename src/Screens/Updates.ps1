# Updates.ps1 - Update management screen

$script:UpdateOutputView = $null
$script:UpdateOutputText = ''
$script:_UpdateListStrings = $null   # mutable List<string> backing the ListView

function Build-UpdatesScreen {
    <#
    .SYNOPSIS
        Builds the Updates screen with update table, action hints, and output pane.
    .DESCRIPTION
        Shows a table of available updates from the cache. The user can toggle
        items with Space, select all with A, trigger per-tool updates with U,
        run a full update with Ctrl+A, and refresh with F5. A scrollable output
        pane at the bottom streams live output when an update is running.
    .PARAMETER Container
        The parent view to add screen elements to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    # --- Header ---
    $header = [Terminal.Gui.Label]::new("  UPDATES")
    $header.X = 0; $header.Y = 0
    $header.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $header.ColorScheme = $script:Colors.Header }
    $Container.Add($header)

    # --- Last checked + refresh hint ---
    $lastCheck    = Get-LastUpdateCheck
    $checkingNote = if ($script:UpdateCheckState -eq 'Checking') { '  (checking...)' } else { '' }
    $lastLine = [Terminal.Gui.Label]::new("  Last checked: ${lastCheck}${checkingNote}")
    $lastLine.X = 0; $lastLine.Y = 1
    $lastLine.Width = [Terminal.Gui.Dim]::Percent(70)
    $Container.Add($lastLine)

    # F5 was labelled "Refresh" which conflicted with its meaning on other
    # screens. Renamed to "Check for updates" throughout to eliminate ambiguity.
    $refreshHint = [Terminal.Gui.Label]::new("[F5 Check for updates]")
    $refreshHint.X = [Terminal.Gui.Pos]::AnchorEnd(24)
    $refreshHint.Y = 1; $refreshHint.Width = 23
    if ($script:Colors.StatusWarn) { $refreshHint.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($refreshHint)

    # --- Load cached updates ---
    $cache   = Get-UpdateCache
    $updates = if ($cache -and $cache.updates) { @($cache.updates) } else { @() }

    # Only show tools that have a known available update
    $realUpdates = @($updates | Where-Object {
        $_.availableVersion -and $_.availableVersion -ne ''
    })

    if ($realUpdates.Count -eq 0) {
        $msgLabel = [Terminal.Gui.Label]::new("  All tools are up to date.")
        $msgLabel.X = 0; $msgLabel.Y = 3
        $msgLabel.Width = [Terminal.Gui.Dim]::Fill()
        if ($script:Colors.StatusOk) { $msgLabel.ColorScheme = $script:Colors.StatusOk }
        $Container.Add($msgLabel)

        $tipLabel = [Terminal.Gui.Label]::new("  Press F5 or type /check-for-updates to check for new versions.")
        $tipLabel.X = 0; $tipLabel.Y = 5
        $tipLabel.Width = [Terminal.Gui.Dim]::Fill()
        $Container.Add($tipLabel)

        # A focusable view must always exist. Without one, key events including
        # F5 and Escape do not reach global handlers. Single-item ListView
        # provides reliable focus even when no updates are available.
        $emptyOptions = [System.Collections.Generic.List[string]]::new()
        $emptyOptions.Add("  [F5] Check for updates   [Esc] Back to home")
        $emptyList = [Terminal.Gui.ListView]::new($emptyOptions)
        $emptyList.X = 0; $emptyList.Y = 7
        $emptyList.Width = [Terminal.Gui.Dim]::Fill()
        $emptyList.Height = 1
        $emptyList.AllowsMarking = $false
        if ($script:Colors.StatusWarn) { $emptyList.ColorScheme = $script:Colors.StatusWarn }

        $emptyList.add_KeyPress({
            param($e)
            $key = $e.KeyEvent.Key

            # F5 -- same as /check-for-updates
            if ($key -eq [Terminal.Gui.Key]::F5) {
                Add-UpdateOutput -Text "Checking for updates..."
                Start-BackgroundUpdateCheck -Force
                $e.Handled = $true
                return
            }
            # '/' -- jump to command bar
            if ([int]$key -eq 47) {
                $script:Layout.CommandInput.Text = '/'
                $script:Layout.CommandInput.SetFocus()
                $script:Layout.CommandInput.CursorPosition = 1
                $e.Handled = $true
            }
        })

        $Container.Add($emptyList)
        Add-OutputPane -Container $Container -Y 9
        $script:Layout.MenuList = $emptyList
        $emptyList.SetFocus()
        return
    }

    # --- Section header ---
    $sectionHeader = [Terminal.Gui.Label]::new("  AVAILABLE UPDATES")
    $sectionHeader.X = 0; $sectionHeader.Y = 3
    $sectionHeader.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $sectionHeader.ColorScheme = $script:Colors.Header }
    $Container.Add($sectionHeader)

    # --- Column headers ---
    $colHeader = [Terminal.Gui.Label]::new(
        "    Tool              Current      Available    Source")
    $colHeader.X = 0; $colHeader.Y = 4
    $colHeader.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($colHeader)

    $sep = [Terminal.Gui.Label]::new(
        "  " + [string]::new([char]0x2500, 56))
    $sep.X = 0; $sep.Y = 5
    $sep.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($sep)

    # --- Build ListView items ---
    $allItems = $realUpdates
    $script:_UpdateItems = $allItems

    $listStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($u in $allItems) {
        $listStrings.Add((Format-UpdateRow $u))
    }
    $script:_UpdateListStrings = $listStrings

    $listHeight = [Math]::Min($allItems.Count, 8)

    $updateList = [Terminal.Gui.ListView]::new($listStrings)
    $updateList.X       = 2
    $updateList.Y       = 6
    $updateList.Width    = [Terminal.Gui.Dim]::Fill(1)
    $updateList.Height   = $listHeight
    $updateList.AllowsMarking = $true
    if ($script:Colors.Menu) { $updateList.ColorScheme = $script:Colors.Menu }

    # Pre-select items with a real available version
    for ($i = 0; $i -lt $allItems.Count; $i++) {
        if ($allItems[$i].availableVersion -and $allItems[$i].availableVersion -ne '') {
            $updateList.Source.SetMark($i, $true)
        }
    }

    # --- Key handlers ---
    # PowerShell .NET event handler scriptblocks do not capture function-local
    # variables. $updateList resolved to $null when key events fired.
    # All event handlers reference $script:Layout.MenuList directly.
    $updateList.add_KeyPress({
        param($e)
        $key = $e.KeyEvent.Key

        # 'a' / 'A' -- toggle all marks
        if ([int]$key -eq [int][char]'a' -or [int]$key -eq [int][char]'A') {
            $lv = $script:Layout.MenuList
            if ($lv -and $lv.Source) {
                for ($i = 0; $i -lt $script:_UpdateItems.Count; $i++) {
                    $lv.Source.SetMark($i, $true)
                }
                $lv.SetNeedsDisplay()
            }
            $e.Handled = $true
            return
        }

        # 'u' / 'U' -- update selected tools individually
        if ([int]$key -eq [int][char]'u' -or [int]$key -eq [int][char]'U') {
            try {
                $script:UpdateFlowActive = $true
                Invoke-SelectedUpdates
            }
            catch {
                try { Add-UpdateOutput -Text "Error: $_" } catch {}
            }
            finally { $script:UpdateFlowActive = $false }
            $e.Handled = $true
            return
        }

        # Ctrl+A -- full update (Update-DevEnvironment.ps1 with no args)
        if ([int]$key -eq 1) {   # ControlA = 1
            try {
                $script:UpdateFlowActive = $true
                Invoke-FullUpdate
            }
            catch {
                try { Add-UpdateOutput -Text "Error: $_" } catch {}
            }
            finally { $script:UpdateFlowActive = $false }
            $e.Handled = $true
            return
        }

        # F5 previously called Switch-Screen from inside a key event handler,
        # destroying the view that owns the event mid-dispatch. The timer
        # re-renders on completion instead. See CONTRIBUTING.md.
        if ($key -eq [Terminal.Gui.Key]::F5) {
            Add-UpdateOutput -Text "Checking for updates..."
            Start-BackgroundUpdateCheck -Force
            $e.Handled = $true
            return
        }

        # '/' -- command bar
        if ([int]$key -eq 47) {
            $script:Layout.CommandInput.Text = "/"
            $script:Layout.CommandInput.SetFocus()
            $script:Layout.CommandInput.CursorPosition = 1
            $e.Handled = $true
        }
    })

    $Container.Add($updateList)
    $script:Layout.MenuList = $updateList

    # --- Hint bar ---
    $hintY = 6 + $listHeight + 1
    $hints = [Terminal.Gui.Label]::new(
        "  [Space] Toggle  [A] All  [U] Update selected  [Ctrl+A] Update all  [F5] Check for updates  [Esc] Back")
    $hints.X = 0; $hints.Y = $hintY
    $hints.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $hints.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($hints)

    Add-OutputPane -Container $Container -Y ($hintY + 1)
    $updateList.SetFocus()
}

# ---------------------------------------------------------------------------
# Row formatting
# ---------------------------------------------------------------------------

function Format-UpdateRow {
    <#
    .SYNOPSIS
        Formats a single update cache entry into a display string for the ListView.
    .PARAMETER Item
        Hashtable with name, currentVersion, availableVersion, source keys.
    .PARAMETER Indicator
        Optional prefix character (e.g. check mark or cross).
    .OUTPUTS
        [string] Fixed-width formatted row.
    #>
    param($Item, [string]$Indicator = '')

    $prefix = if ($Indicator) { "$Indicator " } else { '' }
    $name = "$($Item.name)".PadRight(18)
    $cur  = "$($Item.currentVersion)".PadRight(13)
    $avl  = if ($Item.availableVersion) { "$($Item.availableVersion)".PadRight(13) } else { '---'.PadRight(13) }
    $src  = "$($Item.source)"
    return "${prefix}${name} ${cur} ${avl} ${src}"
}

# ---------------------------------------------------------------------------
# Output pane helpers
# ---------------------------------------------------------------------------

function Add-OutputPane {
    <#
    .SYNOPSIS
        Adds a scrollable output pane to the given container.
    .PARAMETER Container
        Parent view.
    .PARAMETER Y
        Y position for the pane.
    #>
    param($Container, [int]$Y)

    $frame = [Terminal.Gui.FrameView]::new("Output")
    $frame.X      = 0
    $frame.Y      = $Y
    $frame.Width   = [Terminal.Gui.Dim]::Fill()
    $frame.Height  = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Base) { $frame.ColorScheme = $script:Colors.Base }

    $tv = [Terminal.Gui.TextView]::new()
    $tv.X        = 0; $tv.Y = 0
    $tv.Width     = [Terminal.Gui.Dim]::Fill()
    $tv.Height    = [Terminal.Gui.Dim]::Fill()
    $tv.ReadOnly  = $true
    if ($script:Colors.Base) { $tv.ColorScheme = $script:Colors.Base }

    if ($script:UpdateOutputText) { $tv.Text = $script:UpdateOutputText }

    $frame.Add($tv)
    $Container.Add($frame)

    $script:UpdateOutputView = $tv
}

function Add-UpdateOutput {
    <#
    .SYNOPSIS
        Appends a line of text to the output pane and scrolls to the bottom.
    .PARAMETER Text
        The text to append.
    #>
    param([string]$Text)

    $script:UpdateOutputText += "$Text`n"

    if ($script:UpdateOutputView) {
        try {
            $script:UpdateOutputView.Text = $script:UpdateOutputText
            $lineCount    = ($script:UpdateOutputText -split "`n").Count
            $visibleLines = $script:UpdateOutputView.Frame.Height
            $targetRow    = [Math]::Max(0, $lineCount - $visibleLines)
            $script:UpdateOutputView.TopRow = $targetRow
            $script:UpdateOutputView.SetNeedsDisplay()
        }
        catch {}
    }
}

# ---------------------------------------------------------------------------
# Per-tool status updates in the ListView
# ---------------------------------------------------------------------------

function Update-UpdateListItemStatus {
    <#
    .SYNOPSIS
        Updates the display string for a tool in the ListView after it completes.
    .PARAMETER Name
        The tool name to update.
    .PARAMETER Status
        One of 'success', 'failed', 'skipped'.
    #>
    param([string]$Name, [string]$Status)

    if (-not $script:_UpdateListStrings -or -not $script:_UpdateItems) { return }

    $indicator = switch ($Status) {
        'success' { [char]0x2713 }   # ✓
        'failed'  { [char]0x2717 }   # ✗
        default   { [char]0x2013 }   # –
    }

    for ($i = 0; $i -lt $script:_UpdateItems.Count; $i++) {
        if ($script:_UpdateItems[$i].name -eq $Name) {
            $script:_UpdateListStrings[$i] = Format-UpdateRow -Item $script:_UpdateItems[$i] -Indicator "$indicator"
            break
        }
    }

    if ($script:Layout.MenuList) {
        $script:Layout.MenuList.SetNeedsDisplay()
    }
}

# ---------------------------------------------------------------------------
# Update triggers
# ---------------------------------------------------------------------------

function Invoke-SelectedUpdates {
    <#
    .SYNOPSIS
        Starts per-tool updates for all marked items in the ListView.
    .DESCRIPTION
        Uses $script:Layout.MenuList (the script-scoped reference) rather than
        a closure-captured local variable, because .NET event handler
        scriptblocks cannot reliably capture function-local variables.
    #>

    if ($script:UpdateRunJob) {
        Add-UpdateOutput -Text "An update is already running."
        return
    }

    $lv = $script:Layout.MenuList
    if (-not $lv -or -not $lv.Source) {
        Add-UpdateOutput -Text "Cannot read selections -- list view unavailable."
        return
    }
    if (-not $script:_UpdateItems) {
        Add-UpdateOutput -Text "No update data loaded."
        return
    }

    # Collect marked items that have a known available version
    $selected = @()
    $itemCount = @($script:_UpdateItems).Count
    for ($i = 0; $i -lt $itemCount; $i++) {
        if ($lv.Source.IsMarked($i)) {
            $item = @($script:_UpdateItems)[$i]
            if ($item -and $item.availableVersion -and $item.availableVersion -ne '') {
                $selected += $item
            }
        }
    }

    if ($selected.Count -eq 0) {
        Add-UpdateOutput -Text "No updateable tools selected."
        return
    }

    # Clear output
    $script:UpdateOutputText = ''
    if ($script:UpdateOutputView) {
        try {
            $script:UpdateOutputView.Text = ''
            $script:UpdateOutputView.SetNeedsDisplay()
        } catch {}
    }

    $started = Start-PackageUpdateQueue -Packages $selected
    if ($started) {
        Add-UpdateOutput -Text "Starting per-tool updates ($($selected.Count) tools)..."
        Add-UpdateOutput -Text ""
    } else {
        Add-UpdateOutput -Text "Update cancelled or winSetup path is invalid."
    }
}

function Invoke-FullUpdate {
    <#
    .SYNOPSIS
        Runs the full Update-DevEnvironment.ps1 script with no arguments.
    #>
    if ($script:UpdateRunJob) {
        Add-UpdateOutput -Text "An update is already running."
        return
    }

    $script:UpdateOutputText = ''
    if ($script:UpdateOutputView) {
        $script:UpdateOutputView.Text = ''
        $script:UpdateOutputView.SetNeedsDisplay()
    }

    $started = Invoke-WinSetupUpdate
    if ($started) {
        Add-UpdateOutput -Text "Starting full Update-DevEnvironment.ps1 ..."
        Add-UpdateOutput -Text ""
    } else {
        Add-UpdateOutput -Text "Update cancelled or winSetup path is invalid."
    }
}
