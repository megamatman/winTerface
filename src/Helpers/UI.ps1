# UI.ps1 - Color schemes and shared UI helpers

$script:Colors = @{}

function Initialize-ColorSchemes {
    <#
    .SYNOPSIS
        Creates Terminal.Gui color schemes for the application.
    .DESCRIPTION
        Initializes color schemes for the header, base content, command bar,
        status indicators, menu, and autocomplete overlay.
        Must be called after [Terminal.Gui.Application]::Init().
    #>
    $driver = [Terminal.Gui.Application]::Driver

    $script:Colors.Base = [Terminal.Gui.ColorScheme]::new()
    $script:Colors.Base.Normal    = $driver.MakeAttribute([Terminal.Gui.Color]::White,      [Terminal.Gui.Color]::Black)
    $script:Colors.Base.Focus     = $driver.MakeAttribute([Terminal.Gui.Color]::White,      [Terminal.Gui.Color]::DarkGray)
    $script:Colors.Base.HotNormal = $driver.MakeAttribute([Terminal.Gui.Color]::White,      [Terminal.Gui.Color]::Black)
    $script:Colors.Base.HotFocus  = $driver.MakeAttribute([Terminal.Gui.Color]::White,      [Terminal.Gui.Color]::DarkGray)

    $script:Colors.Header = [Terminal.Gui.ColorScheme]::new()
    $script:Colors.Header.Normal    = $driver.MakeAttribute([Terminal.Gui.Color]::BrightCyan, [Terminal.Gui.Color]::Black)
    $script:Colors.Header.Focus     = $driver.MakeAttribute([Terminal.Gui.Color]::BrightCyan, [Terminal.Gui.Color]::Black)
    $script:Colors.Header.HotNormal = $driver.MakeAttribute([Terminal.Gui.Color]::BrightCyan, [Terminal.Gui.Color]::Black)
    $script:Colors.Header.HotFocus  = $driver.MakeAttribute([Terminal.Gui.Color]::BrightCyan, [Terminal.Gui.Color]::Black)

    $script:Colors.CommandBar = [Terminal.Gui.ColorScheme]::new()
    $script:Colors.CommandBar.Normal    = $driver.MakeAttribute([Terminal.Gui.Color]::White,      [Terminal.Gui.Color]::Black)
    $script:Colors.CommandBar.Focus     = $driver.MakeAttribute([Terminal.Gui.Color]::BrightCyan, [Terminal.Gui.Color]::Black)
    $script:Colors.CommandBar.HotNormal = $driver.MakeAttribute([Terminal.Gui.Color]::Cyan,       [Terminal.Gui.Color]::Black)
    $script:Colors.CommandBar.HotFocus  = $driver.MakeAttribute([Terminal.Gui.Color]::BrightCyan, [Terminal.Gui.Color]::Black)

    $script:Colors.StatusOk = [Terminal.Gui.ColorScheme]::new()
    $attr = $driver.MakeAttribute([Terminal.Gui.Color]::Green, [Terminal.Gui.Color]::Black)
    $script:Colors.StatusOk.Normal = $attr; $script:Colors.StatusOk.Focus = $attr
    $script:Colors.StatusOk.HotNormal = $attr; $script:Colors.StatusOk.HotFocus = $attr

    $script:Colors.StatusWarn = [Terminal.Gui.ColorScheme]::new()
    $attr = $driver.MakeAttribute([Terminal.Gui.Color]::BrightYellow, [Terminal.Gui.Color]::Black)
    $script:Colors.StatusWarn.Normal = $attr; $script:Colors.StatusWarn.Focus = $attr
    $script:Colors.StatusWarn.HotNormal = $attr; $script:Colors.StatusWarn.HotFocus = $attr

    $script:Colors.StatusError = [Terminal.Gui.ColorScheme]::new()
    $attr = $driver.MakeAttribute([Terminal.Gui.Color]::Red, [Terminal.Gui.Color]::Black)
    $script:Colors.StatusError.Normal = $attr; $script:Colors.StatusError.Focus = $attr
    $script:Colors.StatusError.HotNormal = $attr; $script:Colors.StatusError.HotFocus = $attr

    $script:Colors.Menu = [Terminal.Gui.ColorScheme]::new()
    $script:Colors.Menu.Normal    = $driver.MakeAttribute([Terminal.Gui.Color]::White, [Terminal.Gui.Color]::Black)
    $script:Colors.Menu.Focus     = $driver.MakeAttribute([Terminal.Gui.Color]::Black, [Terminal.Gui.Color]::Cyan)
    $script:Colors.Menu.HotNormal = $driver.MakeAttribute([Terminal.Gui.Color]::Cyan,  [Terminal.Gui.Color]::Black)
    $script:Colors.Menu.HotFocus  = $driver.MakeAttribute([Terminal.Gui.Color]::Black, [Terminal.Gui.Color]::BrightCyan)

    $script:Colors.Dim = [Terminal.Gui.ColorScheme]::new()
    $attr = $driver.MakeAttribute([Terminal.Gui.Color]::DarkGray, [Terminal.Gui.Color]::Black)
    $script:Colors.Dim.Normal = $attr; $script:Colors.Dim.Focus = $attr
    $script:Colors.Dim.HotNormal = $attr; $script:Colors.Dim.HotFocus = $attr

    $script:Colors.OutputPane = [Terminal.Gui.ColorScheme]::new()
    $attr = $driver.MakeAttribute([Terminal.Gui.Color]::White, [Terminal.Gui.Color]::Black)
    $script:Colors.OutputPane.Normal = $attr; $script:Colors.OutputPane.Focus = $attr
    $script:Colors.OutputPane.HotNormal = $attr; $script:Colors.OutputPane.HotFocus = $attr

    $script:Colors.Autocomplete = [Terminal.Gui.ColorScheme]::new()
    $script:Colors.Autocomplete.Normal    = $driver.MakeAttribute([Terminal.Gui.Color]::White, [Terminal.Gui.Color]::DarkGray)
    $script:Colors.Autocomplete.Focus     = $driver.MakeAttribute([Terminal.Gui.Color]::Black, [Terminal.Gui.Color]::Cyan)
    $script:Colors.Autocomplete.HotNormal = $driver.MakeAttribute([Terminal.Gui.Color]::Cyan,  [Terminal.Gui.Color]::DarkGray)
    $script:Colors.Autocomplete.HotFocus  = $driver.MakeAttribute([Terminal.Gui.Color]::Black, [Terminal.Gui.Color]::BrightCyan)
}

