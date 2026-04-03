# UpdateCache.ps1 - Update check caching logic

function Get-LastUpdateCheck {
    <#
    .SYNOPSIS
        Returns a human-readable string describing when the last update check ran.
    .OUTPUTS
        [string] Relative time string (e.g. "2 hours ago") or "Never".
    #>
    $config = Get-WinTerfaceConfig
    if (-not $config -or -not $config.lastUpdateCheck) {
        return 'Never'
    }

    try {
        $lastCheck = [DateTime]::Parse($config.lastUpdateCheck)
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
        Checks if an update check should be performed based on the configured interval.
    .OUTPUTS
        [bool] True if the interval has elapsed since the last check.
    #>
    $config = Get-WinTerfaceConfig
    if (-not $config -or -not $config.lastUpdateCheck) {
        return $true
    }

    try {
        $lastCheck = [DateTime]::Parse($config.lastUpdateCheck)
        $interval  = if ($config.updateCheckIntervalHours) { $config.updateCheckIntervalHours } else { 24 }
        $elapsed   = (Get-Date) - $lastCheck
        return ($elapsed.TotalHours -ge $interval)
    }
    catch {
        return $true
    }
}

function Get-AvailableUpdateCount {
    <#
    .SYNOPSIS
        Returns information about available updates.
    .DESCRIPTION
        Placeholder for Phase 2. Will eventually query choco outdated,
        winget upgrade --list, and pipx list.
    .OUTPUTS
        [hashtable] @{ Status = string; Count = int; Message = string }
    #>
    return @{
        Status  = 'Unknown'
        Count   = 0
        Message = 'Run /check-for-updates'
    }
}
