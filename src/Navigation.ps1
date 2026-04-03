# Navigation.ps1 - Screen switching, focus management, keybinding routing,
#                   and autocomplete overlay management

$script:CurrentScreen = 'Home'
$script:AutocompleteSuggestions = @()

function Switch-Screen {
    <#
    .SYNOPSIS
        Replaces the content area with a different screen.
    .PARAMETER ScreenName
        The screen to show: Home, Tools, AddTool, Updates, Profile, Config, About.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ScreenName
    )

    # Cleanup when leaving a screen
    if ($script:CurrentScreen -eq 'AddTool' -and $ScreenName -ne 'AddTool') {
        Stop-WizardSearchJobs
        Reset-WizardState
    }

    # Clear existing content
    $script:Layout.Content.RemoveAll()

    switch ($ScreenName) {
        'Home'    { Build-HomeScreen    -Container $script:Layout.Content }
        'Tools'   { Build-ToolsScreen   -Container $script:Layout.Content }
        'AddTool' { Build-AddToolScreen -Container $script:Layout.Content }
        'Updates' { Build-UpdatesScreen -Container $script:Layout.Content }
        'Profile' { Build-ProfileScreen -Container $script:Layout.Content }
        'Config'  { Build-ConfigScreen  -Container $script:Layout.Content }
        'About'   { Build-AboutScreen   -Container $script:Layout.Content }
        default   { Build-HomeScreen    -Container $script:Layout.Content }
    }

    $script:CurrentScreen = $ScreenName
    $script:Layout.Content.SetNeedsDisplay()
}

function Invoke-GlobalKeyHandler {
    <#
    .SYNOPSIS
        Handles application-wide key events that are not consumed by focused views.
    .PARAMETER KeyEvent
        The Terminal.Gui KeyEvent to process.
    .OUTPUTS
        [bool] True if the key was handled and should not propagate further.
    #>
    param($KeyEvent)

    $key = $KeyEvent.Key

    # F1 -- help overlay
    if ($key -eq [Terminal.Gui.Key]::F1) {
        Show-HelpOverlay
        return $true
    }

    # Escape -- dismiss autocomplete, or navigate back to Home
    if ($key -eq [Terminal.Gui.Key]::Esc) {
        if ($script:Layout.AutocompleteOverlay) {
            Hide-AutocompleteOverlay
            $script:Layout.CommandInput.Text = ""
            if ($script:Layout.MenuList) { $script:Layout.MenuList.SetFocus() }
            return $true
        }

        if ($script:CurrentScreen -eq 'AddTool' -and $script:WizardStep -and $script:WizardStep -ne 'ChoosePath') {
            Step-WizardBack
            return $true
        }

        if ($script:CurrentScreen -ne 'Home') {
            Switch-Screen -ScreenName 'Home'
            return $true
        }
        return $false
    }

    return $false
}

