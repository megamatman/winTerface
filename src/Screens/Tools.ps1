# Tools.ps1 - Tool inventory with install, update, remove, and add actions

$script:ToolsOutputView = $null
$script:ToolsOutputText = ''
$script:ToolActionJob   = $null

function Build-ToolsScreen {
    <#
    .SYNOPSIS
        Builds the tools screen with inventory list, detail panel, and actions.
    .DESCRIPTION
        Left panel: tool list from Get-ToolInventory (background loaded).
        Right panel: detail for the selected tool with context-sensitive actions.
    .PARAMETER Container
        The parent view to add screen elements to.
    #>
    param(
        [Parameter(Mandatory)]
        $Container
    )

    # --- Header ---
    $header = [Terminal.Gui.Label]::new("  TOOLS")
    $header.X = 0; $header.Y = 0; $header.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $header.ColorScheme = $script:Colors.Header }
    $Container.Add($header)

    $refreshHint = [Terminal.Gui.Label]::new("[F5 Refresh]")
    $refreshHint.X = [Terminal.Gui.Pos]::AnchorEnd(14); $refreshHint.Y = 0; $refreshHint.Width = 13
    if ($script:Colors.StatusWarn) { $refreshHint.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($refreshHint)

    # --- Left panel: tool list ---
    $leftFrame = [Terminal.Gui.FrameView]::new("Tools")
    $leftFrame.X = 0; $leftFrame.Y = 2
    $leftFrame.Width  = [Terminal.Gui.Dim]::Percent(45)
    $leftFrame.Height = [Terminal.Gui.Dim]::Fill(8)
    if ($script:Colors.Base) { $leftFrame.ColorScheme = $script:Colors.Base }

    # --- Right panel: detail ---
    $rightFrame = [Terminal.Gui.FrameView]::new("Detail")
    $rightFrame.X = [Terminal.Gui.Pos]::Percent(45); $rightFrame.Y = 2
    $rightFrame.Width  = [Terminal.Gui.Dim]::Fill()
    $rightFrame.Height = [Terminal.Gui.Dim]::Fill(8)
    if ($script:Colors.Base) { $rightFrame.ColorScheme = $script:Colors.Base }

    $detailView = [Terminal.Gui.TextView]::new()
    $detailView.X = 0; $detailView.Y = 0
    $detailView.Width  = [Terminal.Gui.Dim]::Fill()
    $detailView.Height = [Terminal.Gui.Dim]::Fill()
    $detailView.ReadOnly = $true
    if ($script:Colors.Base) { $detailView.ColorScheme = $script:Colors.Base }
    $rightFrame.Add($detailView)
    $script:_ToolDetailView = $detailView

    # Build tool list from inventory data
    if (-not $script:ToolInventoryData -and -not $script:ToolInventoryJob) {
        Get-ToolInventory
    }

    $data = $script:ToolInventoryData
    if (-not $data) {
        # Still loading
        $loadLabel = [Terminal.Gui.Label]::new(" Scanning tools...")
        $loadLabel.X = 0; $loadLabel.Y = 0; $loadLabel.Width = [Terminal.Gui.Dim]::Fill()
        if ($script:Colors.StatusWarn) { $loadLabel.ColorScheme = $script:Colors.StatusWarn }
        $leftFrame.Add($loadLabel)
        $Container.Add($leftFrame)
        $Container.Add($rightFrame)
        Add-ToolsOutputPane -Container $Container
        Add-ToolsHints -Container $Container
        return
    }

    # Calculate name column width dynamically from the data
    $toolNameW = [Math]::Max(8, [Math]::Min(24,
        ($data | ForEach-Object { "$($_.Name)".Length } | Measure-Object -Maximum).Maximum + 2))

    $listStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $data) {
        $icon = switch ($t.Status) {
            'Ok'    { [char]0x2713 }
            'Error' { [char]0x2717 }
            default { '?' }
        }
        $nameStr = "$($t.Name)"
        if ($nameStr.Length -gt $toolNameW - 1) { $nameStr = $nameStr.Substring(0, $toolNameW - 3) + '..' }
        $name = $nameStr.PadRight($toolNameW)
        $ver  = "$($t.Version)"
        $listStrings.Add(" $icon $name $ver")
    }

    $toolList = [Terminal.Gui.ListView]::new($listStrings)
    $toolList.X = 0; $toolList.Y = 0
    $toolList.Width = [Terminal.Gui.Dim]::Fill(); $toolList.Height = [Terminal.Gui.Dim]::Fill()
    $toolList.AllowsMarking = $false
    if ($script:Colors.Menu) { $toolList.ColorScheme = $script:Colors.Menu }

    $leftFrame.Add($toolList)
    $Container.Add($leftFrame)
    $Container.Add($rightFrame)

    # Show first tool's detail
    if ($data.Count -gt 0) { Update-ToolDetail -Index 0 }

    # Selection change -- use $script:Layout.MenuList (closure rule)
    $toolList.add_SelectedItemChanged({
        param($e)
        $lv = $script:Layout.MenuList
        if ($lv) { Update-ToolDetail -Index $lv.SelectedItem }
    })

    # Key handlers
    $toolList.add_KeyPress({
        param($e)
        $key = $e.KeyEvent.Key
        $lv  = $script:Layout.MenuList
        $idx = if ($lv) { $lv.SelectedItem } else { -1 }

        # A -- Add tool (navigate to AddTool wizard)
        if ([int]$key -eq [int][char]'a' -or [int]$key -eq [int][char]'A') {
            Switch-Screen -ScreenName 'AddTool'
            $e.Handled = $true; return
        }

        # I -- Install missing tool
        if ([int]$key -eq [int][char]'i' -or [int]$key -eq [int][char]'I') {
            if ($idx -ge 0) { Invoke-ToolInstallAction -Index $idx }
            $e.Handled = $true; return
        }

        # U -- Update installed tool
        if ([int]$key -eq [int][char]'u' -or [int]$key -eq [int][char]'U') {
            if ($idx -ge 0) { Invoke-ToolUpdateAction -Index $idx }
            $e.Handled = $true; return
        }

        # X -- Remove tool
        if ([int]$key -eq [int][char]'x' -or [int]$key -eq [int][char]'X') {
            if ($idx -ge 0) { Invoke-ToolRemoveAction -Index $idx }
            $e.Handled = $true; return
        }

        # O -- Open install location
        if ([int]$key -eq [int][char]'o' -or [int]$key -eq [int][char]'O') {
            if ($idx -ge 0) { Invoke-ToolOpenLocation -Index $idx }
            $e.Handled = $true; return
        }

        # F5 -- Refresh inventory. Clean up any previous job first so
        # Get-ToolInventory's guard doesn't bail out.
        if ($key -eq [Terminal.Gui.Key]::F5) {
            if ($script:ToolInventoryJob) {
                try { Stop-Job $script:ToolInventoryJob -ErrorAction SilentlyContinue } catch {}
                try { Remove-Job $script:ToolInventoryJob -Force -ErrorAction SilentlyContinue } catch {}
                $script:ToolInventoryJob = $null
            }
            $script:ToolInventoryData = $null
            Get-ToolInventory
            Add-ToolsOutput -Text "Scanning tools..."
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

    Add-ToolsOutputPane -Container $Container
    Add-ToolsHints -Container $Container

    $script:Layout.MenuList = $toolList
    $toolList.SetFocus()
}

# ---------------------------------------------------------------------------
# Detail panel
# ---------------------------------------------------------------------------

function Update-ToolDetail {
    <#
    .SYNOPSIS
        Populates the detail panel for the selected tool.
    #>
    param([int]$Index)

    if (-not $script:_ToolDetailView -or -not $script:ToolInventoryData) { return }
    if ($Index -lt 0 -or $Index -ge $script:ToolInventoryData.Count) { return }

    $t = $script:ToolInventoryData[$Index]
    $lines = @(
        "$($t.Name)"
        ""
        "$($t.Desc)"
        ""
        "Manager:  $($t.Manager)"
        "Version:  $($t.Version)"
        "Command:  $($t.Command)"
    )
    if ($t.Path) { $lines += "Path:     $($t.Path)" }
    $lines += ""

    if ($t.Status -eq 'Error') {
        $lines += "[I] Install   [X] Remove from management"
    } else {
        $lines += "[U] Update   [X] Remove   [O] Open location"
    }

    try {
        $script:_ToolDetailView.Text = ($lines -join "`n")
        $script:_ToolDetailView.SetNeedsDisplay()
    } catch {}
}

# ---------------------------------------------------------------------------
# Output pane and hints
# ---------------------------------------------------------------------------

function Add-ToolsOutputPane {
    param($Container)
    $frame = [Terminal.Gui.FrameView]::new("Output")
    $frame.X = 0; $frame.Y = [Terminal.Gui.Pos]::AnchorEnd(8)
    $frame.Width = [Terminal.Gui.Dim]::Fill(); $frame.Height = 7
    if ($script:Colors.Base) { $frame.ColorScheme = $script:Colors.Base }

    $tv = [Terminal.Gui.TextView]::new()
    $tv.X = 0; $tv.Y = 0; $tv.Width = [Terminal.Gui.Dim]::Fill(); $tv.Height = [Terminal.Gui.Dim]::Fill()
    $tv.ReadOnly = $true
    if ($script:Colors.Base) { $tv.ColorScheme = $script:Colors.Base }
    if ($script:ToolsOutputText) { $tv.Text = $script:ToolsOutputText }

    $frame.Add($tv)
    $Container.Add($frame)
    $script:ToolsOutputView = $tv
}

function Add-ToolsHints {
    param($Container)
    $hints = [Terminal.Gui.Label]::new(
        "  [A] Add tool  [I] Install  [U] Update  [X] Remove  [O] Open location  [F5] Scan  [Esc] Back")
    $hints.X = 0; $hints.Y = [Terminal.Gui.Pos]::AnchorEnd(1)
    $hints.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.StatusWarn) { $hints.ColorScheme = $script:Colors.StatusWarn }
    $Container.Add($hints)
}

function Add-ToolsOutput {
    <#
    .SYNOPSIS
        Appends text to the tools screen output pane.
    #>
    param([string]$Text)
    $script:ToolsOutputText += "$Text`n"
    if ($script:ToolsOutputView) {
        try {
            $script:ToolsOutputView.Text = $script:ToolsOutputText
            # Auto-scroll to bottom
            $lineCount    = ($script:ToolsOutputText -split "`n").Count
            $visibleLines = $script:ToolsOutputView.Frame.Height
            $script:ToolsOutputView.TopRow = [Math]::Max(0, $lineCount - $visibleLines)
            $script:ToolsOutputView.SetNeedsDisplay()
        } catch {}
    }
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

function Invoke-ToolInstallAction {
    <#
    .SYNOPSIS
        Installs a missing tool. Tries -InstallTool first, falls back to
        a direct package manager command if the Install-* function doesn't
        exist (e.g. after an uninstall removed it from Setup-DevEnvironment.ps1).
    #>
    param([int]$Index)
    if ($script:ToolActionJob) { Add-ToolsOutput -Text "An action is already running."; return }
    $t = $script:ToolInventoryData[$Index]
    if (-not $t) { return }

    $script:ToolsOutputText = ''
    Add-ToolsOutput -Text "Installing $($t.Name)..."

    $manager = $t.Manager
    $command = $t.Command
    $name    = $t.Name

    $script:ToolActionJob = Start-Job -ScriptBlock {
        param($winsetup, $toolName, $mgr, $cmd)
        try {
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                        ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH', 'User')
            Write-Host "[job] PATH refreshed. choco: $(if (Get-Command choco -EA SilentlyContinue) { 'found' } else { 'NOT FOUND' })"

            # Try -InstallTool first (works for tools with an Install-* function)
            $setupScript = Join-Path $winsetup 'Setup-DevEnvironment.ps1'
            if (Test-Path $setupScript) {
                $content = Get-Content $setupScript -Raw
                $safeName = $toolName -replace '[^a-zA-Z0-9]', ''
                if ($content -match "function Install-$safeName") {
                    Write-Host "[job] Running: & '$setupScript' -InstallTool '$toolName'"
                    & $setupScript -InstallTool $toolName 2>&1
                    Write-Host "[job] Exit code: $LASTEXITCODE"
                    return
                }
            }

            # Fallback: install directly via package manager
            Write-Host "[job] No Install-$toolName function. Installing via $mgr directly."
            switch ($mgr) {
                'choco'  { Write-Host "[job] Running: choco install $cmd -y"; choco install $cmd -y 2>&1 }
                'winget' {
                    Write-Host "[job] Running: winget install $cmd"
                    winget install $cmd --silent --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1 |
                        Where-Object { "$_" -notmatch '^\s*[-\\|/]+\s*$' -and "$_" -notmatch '^\s*$' }
                }
                'pipx'   { Write-Host "[job] Running: pipx install $cmd"; pipx install $cmd 2>&1 }
                'pip'    { Write-Host "[job] Running: pip install --user $cmd"; pip install --user $cmd 2>&1 }
                default  { Write-Host "[job] No install handler for manager: $mgr"; return }
            }
            Write-Host "[job] Exit code: $LASTEXITCODE"
            # winget returns -1978335189 (0x8A15002B) when the package is
            # already installed or no update is available. This is a success.
            if ($LASTEXITCODE -eq 0) { Write-Host "$toolName installed." }
            elseif ($LASTEXITCODE -eq -1978335189) { Write-Host "$toolName is already installed." }
            else { Write-Host "$toolName install may have failed (exit code: $LASTEXITCODE)" }
        } catch {
            Write-Error "[job] Failed: $_ $($_.ScriptStackTrace)"
        }
    } -ArgumentList $env:WINSETUP, $name, $manager, $command
}

function Invoke-ToolUpdateAction {
    <#
    .SYNOPSIS
        Updates an installed tool via Update-DevEnvironment.ps1 -Package.
    #>
    param([int]$Index)
    if ($script:ToolActionJob) { Add-ToolsOutput -Text "An action is already running."; return }
    $t = $script:ToolInventoryData[$Index]
    if (-not $t -or $t.Status -eq 'Error') { Add-ToolsOutput -Text "Tool not installed."; return }

    $script:ToolsOutputText = ''
    Add-ToolsOutput -Text "Updating $($t.Name)..."

    $updateScript = Join-Path $env:WINSETUP 'Update-DevEnvironment.ps1'
    if (-not (Test-Path $updateScript)) { Add-ToolsOutput -Text "Update-DevEnvironment.ps1 not found."; return }

    $script:ToolActionJob = Start-Job -ScriptBlock {
        param($scriptPath, $toolName)
        try {
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                        ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH', 'User')
            Write-Host "[job] Running: & '$scriptPath' -Package '$toolName'"
            & $scriptPath -Package $toolName 2>&1
            Write-Host "[job] Exit code: $LASTEXITCODE"
        } catch {
            Write-Error "[job] Failed: $_ $($_.ScriptStackTrace)"
        }
    } -ArgumentList $updateScript, $t.Name.ToLower()
}

function Invoke-ToolRemoveAction {
    <#
    .SYNOPSIS
        Removes a tool via Uninstall-Tool.ps1, with confirmation.
    #>
    param([int]$Index)
    if ($script:ToolActionJob) { Add-ToolsOutput -Text "An action is already running."; return }
    $t = $script:ToolInventoryData[$Index]
    if (-not $t) { return }

    # Confirmation dialog
    $script:_RemoveChoice = 'cancel'
    $fullBtn   = [Terminal.Gui.Button]::new("_Full removal")
    $keepBtn   = [Terminal.Gui.Button]::new("_Keep installed")
    $cancelBtn = [Terminal.Gui.Button]::new("Ca_ncel")
    $dialog = [Terminal.Gui.Dialog]::new("Remove $($t.Name)?", 52, 9,
        [Terminal.Gui.Button[]]@($fullBtn, $keepBtn, $cancelBtn))

    $msg = [Terminal.Gui.Label]::new(" Full: uninstall + remove from management`n Keep: remove from management only")
    $msg.X = 1; $msg.Y = 1; $msg.Width = [Terminal.Gui.Dim]::Fill(1); $msg.Height = 2
    $dialog.Add($msg)

    $fullBtn.add_Clicked({ $script:_RemoveChoice = 'full'; [Terminal.Gui.Application]::RequestStop() })
    $keepBtn.add_Clicked({ $script:_RemoveChoice = 'keep'; [Terminal.Gui.Application]::RequestStop() })
    $cancelBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })

    $script:UpdateFlowActive = $true
    try { [Terminal.Gui.Application]::Run($dialog) } catch {}
    $script:UpdateFlowActive = $false

    if ($script:_RemoveChoice -eq 'cancel') { return }

    $script:ToolsOutputText = ''
    # Store which tool is being removed so we can clean the in-memory
    # KnownTools array when the job completes (disk is handled by
    # Uninstall-Tool.ps1 Step 5, but the running process keeps stale data).
    $script:_RemovingToolName = $t.Name
    Add-ToolsOutput -Text "Removing $($t.Name)..."

    $uninstallScript = Join-Path $env:WINSETUP 'Uninstall-Tool.ps1'
    if (-not (Test-Path $uninstallScript)) { Add-ToolsOutput -Text "Uninstall-Tool.ps1 not found."; return }

    $keepFiles = $script:_RemoveChoice -eq 'keep'
    # Pass WINTERFACE so the job can update winTerface's KnownTools (step 5)
    $wtPath = $script:WinTerfaceRoot
    $script:ToolActionJob = Start-Job -ScriptBlock {
        param($scriptPath, $toolName, $keep, $winterface)
        try {
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                        ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH', 'User')
            $env:WINTERFACE = $winterface
            $mode = if ($keep) { '-KeepFiles' } else { 'full' }
            Write-Host "[job] Running: & '$scriptPath' -Tool '$toolName' $mode"
            if ($keep) { & $scriptPath -Tool $toolName -KeepFiles 2>&1 }
            else       { & $scriptPath -Tool $toolName 2>&1 }
            Write-Host "[job] Exit code: $LASTEXITCODE"
        } catch {
            Write-Error "[job] Failed: $_ $($_.ScriptStackTrace)"
        }
    } -ArgumentList $uninstallScript, $t.Name.ToLower(), $keepFiles, $wtPath
}

function Invoke-ToolOpenLocation {
    <#
    .SYNOPSIS
        Opens the selected tool's install directory in File Explorer.
    #>
    param([int]$Index)
    if (-not $script:ToolInventoryData) { return }
    $t = $script:ToolInventoryData[$Index]
    if (-not $t -or -not $t.Path) { Add-ToolsOutput -Text "Install path unknown."; return }
    $dir = Split-Path $t.Path -Parent
    try { & explorer.exe $dir 2>$null } catch {}
}
