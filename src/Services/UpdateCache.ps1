# UpdateCache.ps1 - Background update checking and cache management

$script:UpdateCheckJob   = $null
$script:UpdateCheckState = 'Idle'   # 'Idle' | 'Checking'

# ---------------------------------------------------------------------------
# Cache file paths
# ---------------------------------------------------------------------------

function Get-UpdateCachePath {
    <#
    .SYNOPSIS
        Returns the full path to the update cache file.
    .OUTPUTS
        [string] Path to ~/.winTerface/update-cache.json
    #>
    return Join-Path $env:USERPROFILE '.winTerface' 'update-cache.json'
}

# ---------------------------------------------------------------------------
# Cache read / write
# ---------------------------------------------------------------------------

function Get-UpdateCache {
    <#
    .SYNOPSIS
        Reads the update cache from disk.
    .OUTPUTS
        [hashtable] Cache object with lastChecked and updates keys, or $null.
    #>
    $cachePath = Get-UpdateCachePath
    if (-not (Test-Path $cachePath)) { return $null }

    try {
        $content = Get-Content -Path $cachePath -Raw -ErrorAction Stop
        return ($content | ConvertFrom-Json -AsHashtable -ErrorAction Stop)
    }
    catch {
        Write-Warning "Failed to read update cache: $_"
        return $null
    }
}

function Set-UpdateCache {
    <#
    .SYNOPSIS
        Writes the update cache to disk and updates lastUpdateCheck in config.
    .PARAMETER Data
        Hashtable with lastChecked (ISO 8601 string) and updates (array).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    $cachePath = Get-UpdateCachePath
    $cacheDir  = Split-Path $cachePath -Parent

    try {
        if (-not (Test-Path $cacheDir)) {
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
        }
        # Receive-Job injects PSComputerName, RunspaceId, PSShowComputerName into
        # deserialized objects. Only lastChecked and updates are written to cache.
        # Receive-Job returns DateTime objects. Round-tripping through
        # [DateTime]::Parse() causes locale-dependent DD/MM vs MM/DD confusion.
        # Dates are stored as ISO 8601 strings via ToString('o').
        $timestamp = if ($Data.lastChecked -is [DateTime]) {
            $Data.lastChecked.ToString('o')
        } else {
            "$($Data.lastChecked)"
        }
        $clean = @{
            lastChecked = $timestamp
            updates     = @($Data.updates)
        }
        $json = $clean | ConvertTo-Json -Depth 10
        Set-Content -Path $cachePath -Value $json -Encoding UTF8 -ErrorAction Stop

        # Also update config.json timestamp
        $config = Get-WinTerfaceConfig
        if ($config) {
            $config.lastUpdateCheck = $timestamp
            Set-WinTerfaceConfig -Config $config
        }
    }
    catch {
        Write-Warning "Failed to write update cache: $_"
    }
}

# ---------------------------------------------------------------------------
# Cache queries
# ---------------------------------------------------------------------------

function Get-LastUpdateCheck {
    <#
    .SYNOPSIS
        Returns a human-readable string for when the last update check ran.
    .OUTPUTS
        [string] Relative time (e.g. "14 minutes ago") or "Never".
    #>
    $cache = Get-UpdateCache
    if (-not $cache -or -not $cache.lastChecked) {
        return 'Never'
    }

    try {
        # Handle both DateTime objects (from ConvertFrom-Json) and ISO strings.
        # [DateTimeOffset]::Parse avoids the DD/MM vs MM/DD locale ambiguity
        # that [DateTime]::Parse has with round-tripped date strings.
        $lastCheck = if ($cache.lastChecked -is [DateTime]) {
            $cache.lastChecked
        } else {
            [DateTimeOffset]::Parse($cache.lastChecked).LocalDateTime
        }
        $elapsed = (Get-Date) - $lastCheck

        if ($elapsed.TotalMinutes -lt 1)  { return 'Just now' }
        if ($elapsed.TotalMinutes -lt 60) { return "$([int]$elapsed.TotalMinutes) minutes ago" }
        if ($elapsed.TotalHours   -lt 24) { return "$([int]$elapsed.TotalHours) hours ago" }
        return "$([int]$elapsed.TotalDays) days ago"
    }
    catch {
        return 'Unknown'
    }
}

