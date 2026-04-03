# App.ps1 - Main application loop, layout construction, and Terminal.Gui bootstrap

$script:Layout = $null

# ---------------------------------------------------------------------------
# Assembly loading
# ---------------------------------------------------------------------------

function Initialize-TerminalGui {
    <#
    .SYNOPSIS
        Loads the Terminal.Gui assembly bundled with ConsoleGuiTools.
    .DESCRIPTION
        First imports the module so its assemblies are on the load path, then
        checks whether Terminal.Gui types are already available. If not, locates
        Terminal.Gui.dll (and NStack.dll) in the module directory and loads them.
    #>

    # Ensure the module is imported so its assembly resolver is active
    Import-Module Microsoft.PowerShell.ConsoleGuiTools -ErrorAction SilentlyContinue

    # Check if types are already available
    try {
        [Terminal.Gui.Application] | Out-Null
        return   # already loaded
    } catch {}

    $module = Get-Module Microsoft.PowerShell.ConsoleGuiTools -ListAvailable |
        Select-Object -First 1
    if (-not $module) {
        throw "Microsoft.PowerShell.ConsoleGuiTools module not found."
    }

    $moduleBase = Split-Path $module.Path -Parent

    # Load NStack first (Terminal.Gui v1 dependency)
    $nstackPath = Join-Path $moduleBase 'NStack.dll'
    if (Test-Path $nstackPath) {
        try { Add-Type -Path $nstackPath -ErrorAction SilentlyContinue } catch {}
    }

    # Locate Terminal.Gui.dll
    $tgPath = Join-Path $moduleBase 'Terminal.Gui.dll'
    if (-not (Test-Path $tgPath)) {
        $found = Get-ChildItem -Path $moduleBase -Filter 'Terminal.Gui.dll' -Recurse `
            -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $tgPath = $found.FullName }
    }

    if (-not (Test-Path $tgPath)) {
        throw "Terminal.Gui.dll not found in module directory: $moduleBase"
    }

    Add-Type -Path $tgPath
}

# ---------------------------------------------------------------------------
# Header helpers
# ---------------------------------------------------------------------------

function Get-HeaderStatusText {
    <#
    .SYNOPSIS
        Builds the right-side status text for the header bar.
    .OUTPUTS
        [string] Formatted status text (e.g. "WINSETUP: OK   Python: 3.14").
    #>
    $wsStatus  = if (Test-WinSetupPath) { 'OK' } else { 'MISSING' }
    $pyVersion = Get-PythonVersion
    return "WINSETUP: $wsStatus   Python: $pyVersion"
}

# ---------------------------------------------------------------------------
# Layout construction
# ---------------------------------------------------------------------------

function New-MainLayout {
    <#
    .SYNOPSIS
        Creates the persistent application layout.
    .DESCRIPTION
        Builds the Window, header bar, separator, swappable content area,
        command-bar separator, and command input. Returns a hashtable of
        view references used by every other module.
    .OUTPUTS
        [hashtable] Keys: Window, HeaderLeft, HeaderRight, Content,
                          CommandInput, CommandLabel, AutocompleteOverlay,
                          AutocompleteList, MenuList.
    #>

    # --- Main window (provides the outer border) ---
    $window        = [Terminal.Gui.Window]::new("")
    $window.X      = 0
    $window.Y      = 0
    $window.Width  = [Terminal.Gui.Dim]::Fill()
    $window.Height = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Base) { $window.ColorScheme = $script:Colors.Base }

    # --- Header bar (Y = 0) ---
    $headerLeft        = [Terminal.Gui.Label]::new(" winTerface  v$script:WinTerfaceVersion")
    $headerLeft.X      = 0
    $headerLeft.Y      = 0
    $headerLeft.Width  = [Terminal.Gui.Dim]::Percent(50)
    $headerLeft.Height = 1
    if ($script:Colors.Header) { $headerLeft.ColorScheme = $script:Colors.Header }

    $statusText         = Get-HeaderStatusText
    $headerRight        = [Terminal.Gui.Label]::new($statusText)
    $headerRight.X      = [Terminal.Gui.Pos]::AnchorEnd($statusText.Length + 1)
    $headerRight.Y      = 0
    $headerRight.Width  = $statusText.Length
    $headerRight.Height = 1
    if ($script:Colors.Header) { $headerRight.ColorScheme = $script:Colors.Header }

    # --- Top separator (Y = 1) ---
    $sepChar   = [string]::new([char]0x2500, 300)   # ─ repeated
    $topSep        = [Terminal.Gui.Label]::new($sepChar)
    $topSep.X      = 0
    $topSep.Y      = 1
    $topSep.Width  = [Terminal.Gui.Dim]::Fill()
    $topSep.Height = 1

    # --- Content area (Y = 2, fills down to command bar) ---
    $content        = [Terminal.Gui.View]::new()
    $content.X      = 0
    $content.Y      = 2
    $content.Width  = [Terminal.Gui.Dim]::Fill()
    $content.Height = [Terminal.Gui.Dim]::Fill(3)      # leave 3 rows at bottom
    if ($script:Colors.Base) { $content.ColorScheme = $script:Colors.Base }

    # --- Bottom separator (above command bar) ---
    $botSep        = [Terminal.Gui.Label]::new($sepChar)
    $botSep.X      = 0
    $botSep.Y      = [Terminal.Gui.Pos]::AnchorEnd(2)
    $botSep.Width  = [Terminal.Gui.Dim]::Fill()
    $botSep.Height = 1

    # --- Command bar (last row) ---
    $cmdLabel        = [Terminal.Gui.Label]::new(" > ")
    $cmdLabel.X      = 0
    $cmdLabel.Y      = [Terminal.Gui.Pos]::AnchorEnd(1)
    $cmdLabel.Width  = 3
    $cmdLabel.Height = 1
    if ($script:Colors.CommandBar) { $cmdLabel.ColorScheme = $script:Colors.CommandBar }

    $cmdInput        = [Terminal.Gui.TextField]::new("")
    $cmdInput.X      = 3
    $cmdInput.Y      = [Terminal.Gui.Pos]::AnchorEnd(1)
    $cmdInput.Width  = [Terminal.Gui.Dim]::Fill(1)
    $cmdInput.Height = 1
    if ($script:Colors.CommandBar) { $cmdInput.ColorScheme = $script:Colors.CommandBar }

    # Assemble
    $window.Add($headerLeft)
    $window.Add($headerRight)
    $window.Add($topSep)
    $window.Add($content)
    $window.Add($botSep)
    $window.Add($cmdLabel)
    $window.Add($cmdInput)

    return @{
        Window              = $window
        HeaderLeft          = $headerLeft
        HeaderRight         = $headerRight
        Content             = $content
        CommandInput        = $cmdInput
        CommandLabel        = $cmdLabel
        AutocompleteOverlay = $null
        AutocompleteList    = $null
        MenuList            = $null      # set by Build-HomeScreen
    }
}

# ---------------------------------------------------------------------------
# Help overlay (F1)
# ---------------------------------------------------------------------------

function Show-HelpOverlay {
    <#
    .SYNOPSIS
        Displays a modal help dialog listing keybindings and slash commands.
    .DESCRIPTION
        Creates a Terminal.Gui Dialog, populates it with help text, and runs
        it modally. Dismissed by pressing Escape or the OK button.
    #>
    $helpWidth  = 64
    $helpHeight = 24

    $okBtn = [Terminal.Gui.Button]::new("_OK")
    $okBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })

    $dialog = [Terminal.Gui.Dialog]::new(
        "Help  -  Keybindings & Commands",
        $helpWidth,
        $helpHeight,
        [Terminal.Gui.Button[]]@($okBtn)
    )

    $lines = @(
        " KEYBINDINGS"
        " -------------------------------------------------------"
        "  Up / Down     Navigate menu items or lists"
        "  Enter         Select / confirm"
        "  Escape        Go back one level"
        "  Tab           Accept autocomplete suggestion"
        "  F1            Show this help"
        "  /             Focus the command bar"
        "  Ctrl+Q        Quit winTerface"
        ""
        " SLASH COMMANDS"
        " -------------------------------------------------------"
    )

    foreach ($cmd in (Get-AllSlashCommands)) {
        $padded = $cmd.Command.PadRight(24)
        $lines += "  $padded $($cmd.Description)"
    }

    $y = 0
    foreach ($line in $lines) {
        $lbl       = [Terminal.Gui.Label]::new($line)
        $lbl.X     = 0
        $lbl.Y     = $y
        $lbl.Width = [Terminal.Gui.Dim]::Fill()
        $dialog.Add($lbl)
        $y++
    }

    [Terminal.Gui.Application]::Run($dialog)
}

# ---------------------------------------------------------------------------
# Background polling (called every 500 ms by the main-loop timer)
# ---------------------------------------------------------------------------

function Invoke-BackgroundPoll {
    <#
    .SYNOPSIS
        Polls all active background jobs.  Called by the 500 ms timer callback.
    .DESCRIPTION
        1. Polls the update-check job (Start-BackgroundUpdateCheck).
        2. Polls the update-run job (Invoke-WinSetupUpdate) and streams its
           output into the Updates screen output pane.
    #>

    # 1 -- update check job
    Update-BackgroundCheckStatus

    # 2 -- update run job
    if ($script:UpdateRunJob) {
        $job = $script:UpdateRunJob

        # Receive incremental output
        try {
            $newOutput = @(Receive-Job $job -ErrorAction SilentlyContinue 2>&1)
            foreach ($line in $newOutput) {
                if ($null -ne $line) {
                    Append-UpdateOutput -Text "$line"
                }
            }
        }
        catch {}

        # Detect completion
        if ($job.State -ne 'Running') {
            try { Remove-Job $job -Force -ErrorAction SilentlyContinue } catch {}
            $script:UpdateRunJob       = $null
            $script:UpdateRunStartTime = $null

            if ($script:IsQueuedUpdate) {
                # Record per-tool result and advance the queue
                $currentPkg = $script:UpdatePackageQueue[$script:UpdatePackageIndex]
                $status = if ($job.State -eq 'Completed') { 'success' } else { 'failed' }
                $script:UpdatePackageResults[$currentPkg.name] = $status
                Update-UpdateListItemStatus -Name $currentPkg.name -Status $status

                $script:UpdatePackageIndex++
                if ($script:UpdatePackageIndex -lt $script:UpdatePackageQueue.Count) {
                    Start-NextPackageUpdate
                } else {
                    Complete-PackageUpdateQueue
                }
            } else {
                # Full update completed
                $exitMsg = if ($job.State -eq 'Completed') { 'succeeded' } else { "finished ($($job.State))" }
                Append-UpdateOutput -Text ''
                Append-UpdateOutput -Text "--- Update $exitMsg ---"
                Start-BackgroundUpdateCheck -Force
            }
        }
    }

    # 3 -- wizard search jobs
    if ($script:ChocoSearchJob -or $script:WingetSearchJob) {
        Update-SearchJobStatus
    }

    # 4 -- profile redeploy job
    if ($script:ProfileRedeployJob) {
        $job = $script:ProfileRedeployJob

        try {
            $newOutput = @(Receive-Job $job -ErrorAction SilentlyContinue 2>&1)
            foreach ($line in $newOutput) {
                if ($null -ne $line) {
                    $script:ProfileRedeployOutput += "$line`n"
                }
            }
            if ($script:ProfileDetailView -and $script:CurrentScreen -eq 'Profile') {
                $script:ProfileDetailView.Text = $script:ProfileRedeployOutput
                $script:ProfileDetailView.SetNeedsDisplay()
            }
        }
        catch {}

        if ($job.State -ne 'Running') {
            $script:ProfileRedeployOutput += "`n--- Redeploy complete ---`n"
            if ($script:ProfileDetailView -and $script:CurrentScreen -eq 'Profile') {
                $script:ProfileDetailView.Text = $script:ProfileRedeployOutput
                $script:ProfileDetailView.SetNeedsDisplay()
            }

            try { Remove-Job $job -Force -ErrorAction SilentlyContinue } catch {}
            $script:ProfileRedeployJob = $null

            # Refresh the profile screen to pick up new health/drift status
            if ($script:CurrentScreen -eq 'Profile') {
                Switch-Screen -ScreenName 'Profile'
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Application lifecycle
# ---------------------------------------------------------------------------

function Request-ApplicationExit {
    <#
    .SYNOPSIS
        Cleanly requests the Terminal.Gui main loop to stop.
    #>
    [Terminal.Gui.Application]::RequestStop()
}

function Start-WinTerface {
    <#
    .SYNOPSIS
        Initializes Terminal.Gui and runs the winTerface TUI.
    .DESCRIPTION
        1. Loads the Terminal.Gui assembly from ConsoleGuiTools.
        2. Initializes the application and colour schemes.
        3. Builds the persistent layout (header, content, command bar).
        4. Registers global and command-bar key handlers.
        5. Shows the Home screen and enters the main event loop.
        6. Shuts down Terminal.Gui on exit.
    #>

    # Step 1 - load assembly
    Initialize-TerminalGui

    # Step 2 - init Terminal.Gui
    [Terminal.Gui.Application]::Init()

    try {
        $top = [Terminal.Gui.Application]::Top

        # Colour schemes (require the driver to exist)
        Initialize-ColorSchemes

        # Load persisted config
        $script:Config = Get-WinTerfaceConfig

        # Step 3 - build layout
        $script:Layout = New-MainLayout
        $top.Add($script:Layout.Window)

        # Step 4 - event handlers
        Register-CommandBarHandlers

        $top.add_KeyPress({
            param($eventArgs)
            $handled = Invoke-GlobalKeyHandler -KeyEvent $eventArgs.KeyEvent
            if ($handled) { $eventArgs.Handled = $true }
        })

        # Step 5 - show Home and run
        Switch-Screen -ScreenName 'Home'

        # Step 5b - trigger background update check if cache is stale
        if (Test-UpdateCheckNeeded) {
            Start-BackgroundUpdateCheck
        }

        # Step 5c - 500 ms timer for polling background jobs
        $null = [Terminal.Gui.Application]::MainLoop.AddTimeout(
            [TimeSpan]::FromMilliseconds(500),
            [Func[Terminal.Gui.MainLoop, bool]]{
                param([Terminal.Gui.MainLoop]$ml)
                Invoke-BackgroundPoll
                return [bool]$true
            }
        )

        [Terminal.Gui.Application]::Run()
    }
    finally {
        # Step 6 - clean shutdown
        [Terminal.Gui.Application]::Shutdown()
    }
}
