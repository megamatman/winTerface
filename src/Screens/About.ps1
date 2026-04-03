# About.ps1 - Version and environment information screen

function Build-AboutScreen {
    <#
    .SYNOPSIS
        Builds the about screen showing version and environment details.
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

    # Gather environment data
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

    $y = 2
    foreach ($item in $items) {
        $text = "  $($item.Label.PadRight(24)) $($item.Value)"
        $lbl = [Terminal.Gui.Label]::new($text)
        $lbl.X = 0; $lbl.Y = $y
        $lbl.Width = [Terminal.Gui.Dim]::Fill()
        $Container.Add($lbl)
        $y++
    }

    $hint = [Terminal.Gui.Label]::new("  Press Escape to return to the home screen.")
    $hint.X = 0; $hint.Y = ($y + 1)
    $hint.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $hint.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($hint)
}
