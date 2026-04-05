# Home.ps1 - Dashboard home screen with status panel and main menu

# Status label references for in-place updates (avoids full screen rebuild)
$script:_HomeStatusLabels = @{
    Environment = $null
    Profile     = $null
    Updates     = $null
    LastChecked = $null
}

$script:HomeMenuItems = @(
    @{ Name = 'Tools';   Description = 'View and manage installed tools';  Screen = 'Tools' }
    @{ Name = 'Updates'; Description = 'Check and apply updates';          Screen = 'Updates' }
    @{ Name = 'Profile'; Description = 'View and edit profile health';     Screen = 'Profile' }
    @{ Name = 'Config';  Description = 'Manage winSetup configuration';    Screen = 'Config' }
    @{ Name = 'About';   Description = 'Version and environment info';     Screen = 'About' }
)

function Get-RandomQuote {
    <#
    .SYNOPSIS
        Reads a random quote from quotes.txt and returns it as a safe display string.
    .OUTPUTS
        String. The formatted quote, or empty string if the file cannot be read.
    #>
    $quotesPath = Join-Path $PSScriptRoot 'quotes.txt'

    if (-not (Test-Path $quotesPath)) { return '' }

    try {
        $lines = Get-Content $quotesPath -ErrorAction Stop |
            Where-Object { $_ -match '^\d+\.\s+".+"' }

        if ($lines.Count -eq 0) { return '' }

        $line = $lines[(Get-Random -Minimum 0 -Maximum $lines.Count)]

        # Strip the leading number and period: "nn. rest" -> "rest"
        if ($line -match '^\d+\.\s+(.+)$') {
            $quote = $matches[1].Trim()

            # Safety: treat the quote as plain display text only.
            # Strip control characters; allow printable ASCII plus common
            # Unicode punctuation (em dash, en dash, curly quotes).
            $quote = $quote -replace '[^\x20-\x7E\u00C0-\u00FF\u2013\u2014\u201C\u201D\u2018\u2019]', ''

            return $quote
        }
    }
    catch {
        # File read failure is non-fatal -- home screen loads without a quote
        return ''
    }

    return ''
}

function Add-HomeStatusPanel {
    <#
    .SYNOPSIS
        Builds the status indicator panel showing environment health metrics.
    .DESCRIPTION
        Adds the STATUS header and four colour-coded status rows (environment
        health, profile health, updates available, last checked) to the container.
    .PARAMETER Container
        The parent view to add status elements to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    # --- Description ---
    $descLabel = [Terminal.Gui.Label]::new("  Manage your winSetup dev environment. Install, update, and remove tools from the shell.")
    $descLabel.X = 0; $descLabel.Y = 0
    $descLabel.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($descLabel)

    # --- Status section header ---
    $statusHeader = [Terminal.Gui.Label]::new("  STATUS")
    $statusHeader.X = 0
    $statusHeader.Y = 2
    $statusHeader.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $statusHeader.ColorScheme = $script:Colors.Header }
    $Container.Add($statusHeader)

    # Environment health
    $wsStatus    = Get-WinSetupStatus
    $wsState     = if ($wsStatus.Status -eq 'Ok') { 'Ok' } else { 'Error' }
    $bullet      = [char]0x25CF   # ●
    $wsLabel     = New-StatusLabel `
        -Text "  $bullet Environment health      $($wsStatus.Message)" `
        -Status $wsState -X 0 -Y 3
    $Container.Add($wsLabel)
    $script:_HomeStatusLabels.Environment = $wsLabel

    # Profile health + drift. Health checks section presence; drift compares
    # deployed $PROFILE against the source in winSetup. Both can be true
    # simultaneously (all sections present but content differs).
    $profStatus = Get-ProfileHealthStatus
    $driftStatus = Get-ProfileDriftStatus
    if ($profStatus.Status -eq 'Ok' -and $driftStatus.Status -eq 'Drifted') {
        $profMessage = 'Drifted'
        $profState = 'Warn'
    } elseif ($profStatus.Status -eq 'Ok' -and $driftStatus.Status -eq 'InSync') {
        $profMessage = 'Healthy'
        $profState = 'Ok'
    } else {
        $profMessage = $profStatus.Message
        $profState = switch ($profStatus.Status) { 'Ok' { 'Ok' } 'Error' { 'Error' } default { 'Warn' } }
    }
    $profLabel = New-StatusLabel `
        -Text "  $bullet Profile health          $profMessage" `
        -Status $profState -X 0 -Y 4
    $Container.Add($profLabel)
    $script:_HomeStatusLabels.Profile = $profLabel

    # Updates available
    $updateInfo  = Get-AvailableUpdateCount
    $updState = switch ($updateInfo.Status) {
        'UpToDate'  { 'Ok' }
        'Available' { 'Warn' }
        'Checking'  { 'Warn' }
        default     { 'Warn' }
    }
    $updLabel    = New-StatusLabel `
        -Text "  $bullet Updates available       $($updateInfo.Message)" `
        -Status $updState -X 0 -Y 5
    $Container.Add($updLabel)
    $script:_HomeStatusLabels.Updates = $updLabel

    # Last checked
    $lastCheck      = Get-LastUpdateCheck
    $lastCheckState = if ($lastCheck -eq 'Never') { 'Warn' } else { 'Ok' }
    $lastLabel      = New-StatusLabel `
        -Text "  $bullet Last checked            $lastCheck" `
        -Status $lastCheckState -X 0 -Y 6
    $Container.Add($lastLabel)
    $script:_HomeStatusLabels.LastChecked = $lastLabel
}

