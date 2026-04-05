# Profile.ps1 - Profile management screen with health checks, drift detection, and actions

$script:ProfileHealthData = @()
$script:ProfileDriftData  = $null
$script:ProfileDetailView = $null

function Build-ProfileScreen {
    <#
    .SYNOPSIS
        Builds the profile management screen.
    .DESCRIPTION
        Shows profile path info, drift status, a health checks list (left),
        a context-sensitive detail panel (right), and action keybindings.
    .PARAMETER Container
        The parent view to add screen elements to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    # --- Gather data ---
    $healthResult = Get-ProfileHealthResults
    $script:ProfileHealthData = if ($healthResult.Sections) { $healthResult.Sections } else { @() }

    $script:ProfileDriftData = Get-ProfileDriftStatus

    # --- Header info ---
    $header = [Terminal.Gui.Label]::new("  PROFILE MANAGEMENT")
    $header.X = 0; $header.Y = 0; $header.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $header.ColorScheme = $script:Colors.Header }
    $Container.Add($header)

    $refreshHint = [Terminal.Gui.Label]::new("[F5 Refresh]")
    $refreshHint.X = [Terminal.Gui.Pos]::AnchorEnd(14); $refreshHint.Y = 0; $refreshHint.Width = 13
    if ($script:Colors.StatusWarn) { $refreshHint.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($refreshHint)

    $profilePath = if ($PROFILE) { $PROFILE } else { '(not set)' }
    $sourcePath  = Join-Path $env:WINSETUP 'profile.ps1'

    $pathLabel = [Terminal.Gui.Label]::new("  Profile: $profilePath")
    $pathLabel.X = 0; $pathLabel.Y = 1; $pathLabel.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($pathLabel)

    $sourceLabel = [Terminal.Gui.Label]::new("  Source:  $sourcePath")
    $sourceLabel.X = 0; $sourceLabel.Y = 2; $sourceLabel.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($sourceLabel)

    # Drift indicator
    $bullet     = [char]0x25CF
    $driftState = $script:ProfileDriftData.Status
    $driftText  = switch ($driftState) {
        'InSync'         { "$bullet In sync" }
        'Drifted'        { "$bullet Drifted" }
        'SourceNotFound' { "$bullet Source not found" }
        default          { "$bullet Unknown" }
    }
    $driftColor = switch ($driftState) {
        'InSync'         { 'Ok' }
        'Drifted'        { 'Warn' }
        'SourceNotFound' { 'Error' }
        default          { 'Warn' }
    }
    $driftLabel = New-StatusLabel -Text "  Drift:   $driftText" -Status $driftColor -X 0 -Y 3
    $Container.Add($driftLabel)

    # --- Error display if health check failed ---
    if ($healthResult.Error) {
        $errLabel = [Terminal.Gui.Label]::new("  $($healthResult.Error)")
        $errLabel.X = 0; $errLabel.Y = 5; $errLabel.Width = [Terminal.Gui.Dim]::Fill()
        if ($script:Colors.StatusError) { $errLabel.ColorScheme = $script:Colors.StatusError }
        $Container.Add($errLabel)
        return
    }

    # --- Left panel: Health checks ---
    $leftFrame = [Terminal.Gui.FrameView]::new("Health Checks")
    $leftFrame.X = 0; $leftFrame.Y = 5
    $leftFrame.Width  = [Terminal.Gui.Dim]::Percent(42)
    $leftFrame.Height = [Terminal.Gui.Dim]::Fill(3)
    if ($script:Colors.Base) { $leftFrame.ColorScheme = $script:Colors.Base }

    $listStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $script:ProfileHealthData) {
        $icon = switch ($s.Status) {
            'Pass' { [char]0x2713 }   # ✓
            'Fail' { [char]0x2717 }   # ✗
            default { '?' }
        }
        $listStrings.Add(" $icon $($s.Section)")
    }

    $healthList = [Terminal.Gui.ListView]::new($listStrings)
    $healthList.X = 0; $healthList.Y = 0
    $healthList.Width  = [Terminal.Gui.Dim]::Fill()
    $healthList.Height = [Terminal.Gui.Dim]::Fill()
    $healthList.AllowsMarking = $false
    if ($script:Colors.Menu) { $healthList.ColorScheme = $script:Colors.Menu }

    $leftFrame.Add($healthList)
    $Container.Add($leftFrame)

    # --- Right panel: Detail ---
    $rightFrame = [Terminal.Gui.FrameView]::new("Detail")
    $rightFrame.X = [Terminal.Gui.Pos]::Percent(42); $rightFrame.Y = 5
    $rightFrame.Width  = [Terminal.Gui.Dim]::Fill()
    $rightFrame.Height = [Terminal.Gui.Dim]::Fill(3)
    if ($script:Colors.Base) { $rightFrame.ColorScheme = $script:Colors.Base }

    $detailView = [Terminal.Gui.TextView]::new()
    $detailView.X = 0; $detailView.Y = 0
    $detailView.Width  = [Terminal.Gui.Dim]::Fill()
    $detailView.Height = [Terminal.Gui.Dim]::Fill()
    $detailView.ReadOnly = $true
    if ($script:Colors.Base) { $detailView.ColorScheme = $script:Colors.Base }

    $rightFrame.Add($detailView)
    $Container.Add($rightFrame)

    $script:ProfileDetailView = $detailView

    # Populate detail for first item
    if ($script:ProfileHealthData.Count -gt 0) {
        Update-ProfileDetail -Index 0
    }

    # --- Selection change updates detail ---
    # $healthList is function-local and resolves to $null in .NET event
    # scriptblocks (same root cause as the Updates screen closure bug).
    # References $script:Layout.MenuList directly instead.
    $healthList.add_SelectedItemChanged({
        param($e)
        $lv = $script:Layout.MenuList
        if ($lv) { Update-ProfileDetail -Index $lv.SelectedItem }
    })

    # --- Key handlers ---
    $healthList.add_KeyPress({
        param($e)
        $key = $e.KeyEvent.Key

        # R -- Redeploy profile
        if ([int]$key -eq [int][char]'r' -or [int]$key -eq [int][char]'R') {
            Invoke-ProfileRedeployAction
            $e.Handled = $true
            return
        }

        # D -- View drift
        if ([int]$key -eq [int][char]'d' -or [int]$key -eq [int][char]'D') {
            Show-DriftView
            $e.Handled = $true
            return
        }

        # C -- Compare profiles in VS Code
        if ([int]$key -eq [int][char]'c' -or [int]$key -eq [int][char]'C') {
            Invoke-ProfileCompare
            $e.Handled = $true
            return
        }

        # O -- Open in VS Code
        if ([int]$key -eq [int][char]'o' -or [int]$key -eq [int][char]'O') {
            Show-OpenFileDialog
            $e.Handled = $true
            return
        }

        # F5 -- Refresh
        if ($key -eq [Terminal.Gui.Key]::F5) {
            Switch-Screen -ScreenName 'Profile'
            $e.Handled = $true
            return
        }

        # / -- Command bar
        if ([int]$key -eq 47) {
            $script:Layout.CommandInput.Text = "/"
            $script:Layout.CommandInput.SetFocus()
            $script:Layout.CommandInput.CursorPosition = 1
            $e.Handled = $true
        }
    })

    # --- Hints ---
    $hints = [Terminal.Gui.Label]::new(
        "  [R] Redeploy  [D] View drift  [C] Compare  [O] Open in VS Code  [F5] Refresh  [Esc] Back")
    $hints.X = 0; $hints.Y = [Terminal.Gui.Pos]::AnchorEnd(2)
    $hints.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $hints.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($hints)

    $script:Layout.MenuList = $healthList
    $healthList.SetFocus()
}

