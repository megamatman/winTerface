# ToolWriter.ps1 - Code generation and atomic file writes for winSetup

# ---------------------------------------------------------------------------
# File path helpers
# ---------------------------------------------------------------------------

function Get-WinSetupFilePaths {
    <#
    .SYNOPSIS
        Returns a hashtable of paths to the three winSetup target files.
    .OUTPUTS
        [hashtable] Keys: Setup, Update, Profile
    #>
    $base = $env:WINSETUP
    return @{
        Setup   = Join-Path $base 'Setup-DevEnvironment.ps1'
        Update  = Join-Path $base 'Update-DevEnvironment.ps1'
        Profile = Join-Path $base 'profile.ps1'
    }
}

function Read-WinSetupFiles {
    <#
    .SYNOPSIS
        Reads all target files into memory for diff preview and atomic write.
    .OUTPUTS
        [hashtable] Keys matching Get-WinSetupFilePaths; values are file content strings.
    #>
    $paths = Get-WinSetupFilePaths
    $files = @{}
    foreach ($key in $paths.Keys) {
        try {
            if (Test-Path $paths[$key]) {
                $files[$key] = Get-Content -Path $paths[$key] -Raw -ErrorAction Stop
            } else {
                $files[$key] = ''
            }
        }
        catch {
            $files[$key] = ''
        }
    }
    return $files
}

# ---------------------------------------------------------------------------
# Code generation
# ---------------------------------------------------------------------------

function New-InstallFunction {
    <#
    .SYNOPSIS
        Generates an install function matching the winSetup pattern.
    .PARAMETER DisplayName
        Human-readable tool name (e.g. "ripgrep").
    .PARAMETER PackageManager
        One of choco, winget, pipx, manual.
    .PARAMETER PackageId
        Package identifier for the package manager.
    .PARAMETER VerifyCommand
        Command used to test whether the tool is installed.
    .OUTPUTS
        [string] PowerShell function source code.
    #>
    param(
        [string]$DisplayName,
        [string]$PackageManager,
        [string]$PackageId,
        [string]$VerifyCommand
    )

    $safeName = $DisplayName -replace '[^a-zA-Z0-9]', ''

    $installCmd = switch ($PackageManager) {
        'choco'  { "choco install $PackageId -y" }
        'winget' { "winget install $PackageId --silent --accept-package-agreements --accept-source-agreements" }
        'pipx'   { "pipx install $PackageId" }
        'manual' { $null }
    }

    if ($PackageManager -eq 'manual') {
        return @"
function Install-$safeName {
    Write-Step "$DisplayName"
    if (Get-Command $VerifyCommand -ErrorAction SilentlyContinue) {
        Write-Verbose "Skipping $DisplayName -- already installed"
        Write-Skip "$DisplayName is already installed" -Track "$DisplayName"
        return
    }
    Write-Issue "$DisplayName must be installed manually" -Track "$DisplayName"
}
"@
    }

    return @"
function Install-$safeName {
    Write-Step "$DisplayName"
    if (Get-Command $VerifyCommand -ErrorAction SilentlyContinue) {
        Write-Verbose "Skipping $DisplayName -- already installed"
        Write-Skip "$DisplayName is already installed" -Track "$DisplayName"
        return
    }
    try {
        $installCmd
        if (`$LASTEXITCODE -ne 0) { Write-Issue "$DisplayName install failed (exit code: `$LASTEXITCODE)" -Track "$DisplayName"; return }
        Update-SessionPath
        Write-Change "$DisplayName installed" -Track "$DisplayName"
    } catch {
        Write-Issue "$DisplayName install failed: `$(`$_.Exception.Message)" -Track "$DisplayName"
    }
}
"@
}

function New-RegistryEntry {
    <#
    .SYNOPSIS
        Generates a $PackageRegistry hashtable entry.
    .OUTPUTS
        [string] A single line like: "toolname" = @{ Manager = "choco"; Id = "pkg" }
    #>
    param(
        [string]$DisplayName,
        [string]$PackageManager,
        [string]$PackageId
    )

    $key = $DisplayName.ToLower() -replace '[^a-z0-9\-]', ''
    return "    `"$key`" = @{ Manager = `"$PackageManager`"; Id = `"$PackageId`" }"
}

function New-ProfileSection {
    <#
    .SYNOPSIS
        Generates a profile.ps1 section with the standard header format.
    .PARAMETER DisplayName
        Tool display name.
    .PARAMETER ProfileContent
        The alias, function, or config block to add.
    .OUTPUTS
        [string] Complete profile section with header and content.
    #>
    param(
        [string]$DisplayName,
        [string]$ProfileContent
    )

    $bar = '# ' + ('=' * 78)
    return @"

$bar
# $DisplayName
$bar

$ProfileContent
"@
}

