# PackageManager.ps1 - Package manager query functions (choco / winget / pipx)

# ---------------------------------------------------------------------------
# Chocolatey
# ---------------------------------------------------------------------------

function Get-ChocoUpdates {
    <#
    .SYNOPSIS
        Queries Chocolatey for outdated packages.
    .DESCRIPTION
        Runs 'choco outdated -r' and parses the pipe-delimited output.
        Returns an empty array if choco is not installed or produces no results.
        Never throws.
    .OUTPUTS
        [array] Each element: @{ Name; CurrentVersion; AvailableVersion; PackageId; Source }
    #>
    try {
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { return @() }

        $output = & choco outdated -r --no-progress 2>$null
        # Exit code 0 = up to date, 2 = outdated packages found
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) { return @() }
        if (-not $output) { return @() }

        $results = @()
        foreach ($line in $output) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\|'
            if ($parts.Count -lt 3) { continue }

            $results += @{
                Name             = $parts[0]
                CurrentVersion   = $parts[1]
                AvailableVersion = $parts[2]
                PackageId        = $parts[0]
                Source           = 'choco'
            }
        }
        return $results
    }
    catch {
        Write-Warning "Failed to check Chocolatey updates: $_"
        return @()
    }
}

# ---------------------------------------------------------------------------
# Winget
# ---------------------------------------------------------------------------

function Get-WingetUpdates {
    <#
    .SYNOPSIS
        Queries winget for available upgrades.
    .DESCRIPTION
        Runs 'winget upgrade --list' and parses the column-based text output.
        Column positions are derived from the header line to handle varying
        column widths across winget versions and locales.
        Returns an empty array if winget is not installed or produces no results.
        Never throws.
    .OUTPUTS
        [array] Each element: @{ Name; CurrentVersion; AvailableVersion; PackageId; Source }
    #>
    try {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return @() }

        $raw = & winget upgrade --list --accept-source-agreements --disable-interactivity 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }

        # Convert to string array (winget may return a single string)
        $lines = @($raw) | ForEach-Object { "$_" }

        # Locate the dash separator line to anchor column positions
        $dashIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^-{2,}') { $dashIdx = $i; break }
        }
        if ($dashIdx -lt 1) { return @() }

        $header = $lines[$dashIdx - 1]

        # Detect column start positions from the header text
        $colId        = $header.IndexOf('Id')
        $colVersion   = $header.IndexOf('Version')
        $colAvailable = $header.IndexOf('Available')
        $colSource    = $header.IndexOf('Source')

        # If any critical column is missing, abort
        if ($colId -lt 0 -or $colVersion -lt 0 -or $colAvailable -lt 0) { return @() }

        $results = @()
        for ($i = $dashIdx + 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '\d+\s+upgrades?\s+available') { continue }
            if ($line.Length -lt $colAvailable) { continue }

            $name      = $line.Substring(0, $colId).Trim()
            $id        = $line.Substring($colId, $colVersion - $colId).Trim()
            $version   = $line.Substring($colVersion, $colAvailable - $colVersion).Trim()
            $available = if ($colSource -gt 0 -and $line.Length -ge $colSource) {
                $line.Substring($colAvailable, $colSource - $colAvailable).Trim()
            } else {
                $line.Substring($colAvailable).Trim()
            }

            if ([string]::IsNullOrWhiteSpace($name) -or
                [string]::IsNullOrWhiteSpace($version)) { continue }

            $results += @{
                Name             = $name
                CurrentVersion   = $version
                AvailableVersion = $available
                PackageId        = $id
                Source           = 'winget'
            }
        }
        return $results
    }
    catch {
        Write-Warning "Failed to check winget updates: $_"
        return @()
    }
}

# ---------------------------------------------------------------------------
# Pipx
# ---------------------------------------------------------------------------

function Get-PipxTools {
    <#
    .SYNOPSIS
        Lists tools installed via pipx with their current versions.
    .DESCRIPTION
        Tries 'pipx list --json' first for reliable parsing, falls back to
        text output. Does not check for available updates (pipx has no
        built-in outdated command). Never throws.
    .OUTPUTS
        [array] Each element: @{ Name; CurrentVersion; Source = 'pipx' }
    #>
    try {
        if (-not (Get-Command pipx -ErrorAction SilentlyContinue)) { return @() }

        # Try JSON output first (pipx >= 1.1)
        $raw = & pipx list --json 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $jsonText = ($raw | Out-String).Trim()
            if ($jsonText.StartsWith('{')) {
                $json = $jsonText | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                $results = @()
                if ($json.venvs) {
                    foreach ($key in $json.venvs.Keys) {
                        $venv    = $json.venvs[$key]
                        $version = $venv.metadata.main_package.package_version
                        $results += @{
                            Name           = $key
                            CurrentVersion = $version
                            Source         = 'pipx'
                        }
                    }
                }
                return $results
            }
        }

        # Fallback: parse text output
        $raw = & pipx list 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }

        $results = @()
        foreach ($line in $raw) {
            # Lines like: "   package ruff 0.3.4, installed using Python 3.12"
            if ($line -match 'package\s+(\S+)\s+(\S+)') {
                $results += @{
                    Name           = $matches[1]
                    CurrentVersion = $matches[2].TrimEnd(',')
                    Source         = 'pipx'
                }
            }
        }
        return $results
    }
    catch {
        Write-Warning "Failed to query pipx tools: $_"
        return @()
    }
}

# ---------------------------------------------------------------------------
# Search stubs (Phase 3)
# ---------------------------------------------------------------------------

function Search-ChocolateyPackage {
    <#
    .SYNOPSIS
        Searches for packages in the Chocolatey repository.
    .PARAMETER Name
        The package name to search for.
    .OUTPUTS
        [array] Search results. Stub -- returns empty (Phase 3).
    #>
    param([string]$Name)
    return @()
}

function Search-WingetPackage {
    <#
    .SYNOPSIS
        Searches for packages in the winget repository.
    .PARAMETER Name
        The package name to search for.
    .OUTPUTS
        [array] Search results. Stub -- returns empty (Phase 3).
    #>
    param([string]$Name)
    return @()
}
