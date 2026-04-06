#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . "$PSScriptRoot\..\src\Config.ps1"
}

# ---------------------------------------------------------------------------
# Interval validation
# ---------------------------------------------------------------------------

Describe 'Config interval validation' {
    BeforeAll {
        Mock Get-WinTerfaceConfigPath { Join-Path $TestDrive 'interval-config.json' }
        Mock Test-Path { $true } -ParameterFilter { $Path -and $Path -notmatch 'config\.json' }
    }

    It 'accepts minimum valid interval (1 hour)' {
        $config = @{ winSetupPath = ''; updateCheckIntervalHours = 1 }
        $result = Save-WinTerfaceConfig -Config $config
        $result.Success | Should -BeTrue
    }

    It 'accepts maximum valid interval (168 hours)' {
        $config = @{ winSetupPath = ''; updateCheckIntervalHours = 168 }
        $result = Save-WinTerfaceConfig -Config $config
        $result.Success | Should -BeTrue
    }

    It 'accepts a mid-range interval (24 hours)' {
        $config = @{ winSetupPath = ''; updateCheckIntervalHours = 24 }
        $result = Save-WinTerfaceConfig -Config $config
        $result.Success | Should -BeTrue
    }

    It 'rejects zero interval' {
        $config = @{ winSetupPath = ''; updateCheckIntervalHours = 0 }
        $result = Save-WinTerfaceConfig -Config $config
        $result.Success | Should -BeFalse
        $result.Errors | Should -Contain 'Update check interval must be 1-168 hours.'
    }

    It 'rejects negative interval' {
        $config = @{ winSetupPath = ''; updateCheckIntervalHours = -5 }
        $result = Save-WinTerfaceConfig -Config $config
        $result.Success | Should -BeFalse
        $result.Errors | Should -Contain 'Update check interval must be 1-168 hours.'
    }

    It 'rejects interval above maximum (169)' {
        $config = @{ winSetupPath = ''; updateCheckIntervalHours = 169 }
        $result = Save-WinTerfaceConfig -Config $config
        $result.Success | Should -BeFalse
    }

    It 'rejects non-integer interval' {
        $config = @{ winSetupPath = ''; updateCheckIntervalHours = 'abc' }
        $result = Save-WinTerfaceConfig -Config $config
        $result.Success | Should -BeFalse
    }
}

# ---------------------------------------------------------------------------
# Path validation
# ---------------------------------------------------------------------------

Describe 'Config path validation' {
    BeforeAll {
        Mock Get-WinTerfaceConfigPath { Join-Path $TestDrive 'path-config.json' }
    }

    It 'accepts a valid path containing Setup-DevEnvironment.ps1' {
        $dir = Join-Path $TestDrive 'valid-ws'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'Setup-DevEnvironment.ps1') -Value '# stub'

        $config = @{ winSetupPath = $dir; updateCheckIntervalHours = 24 }
        $result = Save-WinTerfaceConfig -Config $config
        $result.Success | Should -BeTrue
    }

    It 'rejects a non-existent path with a clear error' {
        $config = @{ winSetupPath = 'C:\does\not\exist\anywhere'; updateCheckIntervalHours = 24 }
        $result = Save-WinTerfaceConfig -Config $config
        $result.Success | Should -BeFalse
        $result.Errors[0] | Should -Match 'does not exist'
    }

    It 'rejects a path that exists but lacks Setup-DevEnvironment.ps1' {
        $dir = Join-Path $TestDrive 'no-setup'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $config = @{ winSetupPath = $dir; updateCheckIntervalHours = 24 }
        $result = Save-WinTerfaceConfig -Config $config
        $result.Success | Should -BeFalse
        $result.Errors[0] | Should -Match 'Setup-DevEnvironment.ps1 not found'
    }

    It 'accepts empty path (skips path validation)' {
        $config = @{ winSetupPath = ''; updateCheckIntervalHours = 24 }
        $result = Save-WinTerfaceConfig -Config $config
        $result.Success | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# Config read/write round-trip
# ---------------------------------------------------------------------------

Describe 'Config read/write round-trip' {
    BeforeAll {
        Mock Get-WinTerfaceConfigPath { Join-Path $TestDrive 'roundtrip-config.json' }
    }

    BeforeEach {
        Remove-Item (Get-WinTerfaceConfigPath) -ErrorAction SilentlyContinue
    }

    It 'round-trips all config values through write and read' {
        $original = @{
            winSetupPath             = 'C:\test\winSetup'
            lastUpdateCheck          = '2026-04-06T12:00:00.0000000+01:00'
            updateCheckIntervalHours = 48
        }
        Set-WinTerfaceConfig -Config $original

        $loaded = Get-WinTerfaceConfig
        $loaded.winSetupPath | Should -Be 'C:\test\winSetup'
        # ConvertFrom-Json may deserialise ISO 8601 strings as DateTime objects.
        # Verify the date value round-trips rather than exact string equality.
        $parsedDate = if ($loaded.lastUpdateCheck -is [DateTime]) {
            $loaded.lastUpdateCheck
        } else {
            [DateTimeOffset]::Parse($loaded.lastUpdateCheck).LocalDateTime
        }
        $expectedDate = [DateTimeOffset]::Parse('2026-04-06T12:00:00.0000000+01:00').LocalDateTime
        [Math]::Abs(($parsedDate - $expectedDate).TotalSeconds) | Should -BeLessThan 2
        $loaded.updateCheckIntervalHours | Should -Be 48
    }

    It 'fills in defaults for missing keys' {
        # Write a config with only one key
        $partial = @{ winSetupPath = 'C:\partial' }
        Set-WinTerfaceConfig -Config $partial

        $loaded = Get-WinTerfaceConfig
        $loaded.winSetupPath | Should -Be 'C:\partial'
        # Missing keys should get defaults
        $loaded.updateCheckIntervalHours | Should -Be 24
    }

    It 'returns defaults when config file does not exist' {
        $loaded = Get-WinTerfaceConfig
        $loaded | Should -Not -BeNullOrEmpty
        $loaded.updateCheckIntervalHours | Should -Be 24
    }

    It 'ignores unknown keys without throwing' {
        $configPath = Get-WinTerfaceConfigPath
        $configDir = Split-Path $configPath -Parent
        if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
        $json = '{"winSetupPath":"C:\\test","updateCheckIntervalHours":12,"unknownKey":"value","anotherUnknown":42}'
        Set-Content -Path $configPath -Value $json -Encoding UTF8

        { Get-WinTerfaceConfig } | Should -Not -Throw
        $loaded = Get-WinTerfaceConfig
        $loaded.winSetupPath | Should -Be 'C:\test'
        $loaded.updateCheckIntervalHours | Should -Be 12
    }
}