function Update-HomeStatus {
    <#
    .SYNOPSIS
        Updates the Home screen status labels in place without rebuilding the view tree.
    .DESCRIPTION
        Recalculates update count and last-checked values and updates the existing
        labels directly. Called by the timer after a background update check completes,
        avoiding a full Switch-Screen rebuild for the Home screen. Only updates the
        two labels that change after an update check (updates available, last checked).
    #>
    $labels = $script:_HomeStatusLabels
    if (-not $labels -or -not $labels.Updates -or -not $labels.LastChecked) { return }

    $bullet = [char]0x25CF

    # Updates available
    $updateInfo = Get-AvailableUpdateCount
    $updState = switch ($updateInfo.Status) {
        'UpToDate'  { 'Ok' }
        'Available' { 'Warn' }
        'Checking'  { 'Warn' }
        default     { 'Warn' }
    }
    $labels.Updates.Text = "  $bullet Updates available       $($updateInfo.Message)"
    $scheme = switch ($updState) {
        'Ok'   { $script:Colors.StatusOk }
        'Warn' { $script:Colors.StatusWarn }
        default { $script:Colors.StatusWarn }
    }
    if ($scheme) { $labels.Updates.ColorScheme = $scheme }
    $labels.Updates.SetNeedsDisplay()

    # Last checked
    $lastCheck      = Get-LastUpdateCheck
    $lastCheckState = if ($lastCheck -eq 'Never') { 'Warn' } else { 'Ok' }
    $labels.LastChecked.Text = "  $bullet Last checked            $lastCheck"
    $scheme = switch ($lastCheckState) {
        'Ok'   { $script:Colors.StatusOk }
        'Warn' { $script:Colors.StatusWarn }
        default { $script:Colors.StatusWarn }
    }
    if ($scheme) { $labels.LastChecked.ColorScheme = $scheme }
    $labels.LastChecked.SetNeedsDisplay()
}

function Add-HomeMenuList {
    <#
    .SYNOPSIS
        Builds the main menu ListView with navigation and key handlers.
    .DESCRIPTION
        Constructs a formatted ListView from $script:HomeMenuItems, wires
        OpenSelectedItem to navigate screens, and wires '/' to focus the
        command bar. Returns the ListView for focus management.
    .PARAMETER Container
        The parent view to add the menu to.
    .OUTPUTS
        Terminal.Gui.ListView. The constructed menu list view.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    # --- Main menu section header ---
    $menuHeader = [Terminal.Gui.Label]::new("  MAIN MENU")
    $menuHeader.X = 0
    $menuHeader.Y = 8
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
    $menuList.Y = 9
    $menuList.Width  = [Terminal.Gui.Dim]::Fill()
    $menuList.Height = 5
    $menuList.AllowsMarking = $false
    if ($script:Colors.Menu) { $menuList.ColorScheme = $script:Colors.Menu }

    # Enter navigates to the selected screen
    $menuList.add_OpenSelectedItem({
        param($e)
        $index = $e.Item
        if ($index -ge 0 -and $index -lt $script:HomeMenuItems.Count) {
            Switch-Screen -ScreenName $script:HomeMenuItems[$index].Screen
        }
    })

    # '/' key jumps focus to the command bar
    $menuList.add_KeyPress({
        param($e)
        $keyValue = [int]$e.KeyEvent.Key
        # ASCII 47 = '/'
        if ($keyValue -eq 47) {
            $script:Layout.CommandInput.Text = "/"
            $script:Layout.CommandInput.SetFocus()
            $script:Layout.CommandInput.CursorPosition = 1
            $e.Handled = $true
        }
    })

    $Container.Add($menuList)
    return $menuList
}