# ---------------------------------------------------------------------------
# Change application (in-memory)
# ---------------------------------------------------------------------------

function Get-ModifiedSetupContent {
    <#
    .SYNOPSIS
        Applies the new install function and call to Setup-DevEnvironment.ps1 content.
    .PARAMETER OriginalContent
        The original file content.
    .PARAMETER ToolData
        Hashtable with DisplayName, PackageManager, PackageId, VerifyCommand.
    .OUTPUTS
        [string] Modified file content.
    #>
    param([string]$OriginalContent, [hashtable]$ToolData)

    $funcCode = New-InstallFunction @ToolData
    $safeName = $ToolData.DisplayName -replace '[^a-zA-Z0-9]', ''
    $funcCall = "Install-$safeName"

    $lines = $OriginalContent -split "`r?`n"
    $result = [System.Collections.Generic.List[string]]::new()

    $funcInserted  = $false
    $callInserted  = $false
    $stepsIncremented = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Increment $CoreSteps
        if (-not $stepsIncremented -and $line -match '^\$CoreSteps\s*=\s*(\d+)') {
            $newCount = [int]$Matches[1] + 1
            $result.Add(($line -replace '\d+', "$newCount"))
            $stepsIncremented = $true
            continue
        }

        # Insert function definition before outcome tracking
        if (-not $funcInserted -and $line -match '# === Outcome tracking ===') {
            $result.Add($funcCode)
            $result.Add('')
            $funcInserted = $true
        }

        # Insert function call before Write-Summary
        if (-not $callInserted -and $line -match '^\s*Write-Summary') {
            $result.Add($funcCall)
            $result.Add('')
            $callInserted = $true
        }

        $result.Add($line)
    }

    return ($result -join "`n")
}

function Get-ModifiedUpdateContent {
    <#
    .SYNOPSIS
        Inserts a new entry into $PackageRegistry in Update-DevEnvironment.ps1.
    .PARAMETER OriginalContent
        The original file content.
    .PARAMETER ToolData
        Hashtable with DisplayName, PackageManager, PackageId.
    .OUTPUTS
        [string] Modified file content.
    #>
    param([string]$OriginalContent, [hashtable]$ToolData)

    $entry = New-RegistryEntry -DisplayName $ToolData.DisplayName `
        -PackageManager $ToolData.PackageManager -PackageId $ToolData.PackageId

    $key = $ToolData.DisplayName.ToLower() -replace '[^a-z0-9\-]', ''
    $lines = $OriginalContent -split "`r?`n"
    $result = [System.Collections.Generic.List[string]]::new()

    $inRegistry = $false
    $inserted   = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($line -match '^\$PackageRegistry\s*=\s*@\{') {
            $inRegistry = $true
            $result.Add($line)
            continue
        }

        if ($inRegistry -and -not $inserted) {
            # Look for the closing brace or an entry that comes after alphabetically
            if ($line -match '^\s*\}') {
                # End of registry -- insert before closing brace
                $result.Add($entry)
                $inserted = $true
            }
            elseif ($line -match '^\s+"([^"]+)"') {
                $existingKey = $Matches[1]
                if ($existingKey -gt $key -and -not $inserted) {
                    $result.Add($entry)
                    $inserted = $true
                }
            }
        }

        $result.Add($line)
    }

    return ($result -join "`n")
}