# ---------------------------------------------------------------------------
# Detail panel
# ---------------------------------------------------------------------------

function Update-ProfileDetail {
    <#
    .SYNOPSIS
        Populates the detail panel for the selected health check row.
    .PARAMETER Index
        Index into $script:ProfileHealthData.
    #>
    param([int]$Index)

    if ($Index -lt 0 -or $Index -ge $script:ProfileHealthData.Count) { return }
    if (-not $script:ProfileDetailView) { return }

    # If a redeploy is running, show its output instead
    if ($script:ProfileRedeployJob) {
        $script:ProfileDetailView.Text = $script:ProfileRedeployOutput
        $script:ProfileDetailView.SetNeedsDisplay()
        return
    }

    $item = $script:ProfileHealthData[$Index]
    $desc = $script:ProfileDescriptions[$item.Section]
    if (-not $desc) { $desc = $item.Section }

    $lines = @()
    $lines += "$($item.Section)"
    $lines += ""
    $lines += "$desc"
    $lines += ""

    if ($item.Status -eq 'Pass') {
        $lines += "Status: Present"
    } else {
        $lines += "Status: Missing"
        $lines += ""
        $lines += "$($item.Suggestion)"
        $lines += ""
        $lines += "[R] Redeploy profile   [O] Open in VS Code"
    }

    $script:ProfileDetailView.Text = ($lines -join "`n")
    $script:ProfileDetailView.SetNeedsDisplay()
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

function Invoke-ProfileRedeployAction {
    <#
    .SYNOPSIS
        Shows a confirmation dialog and runs Apply-PowerShellProfile.ps1.
    #>
    if ($script:ProfileRedeployJob) { return }

    # Confirmation dialog
    $script:_RedeployConfirmed = $false

    $confirmBtn = [Terminal.Gui.Button]::new("_Confirm")
    $cancelBtn  = [Terminal.Gui.Button]::new("Ca_ncel")

    $dialog = [Terminal.Gui.Dialog]::new(
        "Redeploy profile?",
        54, 11,
        [Terminal.Gui.Button[]]@($confirmBtn, $cancelBtn)
    )

    $msg1 = [Terminal.Gui.Label]::new(" This will overwrite your deployed `$PROFILE with")
    $msg1.X = 1; $msg1.Y = 1; $msg1.Width = [Terminal.Gui.Dim]::Fill(1)
    $dialog.Add($msg1)

    $msg2 = [Terminal.Gui.Label]::new(" `$env:WINSETUP\profile.ps1.")
    $msg2.X = 1; $msg2.Y = 2; $msg2.Width = [Terminal.Gui.Dim]::Fill(1)
    $dialog.Add($msg2)

    $msg3 = [Terminal.Gui.Label]::new(" Your current profile will be backed up automatically.")
    $msg3.X = 1; $msg3.Y = 4; $msg3.Width = [Terminal.Gui.Dim]::Fill(1)
    $dialog.Add($msg3)

    $confirmBtn.add_Clicked({
        $script:_RedeployConfirmed = $true
        [Terminal.Gui.Application]::RequestStop()
    })
    $cancelBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })

    $script:UpdateFlowActive = $true
    try { [Terminal.Gui.Application]::Run($dialog) } catch {}
    $script:UpdateFlowActive = $false

    if (-not $script:_RedeployConfirmed) { return }

    # Start redeployment
    $started = Invoke-ProfileRedeploy
    if ($started) {
        $script:ProfileRedeployOutput = "Starting Apply-PowerShellProfile.ps1 ...`n"
        if ($script:ProfileDetailView) {
            $script:ProfileDetailView.Text = $script:ProfileRedeployOutput
            $script:ProfileDetailView.SetNeedsDisplay()
        }
    } else {
        $script:ProfileRedeployOutput = "Could not start redeploy. Apply-PowerShellProfile.ps1 not found.`n"
        if ($script:ProfileDetailView) {
            $script:ProfileDetailView.Text = $script:ProfileRedeployOutput
            $script:ProfileDetailView.SetNeedsDisplay()
        }
    }
}

