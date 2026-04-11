# Config.ps1 (Screen) - Configuration management with 4 sections:
#   0: winTerface settings (edit config.json)
#   1: winSetup path management
#   2: Tool inventory (background loaded)
#   3: Update cache management

$script:ConfigSectionIndex = 0
$script:ConfigDetailView   = $null

# ---------------------------------------------------------------------------
# Screen builder
# ---------------------------------------------------------------------------

function Add-ConfigSectionList {
    <#
    .SYNOPSIS
        Constructs the section ListView with selection and key handlers.
    .DESCRIPTION
        Creates a ListView with the four config sections (winTerface, winSetup,
        Tools, Update cache), wires SelectedItemChanged to update the detail
        panel, and attaches key handlers for E/S/V/C/R/T// actions.
    .PARAMETER LeftFrame
        The FrameView that will contain the section ListView.
    #>
    param($LeftFrame)

    $sections = [System.Collections.Generic.List[string]]::new()
    $sections.Add(" winTerface")
    $sections.Add(" winSetup")
    $sections.Add(" Tools")
    $sections.Add(" Update cache")

    $sectionList = [Terminal.Gui.ListView]::new($sections)
    $sectionList.X = 0; $sectionList.Y = 0
    $sectionList.Width = [Terminal.Gui.Dim]::Fill(); $sectionList.Height = [Terminal.Gui.Dim]::Fill()
    $sectionList.AllowsMarking = $false
    if ($script:Colors.Menu) { $sectionList.ColorScheme = $script:Colors.Menu }

    $LeftFrame.Add($sectionList)

    # Restore last-viewed section
    if ($script:ConfigSectionIndex -ge 0 -and $script:ConfigSectionIndex -lt 4) {
        $sectionList.SelectedItem = $script:ConfigSectionIndex
    }

    # --- Selection change updates content ---
    # $sectionList is function-local; use $script:Layout.MenuList in handlers.
    $sectionList.add_SelectedItemChanged({
        param($e)
        $lv = $script:Layout.MenuList
        if ($lv) {
            $script:ConfigSectionIndex = $lv.SelectedItem
            Update-ConfigDetail -Index $lv.SelectedItem
        }
    })

    # --- Key handlers ---
    $sectionList.add_KeyPress({
        param($e)
        $key = $e.KeyEvent.Key
        $idx = $script:ConfigSectionIndex

        # E -- Edit (sections 0 and 1)
        if ([int]$key -eq [int][char]'e' -or [int]$key -eq [int][char]'E') {
            if ($idx -eq 0) { Invoke-EditWinTerfaceSettings }
            elseif ($idx -eq 1) { Invoke-EditWinSetupPath }
            $e.Handled = $true; return
        }

        # S -- Save (section 0)
        if ([int]$key -eq [int][char]'s' -or [int]$key -eq [int][char]'S') {
            if ($idx -eq 0) { Invoke-SaveSettings }
            $e.Handled = $true; return
        }

        # V -- Verify path (section 1)
        if ([int]$key -eq [int][char]'v' -or [int]$key -eq [int][char]'V') {
            if ($idx -eq 1) { Update-ConfigDetail -Index 1 }
            $e.Handled = $true; return
        }

        # C -- Clear cache (section 3)
        if ([int]$key -eq [int][char]'c' -or [int]$key -eq [int][char]'C') {
            if ($idx -eq 3) { Invoke-ClearCache }
            $e.Handled = $true; return
        }

        # R -- Refresh now (section 3)
        if ([int]$key -eq [int][char]'r' -or [int]$key -eq [int][char]'R') {
            if ($idx -eq 3) {
                Start-BackgroundUpdateCheck -Force
                Update-ConfigDetail -Index 3
            }
            $e.Handled = $true; return
        }

        # T -- Open Tools screen (section 2)
        if ([int]$key -eq [int][char]'t' -or [int]$key -eq [int][char]'T') {
            if ($idx -eq 2) { Switch-Screen -ScreenName 'Tools' }
            $e.Handled = $true; return
        }

        # '/' -- command bar
        if ([int]$key -eq 47) {
            $script:Layout.CommandInput.Text = '/'
            $script:Layout.CommandInput.SetFocus()
            $script:Layout.CommandInput.CursorPosition = 1
            $e.Handled = $true
        }
    })

    return $sectionList
}

