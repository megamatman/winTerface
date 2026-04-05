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

function Get-PipxUpdateAvailable {
    <#
    .SYNOPSIS
        Checks PyPI for the latest version of a pipx-installed package.
    .DESCRIPTION
        Queries installed version via pipx runpip and latest from PyPI JSON API.
        Populates real availableVersion for pipx tools in the background check,
        replacing the blank '---' that pipx list alone provides.  Never throws.
    .PARAMETER Package
        The package name to check.
    .OUTPUTS
        [hashtable] @{ Package; Installed; Latest; UpdateAvailable }
        Returns $null if the check cannot be performed.
    #>
    param([string]$Package)

    try {
        # Installed version via pipx's own pip
        $showOutput = & pipx runpip $Package show $Package 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $showOutput) { return $null }

        $installed = $showOutput |
            Where-Object { $_ -match '^Version:' } |
            ForEach-Object { ($_ -split '\s+', 2)[1].Trim() } |
            Select-Object -First 1
        if (-not $installed) { return $null }

        # Latest version from PyPI
        $pypi = Invoke-RestMethod "https://pypi.org/pypi/$Package/json" -ErrorAction Stop
        $latest = $pypi.info.version
        if (-not $latest) { return $null }

        return @{
            Package         = $Package
            Installed       = $installed
            Latest          = $latest
            UpdateAvailable = $installed -ne $latest
        }
    }
    catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# Package descriptions (lazy fetch)
# ---------------------------------------------------------------------------

function Get-ChocoPackageDescription {
    <#
    .SYNOPSIS
        Fetches the summary or description for a Chocolatey package.
    .DESCRIPTION
        Runs 'choco info <Id>' and parses the Summary or Description field.
        Returns the summary text, or empty string on failure or timeout.
    .PARAMETER Id
        The Chocolatey package identifier.
    .OUTPUTS
        [string] Package summary/description, or empty string.
    #>
    param([string]$Id)

    try {
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { return '' }

        $out = & choco info $Id --no-progress 2>$null | Out-String
        if (-not $out) { return '' }

        # Prefer Summary (one-liner), fall back to Description (multi-line)
        if ($out -match 'Summary:\s*(.+)') {
            return $Matches[1].Trim()
        }
        if ($out -match 'Description:\s*(.+)') {
            $desc = $Matches[1].Trim()
            if ($desc.Length -gt 200) { $desc = $desc.Substring(0, 197) + '...' }
            return $desc
        }
        return ''
    }
    catch { return '' }
}

function Get-WingetPackageDescription {
    <#
    .SYNOPSIS
        Fetches the description for a winget package.
    .DESCRIPTION
        Runs 'winget show --id <Id> --exact' and parses the Description field.
        Returns the description text, or empty string on failure or timeout.
    .PARAMETER Id
        The winget package identifier.
    .OUTPUTS
        [string] Package description, or empty string.
    #>
    param([string]$Id)

    try {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return '' }

        $out = & winget show --id $Id --exact --disable-interactivity 2>$null | Out-String
        if (-not $out) { return '' }

        if ($out -match 'Description:\s*(.+)') {
            $desc = $Matches[1].Trim()
            if ($desc.Length -gt 200) { $desc = $desc.Substring(0, 197) + '...' }
            return $desc
        }
        return ''
    }
    catch { return '' }
}

# ---------------------------------------------------------------------------
# Package search
# ---------------------------------------------------------------------------

function Search-ChocolateyPackage {
    <#
    .SYNOPSIS
        Searches for packages in the Chocolatey repository.
    .DESCRIPTION
        Runs 'choco search <name> -r' and parses the pipe-delimited output.
        Never throws.
    .PARAMETER Name
        The package name to search for.
    .OUTPUTS
        [array] Each element: @{ Name; Version; PackageId; Source = 'choco' }
    #>
    param([string]$Name)

    try {
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { return @() }
        if ([string]::IsNullOrWhiteSpace($Name)) { return @() }

        $raw = & choco search $Name -r --no-progress 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }

        $results = @()
        foreach ($line in $raw) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\|'
            if ($parts.Count -lt 2) { continue }

            $results += @{
                Name      = $parts[0]
                Version   = $parts[1]
                PackageId = $parts[0]
                Source    = 'choco'
            }
        }
        return $results
    }
    catch {
        Write-Warning "Chocolatey search failed: $_"
        return @()
    }
}