function Show-DriftView {
    <#
    .SYNOPSIS
        Shows a modal dialog with the human-readable drift diff.
    #>
    $drift = $script:ProfileDriftData
    if (-not $drift) { $drift = Get-ProfileDriftStatus }

    $width  = 70
    $height = 22

    $okBtn = [Terminal.Gui.Button]::new("_OK")
    $okBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })

    $dialog = [Terminal.Gui.Dialog]::new(
        "Profile Drift",
        $width, $height,
        [Terminal.Gui.Button[]]@($okBtn)
    )

    $text = if ($drift.Status -eq 'InSync') {
        "Profiles are identical. No drift detected."
    } elseif ($drift.DiffText) {
        $drift.DiffText
    } else {
        "Unable to determine drift status."
    }

    $tv = [Terminal.Gui.TextView]::new()
    $tv.X = 1; $tv.Y = 0
    $tv.Width  = [Terminal.Gui.Dim]::Fill(1)
    $tv.Height = [Terminal.Gui.Dim]::Fill(2)
    $tv.ReadOnly = $true
    $tv.Text = $text

    $dialog.Add($tv)
    $script:UpdateFlowActive = $true
    try { [Terminal.Gui.Application]::Run($dialog) } catch {}
    $script:UpdateFlowActive = $false
}

