# Home.ps1 - Dashboard home screen with status panel and main menu

$script:HomeMenuItems = @(
    @{ Name = 'Tools';   Description = 'View and manage installed tools';  Screen = 'Tools' }
    @{ Name = 'Updates'; Description = 'Check and apply updates';          Screen = 'Updates' }
    @{ Name = 'Profile'; Description = 'View and edit profile health';     Screen = 'Profile' }
    @{ Name = 'Config';  Description = 'Manage winSetup configuration';    Screen = 'Config' }
    @{ Name = 'About';   Description = 'Version and environment info';     Screen = 'About' }
)

function Build-HomeScreen {
    <#
    .SYNOPSIS
        Populates the content area with the home dashboard.
    .DESCRIPTION
        Builds the STATUS indicator panel and the MAIN MENU list view.
        Status items are colour-coded based on environment state.
    .PARAMETER Container
        The parent view to add home screen elements to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    # --- Status section header ---
    $statusHeader = [Terminal.Gui.Label]::new("  STATUS")
    $statusHeader.X = 0
    $statusHeader.Y = 0
    $statusHeader.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $statusHeader.ColorScheme = $script:Colors.Header }
    $Container.Add($statusHeader)

    # Environment health
    $wsStatus    = Get-WinSetupStatus
    $wsState     = if ($wsStatus.Status -eq 'Ok') { 'Ok' } else { 'Error' }
    $bullet      = [char]0x25CF   # ●
    $wsLabel     = New-StatusLabel `
        -Text "  $bullet Environment health      $($wsStatus.Message)" `
        -Status $wsState -X 0 -Y 1
    $Container.Add($wsLabel)

    # Profile health
    $profStatus  = Get-ProfileHealthStatus
    $profState   = switch ($profStatus.Status) { 'Ok' { 'Ok' } 'Error' { 'Error' } default { 'Warn' } }
    $profLabel   = New-StatusLabel `
        -Text "  $bullet Profile health          $($profStatus.Message)" `
        -Status $profState -X 0 -Y 2
    $Container.Add($profLabel)

    # Updates available
    $updateInfo  = Get-AvailableUpdateCount
    $updState    = switch ($updateInfo.Status) { 'UpToDate' { 'Ok' } default { 'Warn' } }
    $updLabel    = New-StatusLabel `
        -Text "  $bullet Updates available       $($updateInfo.Message)" `
        -Status $updState -X 0 -Y 3
    $Container.Add($updLabel)

    # Last checked
    $lastCheck      = Get-LastUpdateCheck
    $lastCheckState = if ($lastCheck -eq 'Never') { 'Warn' } else { 'Ok' }
    $lastLabel      = New-StatusLabel `
        -Text "  $bullet Last checked            $lastCheck" `
        -Status $lastCheckState -X 0 -Y 4
    $Container.Add($lastLabel)

    # --- Main menu section header ---
    $menuHeader = [Terminal.Gui.Label]::new("  MAIN MENU")
    $menuHeader.X = 0
    $menuHeader.Y = 6
    $menuHeader.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $menuHeader.ColorScheme = $script:Colors.Header }
    $Container.Add($menuHeader)

    # Build formatted menu item strings
    $menuStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $script:HomeMenuItems) {
        $name = $item.Name.PadRight(14)
        $menuStrings.Add("  $name $($item.Description)")
    }

    $menuList = [Terminal.Gui.ListView]::new($menuStrings)
    $menuList.X = 0
    $menuList.Y = 7
    $menuList.Width  = [Terminal.Gui.Dim]::Fill()
    $menuList.Height = [Terminal.Gui.Dim]::Fill()
    $menuList.AllowsMarking = $false
    if ($script:Colors.Menu) { $menuList.ColorScheme = $script:Colors.Menu }

    # Enter navigates to the selected screen
    $menuList.add_OpenSelectedItem({
        param($eventArgs)
        $index = $eventArgs.Item
        if ($index -ge 0 -and $index -lt $script:HomeMenuItems.Count) {
            Switch-Screen -ScreenName $script:HomeMenuItems[$index].Screen
        }
    })

    # '/' key jumps focus to the command bar
    $menuList.add_KeyPress({
        param($eventArgs)
        $keyValue = [int]$eventArgs.KeyEvent.Key
        # ASCII 47 = '/'
        if ($keyValue -eq 47) {
            $script:Layout.CommandInput.Text = "/"
            $script:Layout.CommandInput.SetFocus()
            $script:Layout.CommandInput.CursorPosition = 1
            $eventArgs.Handled = $true
        }
    })

    $Container.Add($menuList)

    # Store reference for focus management
    $script:Layout.MenuList = $menuList
    $menuList.SetFocus()
}
