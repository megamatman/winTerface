# Home.ps1 - Dashboard home screen with status panel and main menu

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
            # Truncate to fit narrow terminals -- Terminal.Gui Labels don't wrap
            if ($quote.Length -gt 100) { $quote = $quote.Substring(0, 97) + '...' }

            return $quote
        }
    }
    catch {
        # File read failure is non-fatal -- home screen loads without a quote
        return ''
    }

    return ''
}

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
    $updState = switch ($updateInfo.Status) {
        'UpToDate'  { 'Ok' }
        'Available' { 'Warn' }
        'Checking'  { 'Warn' }
        default     { 'Warn' }
    }
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

    # --- Quick start tips ---
    $tipsY = 13
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

    # --- Inspirational quote (random on each load) ---
    # Truncate to terminal width minus margins. Terminal.Gui v1 Labels don't
    # wrap or clip reliably on narrow terminals.
    $quote = Get-RandomQuote
    if ($quote) {
        $maxW = [Math]::Max(40, [Console]::WindowWidth - 8)
        if ($quote.Length -gt $maxW) { $quote = $quote.Substring(0, $maxW - 3) + '...' }
        $quoteLabel = [Terminal.Gui.Label]::new("  $quote")
        $quoteLabel.X = 0
        $quoteLabel.Y = [Terminal.Gui.Pos]::AnchorEnd(4)
        $quoteLabel.Width = [Terminal.Gui.Dim]::Fill()
        $Container.Add($quoteLabel)
    }

    # --- Quit hint ---
    $quitHint = [Terminal.Gui.Label]::new("[Ctrl+Q Quit]")
    $quitHint.X = [Terminal.Gui.Pos]::AnchorEnd(15)
    $quitHint.Y = 0
    $quitHint.Width = 14
    if ($script:Colors.StatusWarn) { $quitHint.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($quitHint)

    # Store reference for focus management
    $script:Layout.MenuList = $menuList
    $menuList.SetFocus()
}