function Invoke-ProfileCompare {
    <#
    .SYNOPSIS
        Opens both profile files side by side in VS Code diff view.
    #>
    $deployed = $PROFILE
    $source   = Join-Path $env:WINSETUP 'profile.ps1'

    $launched = Open-FileDiffInVSCode -PathA $deployed -PathB $source
    if (-not $launched) {
        Show-VSCodeNotFoundDialog
    }
}

function Show-OpenFileDialog {
    <#
    .SYNOPSIS
        Shows a selection dialog for which profile file to open in VS Code.
    #>
    $options = [System.Collections.Generic.List[string]]::new()
    $options.Add("  profile.ps1 (source -- edit this)")
    $options.Add("  `$PROFILE (deployed -- view only)")
    $options.Add("  Compare both (diff view)")

    $script:_OpenChoice = -1

    $dialog = [Terminal.Gui.Dialog]::new("Open which file?", 48, 9)

    $optList = [Terminal.Gui.ListView]::new($options)
    $optList.X = 1; $optList.Y = 0
    $optList.Width = [Terminal.Gui.Dim]::Fill(1); $optList.Height = 3
    $optList.AllowsMarking = $false
    if ($script:Colors.Menu) { $optList.ColorScheme = $script:Colors.Menu }

    $optList.add_OpenSelectedItem({
        param($e)
        $script:_OpenChoice = $e.Item
        [Terminal.Gui.Application]::RequestStop()
    })

    $dialog.Add($optList)
    $optList.SetFocus()
    $script:UpdateFlowActive = $true
    try { [Terminal.Gui.Application]::Run($dialog) } catch {}
    $script:UpdateFlowActive = $false

    $source   = Join-Path $env:WINSETUP 'profile.ps1'
    $deployed = $PROFILE

    $launched = switch ($script:_OpenChoice) {
        0 { Open-FileInVSCode -Path $source }
        1 { Open-FileInVSCode -Path $deployed }
        2 { Open-FileDiffInVSCode -PathA $deployed -PathB $source }
        default { $false }
    }

    if ($script:_OpenChoice -ge 0 -and -not $launched) {
        Show-VSCodeNotFoundDialog
    }
}

function Show-VSCodeNotFoundDialog {
    <#
    .SYNOPSIS
        Shows an error dialog when the code command is not on PATH.
    #>
    $okBtn = [Terminal.Gui.Button]::new("_OK")
    $okBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })
    $dialog = [Terminal.Gui.Dialog]::new("Error", 46, 7, [Terminal.Gui.Button[]]@($okBtn))
    $lbl = [Terminal.Gui.Label]::new(" VS Code ('code') is not on PATH.")
    $lbl.X = 1; $lbl.Y = 1; $lbl.Width = [Terminal.Gui.Dim]::Fill(1)
    $dialog.Add($lbl)
    $script:UpdateFlowActive = $true
    try { [Terminal.Gui.Application]::Run($dialog) } catch {}
    $script:UpdateFlowActive = $false
}