function Add-ConfigDetailPanel {
    <#
    .SYNOPSIS
        Constructs the detail panel for the config screen.
    .DESCRIPTION
        Creates a FrameView with a read-only TextView for displaying section content.
        Stores a reference to the TextView in $script:ConfigDetailView.
    .PARAMETER Container
        The parent view to add the detail panel to.
    #>
    param($Container)

    $rightFrame = [Terminal.Gui.FrameView]::new("Detail")
    $rightFrame.X = [Terminal.Gui.Pos]::Percent(25); $rightFrame.Y = 2
    $rightFrame.Width  = [Terminal.Gui.Dim]::Fill()
    $rightFrame.Height = [Terminal.Gui.Dim]::Fill(2)
    if ($script:Colors.Base) { $rightFrame.ColorScheme = $script:Colors.Base }

    $detailView = [Terminal.Gui.TextView]::new()
    $detailView.X = 0; $detailView.Y = 0
    $detailView.Width  = [Terminal.Gui.Dim]::Fill()
    $detailView.Height = [Terminal.Gui.Dim]::Fill()
    $detailView.ReadOnly = $true
    if ($script:Colors.OutputPane) { $detailView.ColorScheme = $script:Colors.OutputPane }

    $rightFrame.Add($detailView)
    $Container.Add($rightFrame)
    $script:ConfigDetailView = $detailView
}

function Add-ConfigHintBar {
    <#
    .SYNOPSIS
        Constructs the keybinding hints bar for the config screen.
    .DESCRIPTION
        Adds a label at the bottom of the container showing available key actions.
    .PARAMETER Container
        The parent view to add the hint bar to.
    #>
    param($Container)

    $hints = [Terminal.Gui.Label]::new(
        "  [E] Edit  [S] Save  [V] Verify  [C] Clear cache  [R] Refresh  [T] Open Tools screen  [Esc] Back")
    $hints.X = 0; $hints.Y = [Terminal.Gui.Pos]::AnchorEnd(1)
    $hints.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $hints.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($hints)
}

function Build-ConfigScreen {
    <#
    .SYNOPSIS
        Builds the configuration management screen.
    .DESCRIPTION
        Left panel: section list. Right panel: context-sensitive content
        that updates when the user arrows through sections.
    .PARAMETER Container
        The parent view to add screen elements to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    # --- Header ---
    $header = [Terminal.Gui.Label]::new("  CONFIGURATION")
    $header.X = 0; $header.Y = 0; $header.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $header.ColorScheme = $script:Colors.Header }
    $Container.Add($header)

    # --- Left panel: section list ---
    $leftFrame = [Terminal.Gui.FrameView]::new("Sections")
    $leftFrame.X = 0; $leftFrame.Y = 2
    $leftFrame.Width  = [Terminal.Gui.Dim]::Percent(25)
    $leftFrame.Height = [Terminal.Gui.Dim]::Fill(2)
    if ($script:Colors.Base) { $leftFrame.ColorScheme = $script:Colors.Base }

    $sectionList = Add-ConfigSectionList -LeftFrame $leftFrame
    $Container.Add($leftFrame)

    # --- Right panel ---
    Add-ConfigDetailPanel -Container $Container
    Update-ConfigDetail -Index $script:ConfigSectionIndex

    # --- Hints ---
    Add-ConfigHintBar -Container $Container

    # Start tool inventory loading if we don't have data yet
    if (-not $script:ToolInventoryData -and -not $script:ToolInventoryJob) {
        Get-ToolInventory
    }

    $script:Layout.MenuList = $sectionList
    $sectionList.SetFocus()
}

# ---------------------------------------------------------------------------
# Section content renderers
# ---------------------------------------------------------------------------