function Test-UpdateCheckNeeded {
    <#
    .SYNOPSIS
        Checks whether an update check should run based on cache age.
    .OUTPUTS
        [bool] True if no cache exists or the cache is older than the interval.
    #>
    $cache = Get-UpdateCache
    if (-not $cache -or -not $cache.lastChecked) { return $true }

    try {
        $lastCheck = if ($cache.lastChecked -is [DateTime]) {
            $cache.lastChecked
        } else {
            [DateTimeOffset]::Parse($cache.lastChecked).LocalDateTime
        }
        $config   = Get-WinTerfaceConfig
        $interval = if ($config -and $config.updateCheckIntervalHours) {
            $config.updateCheckIntervalHours
        } else { 24 }
        return ((Get-Date) - $lastCheck).TotalHours -ge $interval
    }
    catch {
        return $true
    }
}

function Get-AvailableUpdateCount {
    <#
    .SYNOPSIS
        Returns update availability info from the cache.
    .DESCRIPTION
        Reads the cache file and returns a status summary used by the Home
        screen status panel. Reflects the in-progress state when a background
        check is running.
    .OUTPUTS
        [hashtable] @{ Status = string; Count = int; Message = string }
    #>
    [OutputType([hashtable])]
    param()
    if ($script:UpdateCheckState -eq 'Checking') {
        return @{ Status = 'Checking'; Count = 0; Message = 'Checking...' }
    }

    $cache = Get-UpdateCache
    # -not @() evaluates to $true in PowerShell. A valid cache with zero updates
    # was treated as missing. Use $null -eq to distinguish 'no cache' from 'empty'.
    if (-not $cache -or $null -eq $cache.updates) {
        return @{ Status = 'Unknown'; Count = 0; Message = 'Run /check-for-updates' }
    }

    # Count only entries with a non-empty availableVersion. Pipx tools without
    # confirmed updates were inflating the count shown on the home screen.
    $count = @($cache.updates | Where-Object {
        $_.availableVersion -and $_.availableVersion -ne ''
    }).Count
    if ($count -eq 0) {
        return @{ Status = 'UpToDate'; Count = 0; Message = 'Up to date' }
    }

    $noun = if ($count -eq 1) { 'update' } else { 'updates' }
    return @{ Status = 'Available'; Count = $count; Message = "$count $noun available" }
}

# ---------------------------------------------------------------------------
# Background update check
# ---------------------------------------------------------------------------

