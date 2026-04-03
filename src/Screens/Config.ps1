# Config.ps1 (Screen) - Configuration management screen
# Stub - full implementation in Phase 5

function Build-ConfigScreen {
    <#
    .SYNOPSIS
        Builds the configuration screen (placeholder).
    .PARAMETER Container
        The parent view to add screen elements to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    $header = [Terminal.Gui.Label]::new("  CONFIGURATION")
    $header.X = 0; $header.Y = 0
    $header.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $header.ColorScheme = $script:Colors.Header }
    $Container.Add($header)

    $placeholder = [Terminal.Gui.Label]::new("  Coming in a future release.")
    $placeholder.X = 0; $placeholder.Y = 2
    $placeholder.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($placeholder)

    $hint = [Terminal.Gui.Label]::new("  Press Escape to return to the home screen.")
    $hint.X = 0; $hint.Y = 4
    $hint.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $hint.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($hint)
}