function Search-WingetPackage {
    <#
    .SYNOPSIS
        Searches for packages in the winget repository.
    .DESCRIPTION
        Runs 'winget search <name>' and parses column-based output using
        the header line to detect column positions.  Never throws.
    .PARAMETER Name
        The package name to search for.
    .OUTPUTS
        [array] Each element: @{ Name; Version; PackageId; Source = 'winget' }
    #>
    param([string]$Name)

    try {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return @() }
        if ([string]::IsNullOrWhiteSpace($Name)) { return @() }

        $raw = & winget search $Name --accept-source-agreements --disable-interactivity 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }

        $lines = @($raw) | ForEach-Object { "$_" }

        # Find dash separator
        $dashIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^-{2,}') { $dashIdx = $i; break }
        }
        if ($dashIdx -lt 1) { return @() }

        $header    = $lines[$dashIdx - 1]
        $colId     = $header.IndexOf('Id')
        $colVer    = $header.IndexOf('Version')
        $colSource = $header.IndexOf('Source')
        if ($colId -lt 0 -or $colVer -lt 0) { return @() }

        $results = @()
        for ($i = $dashIdx + 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '\d+\s+packages?\s+found') { continue }
            if ($line.Length -lt $colVer) { continue }

            $name    = $line.Substring(0, $colId).Trim()
            $id      = $line.Substring($colId, $colVer - $colId).Trim()
            $version = if ($colSource -gt 0 -and $line.Length -ge $colSource) {
                $line.Substring($colVer, $colSource - $colVer).Trim()
            } else {
                $line.Substring($colVer).Trim()
            }

            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $results += @{
                Name      = $name
                Version   = $version
                PackageId = $id
                Source    = 'winget'
            }
        }
        return $results
    }
    catch {
        Write-Warning "Winget search failed: $_"
        return @()
    }
}

# ---------------------------------------------------------------------------
# PyPI
# ---------------------------------------------------------------------------

function Search-PyPI {
    <#
    .SYNOPSIS
        Searches PyPI for packages matching the given term.
    .DESCRIPTION
        Stage 1: exact name lookup via the PyPI JSON API.
        Stage 2: tries common name variations (python-<term>, py<term>,
        <term>-cli, <term>-python) as additional exact lookups. PyPI has
        no public fuzzy search API, so this provides partial matching
        by convention. Duplicates are removed. Limited to 5 additional
        results to avoid excessive API calls.
    .PARAMETER Term
        The package name or search term to look up.
    .OUTPUTS
        [array] Each element: @{ Name; Id; Version; Description; Source = 'pypi' }
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Term
    )

    $results = @()
    $seen = @{}

    # Helper: query a single package and return a result hashtable or $null
    function Get-PyPIPackage {
        param([string]$PackageName)
        try {
            $response = Invoke-RestMethod "https://pypi.org/pypi/$PackageName/json" -TimeoutSec 10 -ErrorAction Stop
            $info = $response.info
            if (-not $info) { return $null }

            # Description fallback chain: summary -> truncated description -> default
            $desc = $info.summary
            if ([string]::IsNullOrWhiteSpace($desc) -and $info.description) {
                $desc = $info.description
                if ($desc.Length -gt 200) { $desc = $desc.Substring(0, 197) + '...' }
            }
            if ([string]::IsNullOrWhiteSpace($desc)) { $desc = 'No description available.' }

            return @{
                Name        = $info.name
                Id          = $info.name
                Version     = $info.version
                Description = $desc
                Source      = 'pypi'
            }
        }
        catch { return $null }
    }

    try {
        # Stage 1: exact name lookup
        $exact = Get-PyPIPackage -PackageName $Term
        if ($exact) {
            $results += $exact
            $seen[$exact.Name.ToLower()] = $true
        }

        # Stage 2: common name variations (PyPI has no fuzzy search API)
        $termLower = $Term.ToLower()
        $variations = @(
            "python-$termLower"
            "py$termLower"
            "$termLower-cli"
            "$termLower-python"
            "$termLower-tool"
        )

        $maxAdditional = 5
        $added = 0
        foreach ($v in $variations) {
            if ($added -ge $maxAdditional) { break }
            if ($seen.ContainsKey($v)) { continue }
            $pkg = Get-PyPIPackage -PackageName $v
            if ($pkg -and -not $seen.ContainsKey($pkg.Name.ToLower())) {
                $results += $pkg
                $seen[$pkg.Name.ToLower()] = $true
                $added++
            }
        }

        return $results
    }
    catch {
        Write-Warning "PyPI search failed: $_"
        return $results
    }
}
