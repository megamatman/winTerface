# WinSetup.ps1 - Interface to winSetup scripts and functions

function Test-WinSetupPath {
    <#
    .SYNOPSIS
        Validates that the configured winSetup path exists and contains
        the expected Setup-DevEnvironment.ps1 script.
    .OUTPUTS
        [bool] True if the path is valid.
    #>
    $path = $env:WINSETUP
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    if (-not (Test-Path $path)) { return $false }

    $setupScript = Join-Path $path 'Setup-DevEnvironment.ps1'
    return (Test-Path $setupScript)
}

function Get-WinSetupStatus {
    <#
    .SYNOPSIS
        Returns a status string for the winSetup connection.
    .OUTPUTS
        [hashtable] @{ Status = 'Ok'|'Error'; Message = string }
    #>
    if (Test-WinSetupPath) {
        return @{ Status = 'Ok'; Message = 'OK' }
    }

    if ([string]::IsNullOrWhiteSpace($env:WINSETUP)) {
        return @{ Status = 'Error'; Message = 'WINSETUP not set' }
    }

    return @{ Status = 'Error'; Message = 'Path invalid' }
}

function Get-PythonVersion {
    <#
    .SYNOPSIS
        Gets the active Python version from pyenv, falling back to python --version.
    .OUTPUTS
        [string] Python version string (e.g. "3.14.0") or "N/A".
    #>
    try {
        $output = & pyenv version 2>$null
        if ($LASTEXITCODE -eq 0 -and $output) {
            return ($output -split '\s')[0]
        }
    }
    catch {}

    try {
        $output = & python --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $output) {
            return ($output -replace 'Python\s*', '').Trim()
        }
    }
    catch {}

    return 'N/A'
}

function Get-ProfileHealthStatus {
    <#
    .SYNOPSIS
        Checks profile health by looking for winSetup's Test-ProfileHealth function.
    .DESCRIPTION
        Attempts to call Test-ProfileHealth if it is available in the current session.
        Returns a degraded status if winSetup is not configured or the function is
        not loaded.
    .OUTPUTS
        [hashtable] @{ Status = 'Ok'|'Warn'|'Error'; Message = string }
    #>
    if (-not (Test-WinSetupPath)) {
        return @{ Status = 'Warn'; Message = 'winSetup not configured' }
    }

    try {
        if (Get-Command 'Test-ProfileHealth' -ErrorAction SilentlyContinue) {
            $result = Test-ProfileHealth 2>$null
            if ($result) {
                return @{ Status = 'Ok'; Message = 'Healthy' }
            }
            return @{ Status = 'Warn'; Message = 'Issues detected' }
        }
        return @{ Status = 'Warn'; Message = 'Run profile check' }
    }
    catch {
        return @{ Status = 'Error'; Message = 'Check failed' }
    }
}

function Get-DevEnvironmentInfo {
    <#
    .SYNOPSIS
        Retrieves dev environment information from winSetup.
    .DESCRIPTION
        Attempts to call Show-DevEnvironment if available. Returns placeholder
        data when winSetup functions are not loaded.
    .OUTPUTS
        [hashtable] @{ Status = 'Ok'|'Unavailable'; Data = object|$null }
    #>
    try {
        if (Get-Command 'Show-DevEnvironment' -ErrorAction SilentlyContinue) {
            $info = Show-DevEnvironment 2>$null
            return @{ Status = 'Ok'; Data = $info }
        }
    }
    catch {}

    return @{ Status = 'Unavailable'; Data = $null }
}