function Get-ModifiedProfileContent {
    <#
    .SYNOPSIS
        Appends a new section to profile.ps1 content.
    .PARAMETER OriginalContent
        The original file content.
    .PARAMETER ToolData
        Hashtable with DisplayName and ProfileAlias.
    .OUTPUTS
        [string] Modified file content, or original if no alias was provided.
    #>
    param([string]$OriginalContent, [hashtable]$ToolData)

    if (-not $ToolData.ProfileAlias) { return $OriginalContent }

    $section = New-ProfileSection -DisplayName $ToolData.DisplayName `
        -ProfileContent $ToolData.ProfileAlias

    return $OriginalContent.TrimEnd() + "`n" + $section + "`n"
}

# ---------------------------------------------------------------------------
# Diff preview
# ---------------------------------------------------------------------------

function Get-ToolDiffPreview {
    <#
    .SYNOPSIS
        Generates a diff-style preview of all changes for the confirmation screen.
    .PARAMETER ToolData
        Hashtable with all wizard fields.
    .OUTPUTS
        [string] Multi-line diff preview text.
    #>
    param([hashtable]$ToolData)

    $lines = @()

    # Setup-DevEnvironment.ps1
    $sep = [string]::new([char]0x2500, 44)
    $lines += "$([char]0x2500)$([char]0x2500) Setup-DevEnvironment.ps1 $sep"
    $funcCode = New-InstallFunction -DisplayName $ToolData.DisplayName `
        -PackageManager $ToolData.PackageManager `
        -PackageId $ToolData.PackageId `
        -VerifyCommand $ToolData.VerifyCommand
    foreach ($fl in ($funcCode -split "`n")) {
        $lines += "+ $fl"
    }
    $safeName = $ToolData.DisplayName -replace '[^a-zA-Z0-9]', ''
    $lines += ''
    $lines += "+ # (call added to execution block)"
    $lines += "+ Install-$safeName"

    # Update-DevEnvironment.ps1
    $lines += ''
    $lines += "$([char]0x2500)$([char]0x2500) Update-DevEnvironment.ps1 $sep"
    $entry = New-RegistryEntry -DisplayName $ToolData.DisplayName `
        -PackageManager $ToolData.PackageManager -PackageId $ToolData.PackageId
    $lines += "+ $entry"

    # profile.ps1
    $lines += ''
    $lines += "$([char]0x2500)$([char]0x2500) profile.ps1 $sep"
    if ($ToolData.ProfileAlias) {
        $section = New-ProfileSection -DisplayName $ToolData.DisplayName `
            -ProfileContent $ToolData.ProfileAlias
        foreach ($pl in ($section -split "`n")) {
            if ($pl) { $lines += "+ $pl" }
        }
    } else {
        $lines += "  (no changes)"
    }

    return ($lines -join "`n")
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

function Test-GeneratedCode {
    <#
    .SYNOPSIS
        Validates PowerShell code using the built-in parser.
    .PARAMETER Code
        PowerShell source code to validate.
    .OUTPUTS
        [bool] True if the code parses without errors.
    #>
    param([string]$Code)

    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput(
        $Code, [ref]$tokens, [ref]$errors)
    return ($null -eq $errors -or $errors.Count -eq 0)
}

# ---------------------------------------------------------------------------
# Atomic file writer
# ---------------------------------------------------------------------------

function Write-ToolChanges {
    <#
    .SYNOPSIS
        Atomically writes all generated changes to winSetup files.
    .DESCRIPTION
        Reads all target files, applies changes in memory, validates the
        generated code, writes all files, and rolls back if any write fails.
    .PARAMETER ToolData
        Hashtable with DisplayName, PackageManager, PackageId, VerifyCommand,
        ProfileAlias.
    .OUTPUTS
        [hashtable] @{ Success = bool; Error = string; FilesWritten = array }
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolData
    )

    $paths     = Get-WinSetupFilePaths
    $originals = Read-WinSetupFiles

    # Generate modified content
    try {
        $modified = @{
            Setup   = Get-ModifiedSetupContent   -OriginalContent $originals.Setup   -ToolData $ToolData
            Update  = Get-ModifiedUpdateContent   -OriginalContent $originals.Update  -ToolData $ToolData
            Profile = Get-ModifiedProfileContent  -OriginalContent $originals.Profile -ToolData $ToolData
        }
    }
    catch {
        return @{ Success = $false; Error = "Code generation failed: $_"; FilesWritten = @() }
    }

    # Validate setup and update scripts
    foreach ($key in @('Setup', 'Update')) {
        if (-not (Test-GeneratedCode -Code $modified[$key])) {
            return @{ Success = $false; Error = "Generated code for $key is not valid PowerShell"; FilesWritten = @() }
        }
    }

    # Write all files
    $written = @()
    try {
        foreach ($key in @('Setup', 'Update', 'Profile')) {
            # Only write if content actually changed
            if ($modified[$key] -ne $originals[$key]) {
                Set-Content -Path $paths[$key] -Value $modified[$key] -Encoding UTF8 -ErrorAction Stop
                $written += $paths[$key]
            }
        }
        return @{ Success = $true; Error = ''; FilesWritten = $written }
    }
    catch {
        # Rollback: restore originals for any file we already wrote
        foreach ($path in $written) {
            $key = ($paths.GetEnumerator() | Where-Object { $_.Value -eq $path }).Key
            if ($key -and $originals.ContainsKey($key)) {
                try { Set-Content -Path $path -Value $originals[$key] -Encoding UTF8 } catch {}
            }
        }
        return @{ Success = $false; Error = "Write failed: $_. Original files restored."; FilesWritten = @() }
    }
}