function Add-HomeQuickStartTips {
    <#
    .SYNOPSIS
        Adds the quick start tips section to the home screen.
    .DESCRIPTION
        Renders three tip lines below the menu. The F1 key label is split into
        a separate label so it can be styled with the warning colour scheme.
    .PARAMETER Container
        The parent view to add tips to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    $tipsY = 15
    $tipsHeader = [Terminal.Gui.Label]::new("  QUICK START")
    $tipsHeader.X = 0; $tipsHeader.Y = $tipsY
    $tipsHeader.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $tipsHeader.ColorScheme = $script:Colors.Header }
    $Container.Add($tipsHeader)

    $tip1 = [Terminal.Gui.Label]::new("  Use arrow keys to navigate the menu, Enter to select.")
    $tip1.X = 0; $tip1.Y = $tipsY + 1; $tip1.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($tip1)

    $tip2 = [Terminal.Gui.Label]::new("  Type / to open the command bar. Try /update, /profile, or /help.")
    $tip2.X = 0; $tip2.Y = $tipsY + 2; $tip2.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($tip2)

    # Split into two labels so [F1] can be yellow
    $tip3pre = [Terminal.Gui.Label]::new("  Press ")
    $tip3pre.X = 0; $tip3pre.Y = $tipsY + 3; $tip3pre.Width = 8
    $Container.Add($tip3pre)

    $tip3key = [Terminal.Gui.Label]::new("[F1]")
    $tip3key.X = 8; $tip3key.Y = $tipsY + 3; $tip3key.Width = 4
    if ($script:Colors.StatusWarn) { $tip3key.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($tip3key)

    $tip3rest = [Terminal.Gui.Label]::new(" at any time for a full list of keybindings and commands.")
    $tip3rest.X = 12; $tip3rest.Y = $tipsY + 3; $tip3rest.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($tip3rest)
}

function Add-HomeFooter {
    <#
    .SYNOPSIS
        Adds the inspirational quote and quit hint to the home screen.
    .DESCRIPTION
        Renders a random quote near the bottom of the container and a Ctrl+Q
        quit hint anchored to the top-right corner.
    .PARAMETER Container
        The parent view to add footer elements to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    # --- Inspirational quote (random on each load) ---
    # Uses a read-only wrapping TextView so long quotes display in full
    # instead of being truncated. Height of 3 rows fits most quotes at
    # typical terminal widths (80-120 columns).
    $quote = Get-RandomQuote
    if ($quote) {
        $quoteView = [Terminal.Gui.TextView]::new()
        $quoteView.X = 0
        $quoteView.Y = [Terminal.Gui.Pos]::AnchorEnd(5)
        $quoteView.Width = [Terminal.Gui.Dim]::Fill()
        $quoteView.Height = 3
        $quoteView.ReadOnly = $true
        $quoteView.WordWrap = $true
        $quoteView.CanFocus = $false
        $quoteView.Text = "  $quote"
        if ($script:Colors.Base) { $quoteView.ColorScheme = $script:Colors.Base }
        $Container.Add($quoteView)
    }

    # --- Quit hint ---
    $quitHint = [Terminal.Gui.Label]::new("[Ctrl+Q Quit]")
    $quitHint.X = [Terminal.Gui.Pos]::AnchorEnd(15)
    $quitHint.Y = 0
    $quitHint.Width = 14
    if ($script:Colors.StatusWarn) { $quitHint.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($quitHint)
}

function Build-HomeScreen {
    <#
    .SYNOPSIS
        Populates the content area with the home dashboard.
    .DESCRIPTION
        Builds the STATUS indicator panel and the MAIN MENU list view.
        Status items are colour-coded based on environment state.
        Delegates to Add-HomeStatusPanel, Add-HomeMenuList,
        Add-HomeQuickStartTips, and Add-HomeFooter.
    .PARAMETER Container
        The parent view to add home screen elements to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    Add-HomeStatusPanel   -Container $Container
    $menuList = Add-HomeMenuList -Container $Container
    Add-HomeQuickStartTips -Container $Container
    Add-HomeFooter        -Container $Container

    # Store reference for focus management
    $script:Layout.MenuList = $menuList
    $menuList.SetFocus()
}
