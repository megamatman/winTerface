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

    $refreshHint = [Terminal.Gui.Label]::new("[F5 Refresh]")
    $refreshHint.X = [Terminal.Gui.Pos]::AnchorEnd(14)
    $refreshHint.Y = 1; $refreshHint.Width = 13
    if ($script:Colors.StatusWarn) { $refreshHint.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($refreshHint)

    # --- Load cached updates ---
    $cache   = Get-UpdateCache
    $updates = if ($cache -and $cache.updates) { @($cache.updates) } else { @() }

    $realUpdates = @($updates | Where-Object {
        $_.availableVersion -and $_.availableVersion -ne ''
    })
    $pipxOnly = @($updates | Where-Object {
        $_.source -eq 'pipx' -and (-not $_.availableVersion -or $_.availableVersion -eq '')
    })

    if ($realUpdates.Count -eq 0 -and $pipxOnly.Count -eq 0) {
        $msgLabel = [Terminal.Gui.Label]::new("  All tools are up to date.")
        $msgLabel.X = 0; $msgLabel.Y = 3
        $msgLabel.Width = [Terminal.Gui.Dim]::Fill()
        if ($script:Colors.StatusOk) { $msgLabel.ColorScheme = $script:Colors.StatusOk }
        $Container.Add($msgLabel)

        $escHint = [Terminal.Gui.Label]::new("  Press Escape to return to the home screen.")
        $escHint.X = 0; $escHint.Y = 5
        $escHint.Width = [Terminal.Gui.Dim]::Fill()
        if ($script:Colors.StatusWarn) { $escHint.ColorScheme = $script:Colors.StatusWarn }
        $Container.Add($escHint)

        Add-OutputPane -Container $Container -Y 7
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
    $allItems = @($realUpdates) + @($pipxOnly)
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
    $updateList.add_KeyPress({
        param($eventArgs)
        $key = $eventArgs.KeyEvent.Key

        # 'a' / 'A' -- toggle all marks
        if ([int]$key -eq [int][char]'a' -or [int]$key -eq [int][char]'A') {
            for ($i = 0; $i -lt $script:_UpdateItems.Count; $i++) {
                $updateList.Source.SetMark($i, $true)
            }
            $updateList.SetNeedsDisplay()
            $eventArgs.Handled = $true
            return
        }

        # 'u' / 'U' -- update selected tools individually
        if ([int]$key -eq [int][char]'u' -or [int]$key -eq [int][char]'U') {
            try {
                $script:UpdateFlowActive = $true
                Invoke-SelectedUpdates -ListView $updateList
            }
            catch {
                try { Append-UpdateOutput -Text "Error: $_" } catch {}
            }
            finally { $script:UpdateFlowActive = $false }
            $eventArgs.Handled = $true
            return
        }

        # Ctrl+A -- full update (Update-DevEnvironment.ps1 with no args)
        if ([int]$key -eq 1) {   # ControlA = 1
            try {
                $script:UpdateFlowActive = $true
                Invoke-FullUpdate
            }
            catch {
                try { Append-UpdateOutput -Text "Error: $_" } catch {}
            }
            finally { $script:UpdateFlowActive = $false }
            $eventArgs.Handled = $true
            return
        }

        # F5 -- refresh cache
        if ($key -eq [Terminal.Gui.Key]::F5) {
            Start-BackgroundUpdateCheck -Force
            $eventArgs.Handled = $true
            return
        }

        # '/' -- command bar
        if ([int]$key -eq 47) {
            $script:Layout.CommandInput.Text = "/"
            $script:Layout.CommandInput.SetFocus()
            $script:Layout.CommandInput.CursorPosition = 1
            $eventArgs.Handled = $true
        }
    })

    $Container.Add($updateList)
    $script:Layout.MenuList = $updateList

    # --- Hint bar ---
    $hintY = 6 + $listHeight + 1
    $hints = [Terminal.Gui.Label]::new(
        "  [Space] Toggle  [A] All  [U] Update selected  [Ctrl+A] Update all  [F5] Refresh  [Esc] Back")
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

function Append-UpdateOutput {
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
    .PARAMETER ListView
        The Terminal.Gui.ListView whose marks indicate selection.
    #>
    param($ListView)

    if ($script:UpdateRunJob) {
        Append-UpdateOutput -Text "An update is already running."
        return
    }

    # Collect marked items that have an available version
    $selected = @()
    for ($i = 0; $i -lt $script:_UpdateItems.Count; $i++) {
        if ($ListView.Source.IsMarked($i)) {
            $item = $script:_UpdateItems[$i]
            if ($item.availableVersion -and $item.availableVersion -ne '') {
                $selected += $item
            }
        }
    }

    if ($selected.Count -eq 0) {
        Append-UpdateOutput -Text "No updateable tools selected."
        return
    }

    # Clear output
    $script:UpdateOutputText = ''
    if ($script:UpdateOutputView) {
        $script:UpdateOutputView.Text = ''
        $script:UpdateOutputView.SetNeedsDisplay()
    }

    $started = Start-PackageUpdateQueue -Packages $selected
    if ($started) {
        Append-UpdateOutput -Text "Starting per-tool updates ($($selected.Count) tools)..."
        Append-UpdateOutput -Text ""
    } else {
        Append-UpdateOutput -Text "Update cancelled or winSetup path is invalid."
    }
}

function Invoke-FullUpdate {
    <#
    .SYNOPSIS
        Runs the full Update-DevEnvironment.ps1 script with no arguments.
    #>
    if ($script:UpdateRunJob) {
        Append-UpdateOutput -Text "An update is already running."
        return
    }

    $script:UpdateOutputText = ''
    if ($script:UpdateOutputView) {
        $script:UpdateOutputView.Text = ''
        $script:UpdateOutputView.SetNeedsDisplay()
    }

    $started = Invoke-WinSetupUpdate
    if ($started) {
        Append-UpdateOutput -Text "Starting full Update-DevEnvironment.ps1 ..."
        Append-UpdateOutput -Text ""
    } else {
        Append-UpdateOutput -Text "Update cancelled or winSetup path is invalid."
    }
}