function Update-ConfigDetail {
    <#
    .SYNOPSIS
        Populates the right panel based on the selected section index.
    #>
    param([int]$Index)

    if (-not $script:ConfigDetailView) { return }

    $text = switch ($Index) {
        0 { Get-WinTerfaceSettingsText }
        1 { Get-WinSetupPathText }
        2 { Get-ToolInventoryText }
        3 { Get-UpdateCacheText }
        default { '' }
    }

    try {
        $script:ConfigDetailView.Text = $text
        $script:ConfigDetailView.SetNeedsDisplay()
    } catch {}
}

function Get-WinTerfaceSettingsText {
    <#
    .SYNOPSIS
        Renders the winTerface settings section as formatted text.
    #>
    $config = Get-WinTerfaceConfig
    $lastCheck = Get-LastUpdateCheck

    $lines = @(
        "winTerface Settings"
        ""
        "winSetup path"
        "  $($config.winSetupPath)"
        ""
        "Update check interval"
        "  $($config.updateCheckIntervalHours) hours"
        ""
        "Last update check"
        "  $lastCheck"
        ""
        "[E] Edit field   [S] Save"
    )
    return ($lines -join "`n")
}

function Get-WinSetupPathText {
    <#
    .SYNOPSIS
        Renders the winSetup path management section.
    #>
    $config  = Get-WinTerfaceConfig
    $path    = $config.winSetupPath
    $envPath = $env:WINSETUP

    $valid   = if ($path -and (Test-Path (Join-Path $path 'Setup-DevEnvironment.ps1'))) {
        "$([char]0x2713) Valid"
    } else { "$([char]0x2717) Invalid" }

    $match = if ($path -eq $envPath) { "$([char]0x2713) Matches" } else { "$([char]0x2717) Mismatch" }

    $lines = @(
        "winSetup Path Management"
        ""
        "Current path:    $path    $valid"
        "WINSETUP env:    $envPath    $match"
        ""
        "[E] Edit path   [V] Verify path"
    )
    return ($lines -join "`n")
}

function Get-ToolInventoryText {
    <#
    .SYNOPSIS
        Renders a navigation link to the dedicated Tools screen.
    #>
    $lines = @(
        "Tools Inventory"
        ""
        "View and manage all installed tools from the Tools screen."
        ""
        "[T] Open Tools screen"
    )
    return ($lines -join "`n")
}

function Get-UpdateCacheText {
    <#
    .SYNOPSIS
        Renders the update cache management section.
    #>
    $cache = Read-UpdateCacheRaw
    $lastCheck = Get-LastUpdateCheck
    $checking  = $script:UpdateCheckState -eq 'Checking'

    $updates = @($cache.updates | Where-Object {
        $_.availableVersion -and $_.availableVersion -ne ''
    })

    $lines = @(
        "Update Cache"
        ""
        "Last checked:    $lastCheck$(if ($checking) { '  (checking...)' })"
        "Cached updates:  $($updates.Count)"
        ""
    )

    if ($updates.Count -eq 0) {
        $lines += "No update data cached. Press R to check now."
    } else {
        $nameW = 18; $curW = 12; $avlW = 12
        $lines += "Tool".PadRight($nameW) + "Current".PadRight($curW) + "Available".PadRight($avlW) + "Source"
        $lines += [string]::new([char]0x2500, 54)
        foreach ($u in $updates) {
            $lines += "$($u.name)".PadRight($nameW) +
                      "$($u.currentVersion)".PadRight($curW) +
                      "$($u.availableVersion)".PadRight($avlW) +
                      "$($u.source)"
        }
    }

    $lines += ""
    $lines += "[C] Clear cache   [R] Refresh now"

    return ($lines -join "`n")
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

function Invoke-EditWinTerfaceSettings {
    <#
    .SYNOPSIS
        Opens edit dialogs for winTerface config fields.
    #>
    $config = Get-WinTerfaceConfig

    # Edit winSetup path
    $newPath = Show-ConfigEditDialog -Title "winSetup Path" `
        -Hint "Path to winSetup directory:" -CurrentValue $config.winSetupPath
    if ($null -ne $newPath) { $config.winSetupPath = $newPath }

    # Edit interval
    $newInterval = Show-ConfigEditDialog -Title "Update Check Interval" `
        -Hint "Hours between automatic update checks (1-168):" `
        -CurrentValue "$($config.updateCheckIntervalHours)"
    if ($null -ne $newInterval) {
        $intVal = $newInterval -as [int]
        if ($null -ne $intVal) { $config.updateCheckIntervalHours = $intVal }
    }

    # Save immediately after editing
    $result = Save-WinTerfaceConfig -Config $config
    if ($result.Success) {
        $env:WINSETUP = $config.winSetupPath
        Show-ConfigMessage "Settings saved."
    } else {
        Show-ConfigMessage ($result.Errors -join "`n")
    }

    Update-ConfigDetail -Index 0
}