function New-StatusLabel {
    <#
    .SYNOPSIS
        Creates a label with color based on status.
    .PARAMETER Text
        The label text.
    .PARAMETER Status
        One of 'Ok', 'Warn', 'Error'.
    .PARAMETER X
        X position.
    .PARAMETER Y
        Y position.
    .OUTPUTS
        [Terminal.Gui.Label] A colored label view.
    #>
    param(
        [string]$Text,
        [ValidateSet('Ok','Warn','Error')]
        [string]$Status = 'Ok',
        [int]$X = 0,
        [int]$Y = 0
    )

    $label = [Terminal.Gui.Label]::new($Text)
    $label.X = $X
    $label.Y = $Y
    $label.Width = [Terminal.Gui.Dim]::Fill()

    switch ($Status) {
        'Ok'    { if ($script:Colors.StatusOk)    { $label.ColorScheme = $script:Colors.StatusOk } }
        'Warn'  { if ($script:Colors.StatusWarn)  { $label.ColorScheme = $script:Colors.StatusWarn } }
        'Error' { if ($script:Colors.StatusError) { $label.ColorScheme = $script:Colors.StatusError } }
    }

    return $label
}

function Remove-OldBackups {
    <#
    .SYNOPSIS
        Removes old .bak-* files, keeping only the most recent N per source file.
    .PARAMETER SourceFile
        The original file whose backups should be pruned.
    .PARAMETER Keep
        Number of most recent backups to retain. Default 3.
    #>
    param([string]$SourceFile, [int]$Keep = 3)
    $dir  = Split-Path $SourceFile
    $base = Split-Path $SourceFile -Leaf
    Get-ChildItem $dir -Filter "$base.bak-*" |
        Sort-Object Name -Descending |
        Select-Object -Skip $Keep |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
