# About.ps1 - Version, environment, and project information

function Build-AboutScreen {
    <#
    .SYNOPSIS
        Builds the about screen showing project info and environment details.
    .PARAMETER Container
        The parent view to add screen elements to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    $header = [Terminal.Gui.Label]::new("  ABOUT")
    $header.X = 0; $header.Y = 0
    $header.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $header.ColorScheme = $script:Colors.Header }
    $Container.Add($header)

    # --- Project description ---
    $desc = @(
        "  winTerface is a terminal UI for managing a Windows development"
        "  environment configured by winSetup. It provides keyboard-driven"
        "  access to tool installation, updates, profile health, and config."
    )
    $y = 2
    foreach ($line in $desc) {
        $lbl = [Terminal.Gui.Label]::new($line)
        $lbl.X = 0; $lbl.Y = $y; $lbl.Width = [Terminal.Gui.Dim]::Fill()
        $Container.Add($lbl)
        $y++
    }

    # --- Environment info ---
    $y++
    $envHeader = [Terminal.Gui.Label]::new("  ENVIRONMENT")
    $envHeader.X = 0; $envHeader.Y = $y
    $envHeader.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $envHeader.ColorScheme = $script:Colors.Header }
    $Container.Add($envHeader)
    $y++

    $cgtVersion = 'Unknown'
    try {
        $mod = Get-Module Microsoft.PowerShell.ConsoleGuiTools -ListAvailable |
            Select-Object -First 1
        if ($mod) { $cgtVersion = $mod.Version.ToString() }
    } catch {}

    $items = @(
        @{ Label = 'winTerface version';   Value = "v$script:WinTerfaceVersion" }
        @{ Label = 'PowerShell version';   Value = "$($PSVersionTable.PSVersion)" }
        @{ Label = 'winSetup path';        Value = $(if ($env:WINSETUP) { $env:WINSETUP } else { 'Not configured' }) }
        @{ Label = 'winSetup status';      Value = (Get-WinSetupStatus).Message }
        @{ Label = 'Python version';       Value = Get-PythonVersion }
        @{ Label = 'Elevated';             Value = $(if (Test-IsElevated) { 'Yes (Administrator)' } else { 'No' }) }
        @{ Label = 'ConsoleGuiTools';      Value = $cgtVersion }
        @{ Label = 'Terminal';             Value = $(if ($env:WT_SESSION) { 'Windows Terminal' } else { 'Console' }) }
    )

    foreach ($item in $items) {
        $text = "  $($item.Label.PadRight(24)) $($item.Value)"
        $lbl = [Terminal.Gui.Label]::new($text)
        $lbl.X = 0; $lbl.Y = $y
        $lbl.Width = [Terminal.Gui.Dim]::Fill()
        $Container.Add($lbl)
        $y++
    }

    # --- Links and credit ---
    $y++
    $linksHeader = [Terminal.Gui.Label]::new("  LINKS")
    $linksHeader.X = 0; $linksHeader.Y = $y
    $linksHeader.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $linksHeader.ColorScheme = $script:Colors.Header }
    $Container.Add($linksHeader)
    $y++

    $links = @(
        "  winTerface             https://github.com/megamatman/winTerface"
        "  winSetup               https://github.com/megamatman/winSetup"
    )
    foreach ($link in $links) {
        $lbl = [Terminal.Gui.Label]::new($link)
        $lbl.X = 0; $lbl.Y = $y; $lbl.Width = [Terminal.Gui.Dim]::Fill()
        $Container.Add($lbl)
        $y++
    }

    $y++
    $credit = [Terminal.Gui.Label]::new("  Created by Matt Lawrence")
    $credit.X = 0; $credit.Y = $y
    $credit.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $credit.ColorScheme = $script:Colors.Header }
    $Container.Add($credit)

    $hint = [Terminal.Gui.Label]::new("  [Esc] Back")
    $hint.X = 0; $hint.Y = ($y + 2)
    $hint.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $hint.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($hint)

    # A focusable view is required for key events (including Esc) to reach
    # the global handler. Without one, Terminal.Gui v1 does not propagate
    # keys. Use an invisible single-item ListView matching the Updates
    # empty-state pattern.
    $focusTarget = [System.Collections.Generic.List[string]]::new()
    $focusTarget.Add("")
    $focusList = [Terminal.Gui.ListView]::new($focusTarget)
    $focusList.X = 0; $focusList.Y = ($y + 3)
    $focusList.Width = 1; $focusList.Height = 1
    $focusList.AllowsMarking = $false
    if ($script:Colors.Base) { $focusList.ColorScheme = $script:Colors.Base }
    $Container.Add($focusList)

    $script:Layout.MenuList = $focusList
    $focusList.SetFocus()
}