function Invoke-EditWinSetupPath {
    <#
    .SYNOPSIS
        Dedicated path edit with confirmation dialog for side effects.
    #>
    $config = Get-WinTerfaceConfig

    $newPath = Show-ConfigEditDialog -Title "winSetup Path" `
        -Hint "Enter new winSetup directory path:" -CurrentValue $config.winSetupPath
    if ($null -eq $newPath -or $newPath -eq $config.winSetupPath) { return }

    # Validate before confirming
    if (-not (Test-Path $newPath)) {
        Show-ConfigMessage "Path does not exist: $newPath"
        return
    }
    if (-not (Test-Path (Join-Path $newPath 'Setup-DevEnvironment.ps1'))) {
        Show-ConfigMessage "Setup-DevEnvironment.ps1 not found in: $newPath"
        return
    }

    # Confirmation dialog
    $script:_PathConfirmed = $false
    $confirmBtn = [Terminal.Gui.Button]::new("_Confirm")
    $cancelBtn  = [Terminal.Gui.Button]::new("Ca_ncel")
    $dialog = [Terminal.Gui.Dialog]::new("Update winSetup path?", 56, 12,
        [Terminal.Gui.Button[]]@($confirmBtn, $cancelBtn))

    $msg = [Terminal.Gui.Label]::new(
        " This will update:`n" +
        "   config.json`n" +
        "   WINSETUP User environment variable`n" +
        "   Fallback path in profile.ps1`n`n" +
        " A backup of profile.ps1 will be created.")
    $msg.X = 1; $msg.Y = 1; $msg.Width = [Terminal.Gui.Dim]::Fill(1); $msg.Height = 6
    $dialog.Add($msg)

    $confirmBtn.add_Clicked({ $script:_PathConfirmed = $true; [Terminal.Gui.Application]::RequestStop() })
    $cancelBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })

    # Blocks screen rebuilds during modal dialog (see CONTRIBUTING.md)
    $script:UpdateFlowActive = $true
    try { [Terminal.Gui.Application]::Run($dialog) } catch {}
    $script:UpdateFlowActive = $false

    if (-not $script:_PathConfirmed) { return }

    $result = Update-WinSetupPath -NewPath $newPath
    if ($result.Success) {
        $successMsg = "Path updated to: $newPath"
        if ($result.Error) { $successMsg += "`n$($result.Error)" }
        Show-ConfigMessage $successMsg
    } else {
        Show-ConfigMessage "Failed: $($result.Error)"
    }

    Update-ConfigDetail -Index 1
}

function Invoke-SaveSettings {
    <#
    .SYNOPSIS
        Validates and saves the current config.
    #>
    $config = Get-WinTerfaceConfig
    $result = Save-WinTerfaceConfig -Config $config
    if ($result.Success) {
        Show-ConfigMessage "Settings saved."
    } else {
        Show-ConfigMessage ($result.Errors -join "`n")
    }
}

