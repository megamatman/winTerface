# Config.ps1 - Configuration file read/write with validation

function Get-WinTerfaceConfigPath {
    <#
    .SYNOPSIS
        Returns the full path to the winTerface config file.
    .OUTPUTS
        [string] Path to ~/.winTerface/config.json
    #>
    return Join-Path $env:USERPROFILE '.winTerface' 'config.json'
}

function Get-WinTerfaceConfig {
    <#
    .SYNOPSIS
        Reads the winTerface configuration from disk.
    .DESCRIPTION
        Never returns null. Returns a hashtable with sensible defaults if
        the file does not exist or cannot be read.
    .OUTPUTS
        [hashtable] Configuration object.
    #>
    [OutputType([hashtable])]
    param()
    $defaults = @{
        winSetupPath             = if ($env:WINSETUP) { $env:WINSETUP } else { '' }
        lastUpdateCheck          = $null
        updateCheckIntervalHours = 24
    }

    $configPath = Get-WinTerfaceConfigPath
    if (-not (Test-Path $configPath)) { return $defaults }

    try {
        $content = Get-Content -Path $configPath -Raw -ErrorAction Stop
        $config  = $content | ConvertFrom-Json -AsHashtable -ErrorAction Stop

        # Merge with defaults so missing keys are filled in
        foreach ($key in $defaults.Keys) {
            if (-not $config.ContainsKey($key)) {
                $config[$key] = $defaults[$key]
            }
        }
        return $config
    }
    catch {
        Write-Warning "Failed to read config from ${configPath}: $_"
        return $defaults
    }
}

function Set-WinTerfaceConfig {
    <#
    .SYNOPSIS
        Writes the winTerface configuration to disk.
    .PARAMETER Config
        The configuration hashtable to save.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $configPath = Get-WinTerfaceConfigPath
    $configDir  = Split-Path $configPath -Parent

    try {
        if (-not (Test-Path $configDir)) {
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
        }
        $json = $Config | ConvertTo-Json -Depth 10
        Set-Content -Path $configPath -Value $json -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        throw "Failed to write config to ${configPath}: $_"
    }
}

function Save-WinTerfaceConfig {
    <#
    .SYNOPSIS
        Validates all config fields and writes to disk if valid.
    .PARAMETER Config
        The configuration hashtable to validate and save.
    .OUTPUTS
        [hashtable] @{ Success = bool; Errors = string[] }
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $errors = @()

    # Validate winSetupPath
    if ($Config.winSetupPath) {
        if (-not (Test-Path $Config.winSetupPath)) {
            $errors += "winSetup path does not exist: $($Config.winSetupPath)"
        }
        elseif (-not (Test-Path (Join-Path $Config.winSetupPath 'Setup-DevEnvironment.ps1'))) {
            $errors += "Setup-DevEnvironment.ps1 not found in: $($Config.winSetupPath)"
        }
    }

    # Validate updateCheckIntervalHours
    $interval = $Config.updateCheckIntervalHours
    if ($null -ne $interval) {
        $intVal = $interval -as [int]
        if ($null -eq $intVal -or $intVal -lt 1 -or $intVal -gt 168) {
            $errors += "Update check interval must be 1-168 hours."
        }
    }

    if ($errors.Count -gt 0) {
        return @{ Success = $false; Errors = $errors }
    }

    try {
        Set-WinTerfaceConfig -Config $Config
        return @{ Success = $true; Errors = @() }
    }
    catch {
        return @{ Success = $false; Errors = @("Save failed: $_") }
    }
}
