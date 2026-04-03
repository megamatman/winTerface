# Config.ps1 - Configuration file read/write

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
    .OUTPUTS
        [hashtable] Configuration object, or $null if the file does not exist.
    #>
    $configPath = Get-WinTerfaceConfigPath
    if (-not (Test-Path $configPath)) {
        return $null
    }

    try {
        $content = Get-Content -Path $configPath -Raw -ErrorAction Stop
        $config = $content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        return $config
    }
    catch {
        Write-Warning "Failed to read config from ${configPath}: $_"
        return $null
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
    $configDir = Split-Path $configPath -Parent

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