function Register-CommandBarHandlers {
    <#
    .SYNOPSIS
        Wires up keyboard and text-change events on the command bar TextField.
    .DESCRIPTION
        Handles Enter (execute), Tab (accept suggestion), Escape (dismiss),
        and arrow keys (navigate autocomplete). TextChanged triggers fuzzy
        filtering of the slash command list.
    #>
    $cmdInput = $script:Layout.CommandInput

    # --- Text changed: update autocomplete overlay and reset tab cycle ---
    $cmdInput.add_TextChanged({
        param($oldText)
        $text = $script:Layout.CommandInput.Text.ToString()

        # Any text change resets the tab completion cycle so the next Tab
        # starts a fresh match from the new input.
        Reset-TabCompletion

        if ($text.StartsWith('/') -and $text.Length -gt 1) {
            $searchTerm = $text.Substring(1)
            $suggestions = Get-CommandSuggestions -SearchTerm $searchTerm
            $script:AutocompleteSuggestions = $suggestions
            if ($suggestions.Count -gt 0) {
                Show-AutocompleteOverlay -Suggestions $suggestions
            } else {
                Hide-AutocompleteOverlay
            }
        }
        elseif ($text -eq '/') {
            $suggestions = Get-CommandSuggestions -SearchTerm ''
            $script:AutocompleteSuggestions = $suggestions
            Show-AutocompleteOverlay -Suggestions $suggestions
        }
        else {
            Hide-AutocompleteOverlay
        }
    })

    # --- Key press on the command input ---
    $cmdInput.add_KeyPress({
        param($e)
        $key = $e.KeyEvent.Key

        # Enter -- execute the command (or accept highlighted autocomplete)
        if ($key -eq [Terminal.Gui.Key]::Enter) {
            $text = $script:Layout.CommandInput.Text.ToString().Trim()

            # If the autocomplete list is open, prefer the highlighted entry
            if ($script:Layout.AutocompleteList -and
                $script:AutocompleteSuggestions.Count -gt 0) {
                $idx = $script:Layout.AutocompleteList.SelectedItem
                if ($idx -ge 0 -and $idx -lt $script:AutocompleteSuggestions.Count) {
                    $text = $script:AutocompleteSuggestions[$idx].Command
                }
            }

            if ($text.StartsWith('/')) {
                Invoke-SlashCommand -CommandText $text
            }

            $script:Layout.CommandInput.Text = ""
            Hide-AutocompleteOverlay
            if ($script:Layout.MenuList) { $script:Layout.MenuList.SetFocus() }
            $e.Handled = $true
            return
        }

        # Tab -- cycle through prefix-matched completions.
        # The overlay is visual feedback; Enter accepts the overlay selection.
        # Tab always uses the cycling logic for predictable behaviour.
        # Always suppress default Tab behaviour (focus change).
        if ($key -eq [Terminal.Gui.Key]::Tab) {
            $completed = Get-TabCompletion -Input $script:Layout.CommandInput.Text.ToString()
            if ($completed) {
                $script:Layout.CommandInput.Text = $completed
                $script:Layout.CommandInput.CursorPosition = $completed.Length
            }
            $e.Handled = $true
            return
        }

        # Escape -- clear and return focus to menu
        if ($key -eq [Terminal.Gui.Key]::Esc) {
            $script:Layout.CommandInput.Text = ""
            Hide-AutocompleteOverlay
            if ($script:Layout.MenuList) { $script:Layout.MenuList.SetFocus() }
            $e.Handled = $true
            return
        }

        # Arrow up -- navigate autocomplete list up
        if ($key -eq [Terminal.Gui.Key]::CursorUp -and $script:Layout.AutocompleteList) {
            $list = $script:Layout.AutocompleteList
            if ($list.SelectedItem -gt 0) {
                $list.SelectedItem = $list.SelectedItem - 1
                $list.SetNeedsDisplay()
            }
            $e.Handled = $true
            return
        }

        # Arrow down -- navigate autocomplete list down
        if ($key -eq [Terminal.Gui.Key]::CursorDown -and $script:Layout.AutocompleteList) {
            $list = $script:Layout.AutocompleteList
            $maxIdx = $script:AutocompleteSuggestions.Count - 1
            if ($list.SelectedItem -lt $maxIdx) {
                $list.SelectedItem = $list.SelectedItem + 1
                $list.SetNeedsDisplay()
            }
            $e.Handled = $true
            return
        }
    })
}

# ---------------------------------------------------------------------------
# Autocomplete overlay
# ---------------------------------------------------------------------------

function Show-AutocompleteOverlay {
    <#
    .SYNOPSIS
        Displays (or refreshes) the fuzzy-autocomplete popup above the command bar.
    .PARAMETER Suggestions
        Array of command suggestion hashtables to display.
    #>
    param(
        [array]$Suggestions
    )

    Hide-AutocompleteOverlay
    if ($Suggestions.Count -eq 0) { return }

    # Build display strings
    $displayItems = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $Suggestions) {
        $cmd = $s.Command.PadRight(24)
        $displayItems.Add(" $cmd $($s.Description)")
    }

    $maxVisible    = [Math]::Min($Suggestions.Count, 7)
    $overlayHeight = $maxVisible + 2          # +2 for FrameView border

    $overlay = [Terminal.Gui.FrameView]::new("Commands")
    $overlay.X      = 1
    $overlay.Y      = [Terminal.Gui.Pos]::AnchorEnd($overlayHeight + 2)
    $overlay.Width   = [Terminal.Gui.Dim]::Fill(1)
    $overlay.Height  = $overlayHeight
    if ($script:Colors.Autocomplete) { $overlay.ColorScheme = $script:Colors.Autocomplete }

    $list = [Terminal.Gui.ListView]::new($displayItems)
    $list.X      = 0
    $list.Y      = 0
    $list.Width   = [Terminal.Gui.Dim]::Fill()
    $list.Height  = [Terminal.Gui.Dim]::Fill()
    $list.AllowsMarking = $false
    if ($script:Colors.Autocomplete) { $list.ColorScheme = $script:Colors.Autocomplete }

    $overlay.Add($list)
    $script:Layout.Window.Add($overlay)

    $script:Layout.AutocompleteOverlay = $overlay
    $script:Layout.AutocompleteList    = $list
    $script:Layout.Window.SetNeedsDisplay()
}

function Hide-AutocompleteOverlay {
    <#
    .SYNOPSIS
        Removes the autocomplete overlay from the window.
    #>
    if ($script:Layout -and $script:Layout.AutocompleteOverlay) {
        try {
            $script:Layout.Window.Remove($script:Layout.AutocompleteOverlay)
        } catch {}
        $script:Layout.AutocompleteOverlay = $null
        $script:Layout.AutocompleteList    = $null
        $script:AutocompleteSuggestions    = @()
        $script:Layout.Window.SetNeedsDisplay()
    }
}