function Start-BackgroundUpdateCheck {
    <#
    .SYNOPSIS
        Kicks off a background job that queries all package managers.
    .DESCRIPTION
        Starts a PowerShell job that dot-sources PackageManager.ps1, runs
        Get-ChocoUpdates, Get-WingetUpdates, and Get-PipxTools, and returns
        the combined results. Does nothing if a check is already running.
    .PARAMETER Force
        Bypass the cache-age check and force a fresh query.
    #>
    param([switch]$Force)

    # Don't double-up
    if ($script:UpdateCheckJob) { return }

    if (-not $Force -and -not (Test-UpdateCheckNeeded)) { return }

    $pkgMgrScript = Join-Path $script:WinTerfaceRoot 'src' 'Services' 'PackageManager.ps1'

    # Build minimal tool objects for the choco filter. $script:KnownTools is
    # not available inside Start-Job, so pass the relevant entries as an argument.
    $chocoTools = @($script:KnownTools | Where-Object { $_.Manager -eq 'choco' } | ForEach-Object {
        @{ Manager = 'choco'; PackageId = $_.PackageId }
    })

    $script:UpdateCheckState = 'Checking'
    $script:UpdateCheckJob   = Start-Job -ScriptBlock {
        param($scriptPath, $knownChocoTools)
        try {
            # Refresh PATH -- Start-Job runs with -NoProfile so choco/winget
            # may not be on PATH.
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
                        ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH', 'User')

            . $scriptPath

            $choco  = Get-ChocoUpdates -KnownTools $knownChocoTools
            $winget = Get-WingetUpdates
            $pipx   = Get-PipxTools

            # Only include pipx tools that actually have an update on PyPI
            $pipxNorm = foreach ($t in $pipx) {
                $pypiInfo = Get-PipxUpdateAvailable -Package $t.Name
                if ($pypiInfo -and $pypiInfo.UpdateAvailable) {
                    @{
                        name             = $t.Name
                        currentVersion   = $pypiInfo.Installed
                        availableVersion = $pypiInfo.Latest
                        source           = 'pipx'
                        packageId        = $t.Name
                    }
                }
            }

            $allUpdates = @()
            foreach ($u in @($choco) + @($winget)) {
                $allUpdates += @{
                    name             = $u.Name
                    currentVersion   = $u.CurrentVersion
                    availableVersion = $u.AvailableVersion
                    source           = $u.Source
                    packageId        = $u.PackageId
                }
            }
            $allUpdates += @($pipxNorm)

            return @{
                lastChecked = (Get-Date).ToString('o')
                updates     = $allUpdates
            }
        } catch {
            Write-Error "Job failed: $_"
        }
    } -ArgumentList $pkgMgrScript, $chocoTools
}

function Update-BackgroundCheckStatus {
    <#
    .SYNOPSIS
        Polls the background update-check job. Called by the 500 ms timer.
    .DESCRIPTION
        If the job has completed, receives its results, writes the cache,
        resets state, and refreshes the visible screen so the user sees
        updated counts immediately.
    #>
    if (-not $script:UpdateCheckJob) { return }

    $job = $script:UpdateCheckJob

    # Capture state before any operations -- accessing State on a disposed
    # job throws. Consistent with the try/catch pattern in other poll functions.
    $jobState = try { $job.State } catch { 'Failed' }

    if ($jobState -eq 'Completed') {
        $updateCount = 0
        try {
            $result = Receive-Job $job -ErrorAction Stop
            if ($result -and $result.lastChecked) {
                Set-UpdateCache -Data $result
                $updateCount = @($result.updates | Where-Object {
                    $_.availableVersion -and $_.availableVersion -ne ''
                }).Count
            }
        }
        catch {
            Write-Warning "Background update check failed: $_"
        }
        finally {
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            $script:UpdateCheckJob   = $null
            $script:UpdateCheckState = 'Idle'
        }

        # Writes a human-readable completion message to the output pane when
        # the background check finishes. Without this, the pane went silent
        # after the check completed and users had no confirmation it ran.
        $msg = if ($updateCount -gt 0) {
            $noun = if ($updateCount -eq 1) { 'update' } else { 'updates' }
            "Check complete -- $updateCount $noun available."
        } else {
            "Check complete -- all tools are up to date."
        }
        try { Add-UpdateOutput -Text $msg } catch {}

        # Refresh whichever screen is visible. Home uses in-place label
        # updates to avoid a full view tree rebuild (see Update-HomeStatus).
        if ($script:CurrentScreen -eq 'Home') {
            Update-HomeStatus
        }
        elseif ($script:CurrentScreen -eq 'Updates' -and
               -not $script:UpdateRunJob -and
               -not $script:IsQueuedUpdate -and
               -not $script:UpdateFlowActive) {
            Switch-Screen -ScreenName 'Updates'
        }
    }
    elseif ($jobState -eq 'Failed' -or $jobState -eq 'Stopped') {
        try { Remove-Job $job -Force -ErrorAction SilentlyContinue } catch {}
        $script:UpdateCheckJob   = $null
        $script:UpdateCheckState = 'Idle'
    }
}
