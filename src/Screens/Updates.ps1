# Updates.ps1 - Update management screen

$script:UpdateOutputView = $null
$script:UpdateOutputText = ''

function Build-UpdatesScreen {
    <#
    .SYNOPSIS
        Builds the Updates screen with update table, action hints, and output pane.
    .DESCRIPTION
        Shows a table of available updates from the cache. The user can toggle
        items with Space, select all with A, trigger updates with U, and
        refresh with F5. A scrollable output pane at the bottom streams live
        output when an update is running.
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
    $lastCheck = Get-LastUpdateCheck
    $checkingNote = if ($script:UpdateCheckState -eq 'Checking') { '  (checking...)' } else { '' }
    $lastLine = [Terminal.Gui.Label]::new("  Last checked: ${lastCheck}${checkingNote}")
    $lastLine.X = 0; $lastLine.Y = 1
    $lastLine.Width = [Terminal.Gui.Dim]::Percent(70)
    $Container.Add($lastLine)

    $refreshHint = [Terminal.Gui.Label]::new("[F5 Refresh]")
    $refreshHint.X = [Terminal.Gui.Pos]::AnchorEnd(14)
    $refreshHint.Y = 1
    $refreshHint.Width = 13
    if ($script:Colors.StatusWarn) { $refreshHint.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($refreshHint)

    # --- Load cached updates ---
    $cache   = Get-UpdateCache
    $updates = if ($cache -and $cache.updates) { @($cache.updates) } else { @() }

    # Filter to items that actually have an available version (real updates)
    $realUpdates = @($updates | Where-Object {
        $_.availableVersion -and $_.availableVersion -ne ''
    })
    $pipxOnly = @($updates | Where-Object {
        $_.source -eq 'pipx' -and (-not $_.availableVersion -or $_.availableVersion -eq '')
    })

    $hasUpdates = $realUpdates.Count -gt 0

    if (-not $hasUpdates -and $pipxOnly.Count -eq 0) {
        # --- No updates ---
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

    # --- Build ListView items (real updates first, then pipx-only) ---
    $allItems = @($realUpdates) + @($pipxOnly)
    $script:_UpdateItems = $allItems

    $listStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($u in $allItems) {
        $name = "$($u.name)".PadRight(18)
        $cur  = "$($u.currentVersion)".PadRight(13)
        $avl  = if ($u.availableVersion) { "$($u.availableVersion)".PadRight(13) } else { '---'.PadRight(13) }
        $src  = "$($u.source)"
        $listStrings.Add("$name $cur $avl $src")
    }

    # Calculate how much space the list gets (leave room for hints + output)
    $listHeight = [Math]::Min($allItems.Count, 8)

    $updateList = [Terminal.Gui.ListView]::new($listStrings)
    $updateList.X      = 2
    $updateList.Y      = 6
    $updateList.Width   = [Terminal.Gui.Dim]::Fill(1)
    $updateList.Height  = $listHeight
    $updateList.AllowsMarking = $true
    if ($script:Colors.Menu) { $updateList.ColorScheme = $script:Colors.Menu }

    # Pre-select items that have a real available version
    for ($i = 0; $i -lt $allItems.Count; $i++) {
        if ($allItems[$i].availableVersion -and $allItems[$i].availableVersion -ne '') {
            $updateList.Source.SetMark($i, $true)
        }
    }

    # Key handling on the list
    $updateList.add_KeyPress({
        param($eventArgs)
        $key = $eventArgs.KeyEvent.Key

        # 'a' / 'A' -- select all
        if ([int]$key -eq [int][char]'a' -or [int]$key -eq [int][char]'A') {
            for ($i = 0; $i -lt $script:_UpdateItems.Count; $i++) {
                $updateList.Source.SetMark($i, $true)
            }
            $updateList.SetNeedsDisplay()
            $eventArgs.Handled = $true
            return
        }

        # 'u' / 'U' -- update selected
        if ([int]$key -eq [int][char]'u' -or [int]$key -eq [int][char]'U') {
            Invoke-SelectedUpdates
            $eventArgs.Handled = $true
            return
        }

        # F5 -- refresh cache
        if ($key -eq [Terminal.Gui.Key]::F5) {
            Start-BackgroundUpdateCheck -Force
            $eventArgs.Handled = $true
            return
        }

        # '/' -- jump to command bar
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
        "  [Space] Toggle   [A] Select all   [U] Update selected   [Esc] Back")
    $hints.X = 0; $hints.Y = $hintY
    $hints.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $hints.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($hints)

    # --- Output pane ---
    Add-OutputPane -Container $Container -Y ($hintY + 1)

    $updateList.SetFocus()
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
    $tv.X        = 0
    $tv.Y        = 0
    $tv.Width     = [Terminal.Gui.Dim]::Fill()
    $tv.Height    = [Terminal.Gui.Dim]::Fill()
    $tv.ReadOnly  = $true
    if ($script:Colors.Base) { $tv.ColorScheme = $script:Colors.Base }

    # Restore previous output if the screen is re-rendered mid-update
    if ($script:UpdateOutputText) {
        $tv.Text = $script:UpdateOutputText
    }

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
            # Scroll to bottom
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
# Trigger selected updates
# ---------------------------------------------------------------------------

function Invoke-SelectedUpdates {
    <#
    .SYNOPSIS
        Starts Update-DevEnvironment.ps1 after confirming with the user.
    .DESCRIPTION
        Clears the output pane and delegates to Invoke-WinSetupUpdate which
        handles elevation checks and job creation. The 500 ms timer streams
        output into the pane automatically.
    #>
    if ($script:UpdateRunJob) {
        Append-UpdateOutput -Text "An update is already running."
        return
    }

    # Clear output
    $script:UpdateOutputText = ''
    if ($script:UpdateOutputView) {
        $script:UpdateOutputView.Text = ''
        $script:UpdateOutputView.SetNeedsDisplay()
    }

    $started = Invoke-WinSetupUpdate
    if ($started) {
        Append-UpdateOutput -Text "Starting Update-DevEnvironment.ps1 ..."
        Append-UpdateOutput -Text ""
    } else {
        Append-UpdateOutput -Text "Update cancelled or winSetup path is invalid."
    }
}
