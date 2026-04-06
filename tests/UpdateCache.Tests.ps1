#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . "$PSScriptRoot\..\src\Config.ps1"
    . "$PSScriptRoot\..\src\Services\UpdateCache.ps1"
}

Describe 'UpdateCache date round-tripping' {
    BeforeAll {
        # Redirect cache and config paths to $TestDrive
        Mock Get-UpdateCachePath { Join-Path $TestDrive 'update-cache.json' }
        Mock Get-WinTerfaceConfigPath { Join-Path $TestDrive 'config.json' }
    }

    It 'round-trips a DateTime through write and read' {
        $now = Get-Date
        Set-UpdateCache -Data @{ lastChecked = $now; updates = @() }

        $cache = Get-UpdateCache
        $cache | Should -Not -BeNullOrEmpty
        $cache.lastChecked | Should -Not -BeNullOrEmpty

        # ConvertFrom-Json may return a DateTime or a string depending on PS version.
        # Handle both: parse if string, use directly if DateTime.
        $parsed = if ($cache.lastChecked -is [DateTime]) {
            $cache.lastChecked
        } else {
            [DateTimeOffset]::Parse($cache.lastChecked).LocalDateTime
        }
        $diff = [Math]::Abs(($parsed - $now).TotalSeconds)
        $diff | Should -BeLessThan 2
    }

    It 'writes ISO 8601 format to the cache file' {
        Set-UpdateCache -Data @{ lastChecked = (Get-Date); updates = @() }

        # Read the raw file text (not parsed by ConvertFrom-Json) to verify format
        $raw = Get-Content (Get-UpdateCachePath) -Raw
        # The lastChecked value should contain a T separator (ISO 8601 marker)
        $raw | Should -Match '"lastChecked":\s*"[^"]*T[^"]*"'
    }

    It 'round-trips correctly under a non-English locale (de-DE)' {
        $savedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new('de-DE')

            $now = Get-Date
            Set-UpdateCache -Data @{ lastChecked = $now; updates = @() }

            $cache = Get-UpdateCache
            $parsed = if ($cache.lastChecked -is [DateTime]) {
                $cache.lastChecked
            } else {
                [DateTimeOffset]::Parse($cache.lastChecked).LocalDateTime
            }
            $diff = [Math]::Abs(($parsed - $now).TotalSeconds)
            $diff | Should -BeLessThan 2
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $savedCulture
        }
    }

    It 'round-trips an ISO 8601 string preserving the date value' {
        $isoString = '2026-04-06T14:30:00.0000000+01:00'
        Set-UpdateCache -Data @{ lastChecked = $isoString; updates = @() }

        $cache = Get-UpdateCache
        # ConvertFrom-Json may return a DateTime object from the ISO string.
        # Verify the date value round-trips, not the exact string representation.
        $parsed = if ($cache.lastChecked -is [DateTime]) {
            $cache.lastChecked
        } else {
            [DateTimeOffset]::Parse($cache.lastChecked).LocalDateTime
        }
        $expected = [DateTimeOffset]::Parse($isoString).LocalDateTime
        $diff = [Math]::Abs(($parsed - $expected).TotalSeconds)
        $diff | Should -BeLessThan 2
    }
}

Describe 'UpdateCache staleness check' {
    BeforeAll {
        Mock Get-UpdateCachePath { Join-Path $TestDrive 'stale-cache.json' }
        Mock Get-WinTerfaceConfigPath { Join-Path $TestDrive 'stale-config.json' }
    }

    BeforeEach {
        # Clean up between tests
        Remove-Item (Get-UpdateCachePath) -ErrorAction SilentlyContinue
        Remove-Item (Get-WinTerfaceConfigPath) -ErrorAction SilentlyContinue
    }

    It 'returns true (stale) when cache file is missing' {
        Test-UpdateCheckNeeded | Should -BeTrue
    }

    It 'returns false (fresh) when cache was written less than interval ago' {
        # Write a cache with current timestamp
        Set-UpdateCache -Data @{ lastChecked = (Get-Date); updates = @() }
        # Config defaults to 24h interval

        Test-UpdateCheckNeeded | Should -BeFalse
    }

    It 'returns true (stale) when cache is older than the interval' {
        $old = (Get-Date).AddHours(-25)
        Set-UpdateCache -Data @{ lastChecked = $old; updates = @() }

        Test-UpdateCheckNeeded | Should -BeTrue
    }

    It 'returns true (stale) when cache date is unparseable' {
        $cachePath = Get-UpdateCachePath
        $cacheDir = Split-Path $cachePath -Parent
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        Set-Content -Path $cachePath -Value '{"lastChecked":"not-a-date","updates":[]}' -Encoding UTF8

        Test-UpdateCheckNeeded | Should -BeTrue
    }
}

Describe 'UpdateCache structure' {
    BeforeAll {
        Mock Get-UpdateCachePath { Join-Path $TestDrive 'struct-cache.json' }
        Mock Get-WinTerfaceConfigPath { Join-Path $TestDrive 'struct-config.json' }
    }

    It 'writes valid JSON' {
        Set-UpdateCache -Data @{ lastChecked = (Get-Date); updates = @() }

        $raw = Get-Content (Get-UpdateCachePath) -Raw
        { $raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'written cache contains lastChecked and updates keys' {
        Set-UpdateCache -Data @{ lastChecked = (Get-Date); updates = @() }

        $cache = Get-UpdateCache
        $cache.Keys | Should -Contain 'lastChecked'
        $cache.Keys | Should -Contain 'updates'
    }

    It 'writes and reads back empty updates correctly' {
        Set-UpdateCache -Data @{ lastChecked = (Get-Date); updates = @() }

        $cache = Get-UpdateCache
        @($cache.updates).Count | Should -Be 0
    }

    It 'writes and reads back non-empty updates correctly' {
        $updates = @(
            @{ name = 'git'; currentVersion = '2.44'; availableVersion = '2.45'; source = 'choco' }
        )
        Set-UpdateCache -Data @{ lastChecked = (Get-Date); updates = $updates }

        $cache = Get-UpdateCache
        @($cache.updates).Count | Should -Be 1
        $cache.updates[0].name | Should -Be 'git'
    }
}