function Invoke-ClearCache {
    <#
    .SYNOPSIS
        Confirms and clears the update cache.
    #>
    $script:_ClearConfirmed = $false
    $confirmBtn = [Terminal.Gui.Button]::new("_Clear")
    $cancelBtn  = [Terminal.Gui.Button]::new("Ca_ncel")
    $dialog = [Terminal.Gui.Dialog]::new("Clear update cache?", 46, 7,
        [Terminal.Gui.Button[]]@($confirmBtn, $cancelBtn))

    $msg = [Terminal.Gui.Label]::new(" This will delete the cached update data.")
    $msg.X = 1; $msg.Y = 1; $msg.Width = [Terminal.Gui.Dim]::Fill(1)
    $dialog.Add($msg)

    $confirmBtn.add_Clicked({ $script:_ClearConfirmed = $true; [Terminal.Gui.Application]::RequestStop() })
    $cancelBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })

    $script:UpdateFlowActive = $true
    try { [Terminal.Gui.Application]::Run($dialog) } catch {}
    $script:UpdateFlowActive = $false

    if ($script:_ClearConfirmed) {
        Clear-UpdateCacheFile
        Show-ConfigMessage "Update cache cleared."
    }

    Update-ConfigDetail -Index 3
}

# ---------------------------------------------------------------------------
# Helper dialogs
# ---------------------------------------------------------------------------

function Show-ConfigEditDialog {
    <#
    .SYNOPSIS
        Shows a modal dialog with a text field for editing a config value.
    .PARAMETER Title
        Dialog title.
    .PARAMETER Hint
        Description shown above the input.
    .PARAMETER CurrentValue
        Pre-filled value.
    .OUTPUTS
        [string] The new value, or $null if cancelled.
    #>
    param([string]$Title, [string]$Hint, [string]$CurrentValue)

    $script:_EditResult = $null
    # $input is function-local and resolves to $null in .NET event handler
    # scriptblocks (same closure bug as Updates screen and Profile screen).
    # Stored as $script:_EditInput so the OK button's add_Clicked handler
    # can read the value at event time. See CONTRIBUTING.md.
    $script:_EditInput = $null

    $okBtn     = [Terminal.Gui.Button]::new("_OK")
    $cancelBtn = [Terminal.Gui.Button]::new("Ca_ncel")
    $dialog    = [Terminal.Gui.Dialog]::new($Title, 60, 8,
        [Terminal.Gui.Button[]]@($okBtn, $cancelBtn))

    $hintLabel = [Terminal.Gui.Label]::new(" $Hint")
    $hintLabel.X = 1; $hintLabel.Y = 1; $hintLabel.Width = [Terminal.Gui.Dim]::Fill(1)
    $dialog.Add($hintLabel)

    $tf = [Terminal.Gui.TextField]::new($CurrentValue)
    $tf.X = 1; $tf.Y = 2; $tf.Width = [Terminal.Gui.Dim]::Fill(1)
    $dialog.Add($tf)
    $script:_EditInput = $tf

    $okBtn.add_Clicked({
        $script:_EditResult = $script:_EditInput.Text.ToString()
        [Terminal.Gui.Application]::RequestStop()
    })
    $cancelBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })

    $tf.SetFocus()
    $script:UpdateFlowActive = $true
    try { [Terminal.Gui.Application]::Run($dialog) } catch {}
    $script:UpdateFlowActive = $false

    return $script:_EditResult
}

function Show-ConfigMessage {
    <#
    .SYNOPSIS
        Shows a brief modal message dialog.
    .PARAMETER Message
        The message text.
    #>
    param([string]$Message)

    $okBtn  = [Terminal.Gui.Button]::new("_OK")
    $dialog = [Terminal.Gui.Dialog]::new("", 56, 7, [Terminal.Gui.Button[]]@($okBtn))

    $lbl = [Terminal.Gui.Label]::new(" $Message")
    $lbl.X = 1; $lbl.Y = 1; $lbl.Width = [Terminal.Gui.Dim]::Fill(1)
    $dialog.Add($lbl)

    $okBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })

    $script:UpdateFlowActive = $true
    try { [Terminal.Gui.Application]::Run($dialog) } catch {}
    finally { $script:UpdateFlowActive = $false }
}
