#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    # Dot-source the config service (Get-WinTerfaceConfig) and WinSetup service
    . "$PSScriptRoot\..\src\Config.ps1"
    . "$PSScriptRoot\..\src\Services\WinSetup.ps1"
}

Describe 'Get-KnownToolsFromRegistry' {
    BeforeAll {
        # Fixture: minimal $PackageRegistry matching the winSetup format
        $script:RegistryFixture = @'
$PackageRegistry = @{
    "vscode"      = @{ Manager = "choco";  Id = "vscode" }
    "ruff"        = @{ Manager = "pipx";   Id = "ruff" }
    "fzf"         = @{ Manager = "winget"; Id = "junegunn.fzf" }
    "ohmyposh"    = @{ Manager = "winget"; Id = "JanDeDobbeleer.OhMyPosh" }
    "psfzf"       = @{ Manager = "module"; Id = "PSFzf" }
    "pyenv"       = @{ Manager = "pyenv";  Id = "pyenv-win" }
}
'@
    }

    It 'parses registry entries and returns tools with expected properties' {
        $dir = Join-Path $TestDrive 'ws-parse'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'Update-DevEnvironment.ps1') -Value $script:RegistryFixture
        $env:WINSETUP = $dir

        $result = @(Get-KnownToolsFromRegistry)

        # Should contain bootstrap tools + parsed entries (minus psfzf module)
        $names = $result | ForEach-Object { $_.Name }
        $names | Should -Contain 'Chocolatey'    # bootstrap
        $names | Should -Contain 'pipx'          # bootstrap
        $names | Should -Contain 'VS Code'       # from metadata for vscode key
        $names | Should -Contain 'ruff'
        $names | Should -Contain 'fzf'
        $names | Should -Contain 'Oh My Posh'    # from metadata for ohmyposh key
        $names | Should -Contain 'pyenv'
    }

    It 'excludes PSFzf module entries' {
        $dir = Join-Path $TestDrive 'ws-module'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'Update-DevEnvironment.ps1') -Value $script:RegistryFixture
        $env:WINSETUP = $dir

        $result = @(Get-KnownToolsFromRegistry)

        $names = $result | ForEach-Object { $_.Name }
        $names | Should -Not -Contain 'psfzf'
        $names | Should -Not -Contain 'PSFzf'
    }

    It 'maps Command from metadata where registry key differs from CLI binary' {
        $dir = Join-Path $TestDrive 'ws-command'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'Update-DevEnvironment.ps1') -Value $script:RegistryFixture
        $env:WINSETUP = $dir

        $result = @(Get-KnownToolsFromRegistry)

        ($result | Where-Object { $_.Name -eq 'VS Code' }).Command | Should -Be 'code'
        ($result | Where-Object { $_.Name -eq 'Oh My Posh' }).Command | Should -Be 'oh-my-posh'
    }

    It 'includes Desc property for all tools' {
        $dir = Join-Path $TestDrive 'ws-desc'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'Update-DevEnvironment.ps1') -Value $script:RegistryFixture
        $env:WINSETUP = $dir

        $result = @(Get-KnownToolsFromRegistry)

        foreach ($tool in $result) {
            $tool.Desc | Should -Not -BeNullOrEmpty -Because "$($tool.Name) should have a description"
        }
    }

    It 'returns only bootstrap tools when registry file is missing' {
        $env:WINSETUP = Join-Path $TestDrive 'nonexistent-dir'

        $result = @(Get-KnownToolsFromRegistry)

        # Should contain only bootstrap tools
        $result.Count | Should -Be 2
        $result[0].Name | Should -Be 'Chocolatey'
        $result[1].Name | Should -Be 'pipx'
    }

    It 'returns only bootstrap tools when WINSETUP is not set' {
        $savedWinSetup = $env:WINSETUP
        $env:WINSETUP = $null
        # Also ensure Get-WinTerfaceConfig returns no path
        Mock Get-WinTerfaceConfig { @{ winSetupPath = '' } }

        try {
            $result = @(Get-KnownToolsFromRegistry)

            $result.Count | Should -Be 2
            $result[0].Name | Should -Be 'Chocolatey'
        }
        finally {
            $env:WINSETUP = $savedWinSetup
        }
    }

    It 'handles tools added by the wizard that are not in metadata' {
        $fixture = @'
$PackageRegistry = @{
    "customtool" = @{ Manager = "choco"; Id = "customtool" }
}
'@
        $dir = Join-Path $TestDrive 'ws-custom'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'Update-DevEnvironment.ps1') -Value $fixture
        $env:WINSETUP = $dir

        $result = @(Get-KnownToolsFromRegistry)

        $custom = $result | Where-Object { $_.Name -eq 'customtool' }
        $custom | Should -Not -BeNullOrEmpty
        $custom.Command | Should -Be 'customtool'
        $custom.Manager | Should -Be 'choco'
        $custom.Desc | Should -Be 'customtool tool.'
    }
}

Describe 'VSCODE_OPEN sentinel handling' {
    BeforeAll {
        $script:AppSource = Get-Content "$PSScriptRoot\..\src\App.ps1" -Raw
        $script:WinSetupSource = Get-Content "$PSScriptRoot\..\src\Services\WinSetup.ps1" -Raw
    }

    It 'update job invocations pass -NoWait to Update-DevEnvironment.ps1' {
        # Both full update and per-package jobs should pass -NoWait (now inside pwsh -Command strings)
        $script:WinSetupSource | Should -Match '-NoWait -JobMode'
        $script:WinSetupSource | Should -Match '-Package.*-NoWait -JobMode'
    }

    It 'poll function detects VSCODE_OPEN sentinel and outputs warning message' {
        $script:AppSource | Should -Match 'VSCODE_OPEN'
        $script:AppSource | Should -Match 'VS Code is open\. Close it and retry the update\.'
    }

    It 'poll function stops and removes the job when sentinel is detected' {
        # After detecting VSCODE_OPEN, the code should null out UpdateRunJob
        $script:AppSource | Should -Match 'Remove-Job \$job'
        $script:AppSource | Should -Match '\$script:UpdateRunJob\s*=\s*\$null'
    }

    It 're-enables update action by resetting queue state after detection' {
        $script:AppSource | Should -Match '\$script:IsQueuedUpdate\s*=\s*\$false'
    }
}

Describe 'Get-ProfileDriftStatus' {
    BeforeAll {
        $script:ProfileSource = "# profile content`nSet-Alias lg lazygit`n"
        $script:LauncherBlock = @"

# winTerface launcher
function Invoke-WinTerface {
    & "`$env:WINTERFACE\winTerface.ps1" @args
}
Set-Alias wti Invoke-WinTerface
"@
    }

    It 'reports InSync when deployed profile has launcher block but no other drift' {
        $dir = Join-Path $TestDrive 'drift-launcher'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'profile.ps1') -Value $script:ProfileSource -NoNewline
        $env:WINSETUP = $dir

        $deployedPath = Join-Path $TestDrive 'profile-with-launcher.ps1'
        Set-Content -Path $deployedPath -Value ($script:ProfileSource + $script:LauncherBlock) -NoNewline

        $savedProfile = $global:PROFILE
        $global:PROFILE = $deployedPath
        try {
            $result = Get-ProfileDriftStatus
            $result.Status | Should -Be 'InSync'
        }
        finally {
            $global:PROFILE = $savedProfile
        }
    }

    It 'reports InSync when deployed profile has no launcher block and matches source' {
        $dir = Join-Path $TestDrive 'drift-no-launcher'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'profile.ps1') -Value $script:ProfileSource -NoNewline
        $env:WINSETUP = $dir

        $deployedPath = Join-Path $TestDrive 'profile-no-launcher.ps1'
        Set-Content -Path $deployedPath -Value $script:ProfileSource -NoNewline

        $savedProfile = $global:PROFILE
        $global:PROFILE = $deployedPath
        try {
            $result = Get-ProfileDriftStatus
            $result.Status | Should -Be 'InSync'
        }
        finally {
            $global:PROFILE = $savedProfile
        }
    }

    It 'reports Drifted for genuine drift even when launcher block is present' {
        $dir = Join-Path $TestDrive 'drift-genuine'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'profile.ps1') -Value $script:ProfileSource -NoNewline
        $env:WINSETUP = $dir

        $driftContent = $script:ProfileSource + "# user added this line`n" + $script:LauncherBlock
        $deployedPath = Join-Path $TestDrive 'profile-genuine-drift.ps1'
        Set-Content -Path $deployedPath -Value $driftContent -NoNewline

        $savedProfile = $global:PROFILE
        $global:PROFILE = $deployedPath
        try {
            $result = Get-ProfileDriftStatus
            $result.Status | Should -Be 'Drifted'
            $result.DiffText | Should -Match 'user added this line'
            $result.DiffText | Should -Not -Match 'Invoke-WinTerface'
        }
        finally {
            $global:PROFILE = $savedProfile
        }
    }
}

Describe 'UI polish' {
    BeforeAll {
        $script:UpdatesSource = Get-Content "$PSScriptRoot\..\src\Screens\Updates.ps1" -Raw
        $script:ConfigSource  = Get-Content "$PSScriptRoot\..\src\Screens\Config.ps1" -Raw
    }

    It 'Updates screen triggers background check when last check was over 60 minutes ago' {
        $script:UpdatesSource | Should -Match 'TotalMinutes.*-ge\s*60'
        $script:UpdatesSource | Should -Match 'Start-BackgroundUpdateCheck\s+-Force'
    }

    It 'Updates screen does not duplicate staleness logic' {
        # Should parse lastChecked directly, not call Test-UpdateCheckNeeded
        # (which uses the configurable interval, not the 60-minute threshold)
        $script:UpdatesSource | Should -Match 'Get-UpdateCache'
        $script:UpdatesSource | Should -Match 'lastChecked'
    }

    It 'Updates hint bar has F5 before F6' {
        $hintMatch = [regex]::Match($script:UpdatesSource, '\[F5\].*\[F6\]')
        $hintMatch.Success | Should -BeTrue
        # F6 should NOT appear before F5 in any hint string
        $badOrder = [regex]::Match($script:UpdatesSource, '\[F6\].*\[F5\].*\[Esc\]')
        $badOrder.Success | Should -BeFalse
    }

    It 'Config screen detail pane is labelled Detail not Content' {
        $script:ConfigSource | Should -Match "FrameView\]::new\(`"Detail`"\)"
        $script:ConfigSource | Should -Not -Match "FrameView\]::new\(`"Content`"\)"
    }
}

Describe 'Job output hygiene' {
    BeforeAll {
        $script:SrcFiles = Get-ChildItem "$PSScriptRoot\..\src" -Recurse -Filter '*.ps1' |
            ForEach-Object { @{ Path = $_.FullName; Content = (Get-Content $_.FullName -Raw) } }
    }

    It 'no [job] prefixed Write-Host calls exist in source files' {
        foreach ($f in $script:SrcFiles) {
            $jobLines = ($f.Content -split "`n") |
                Where-Object { $_ -match 'Write-Host.*\[job\]' }
            $jobLines | Should -BeNullOrEmpty -Because "$($f.Path) should not have [job] Write-Host lines"
        }
    }

    It 'all Receive-Job calls include 6>$null' {
        foreach ($f in $script:SrcFiles) {
            $receiveLines = ($f.Content -split "`n") |
                Where-Object { $_ -match 'Receive-Job' -and $_ -notmatch '^\s*#' }
            foreach ($line in $receiveLines) {
                $line | Should -Match '6>\$null' -Because "Receive-Job in $($f.Path) must suppress stream 6"
            }
        }
    }
}

Describe 'Subprocess isolation' {
    BeforeAll {
        $script:WinSetupSrc = Get-Content "$PSScriptRoot\..\src\Services\WinSetup.ps1" -Raw
        $script:ToolsSrc    = Get-Content "$PSScriptRoot\..\src\Screens\Tools.ps1" -Raw
        $script:AddToolSrc  = Get-Content "$PSScriptRoot\..\src\Screens\AddTool.ps1" -Raw
        $script:ProfileSrc  = Get-Content "$PSScriptRoot\..\src\Screens\Profile.ps1" -Raw
    }

    It 'full update job uses pwsh subprocess with -NoWait -JobMode' {
        $script:WinSetupSrc | Should -Match 'pwsh -NoProfile -NonInteractive -Command.*-NoWait -JobMode'
    }

    It 'per-package update job uses pwsh subprocess with -JobMode' {
        $script:WinSetupSrc | Should -Match "pwsh -NoProfile -NonInteractive -Command.*-Package.*-NoWait -JobMode"
    }

    It 'tool install job uses pwsh subprocess with -JobMode' {
        $script:ToolsSrc | Should -Match "pwsh -NoProfile -NonInteractive -Command.*-InstallTool.*-JobMode"
    }

    It 'tool update job uses pwsh subprocess with -JobMode' {
        $script:ToolsSrc | Should -Match "pwsh -NoProfile -NonInteractive -Command.*-Package.*-JobMode"
    }

    It 'tool remove job uses pwsh subprocess' {
        $script:ToolsSrc | Should -Match "pwsh -NoProfile -NonInteractive -Command.*-Tool"
    }

    It 'post-wizard install uses pwsh subprocess with -JobMode' {
        $script:AddToolSrc | Should -Match "pwsh -NoProfile -NonInteractive -Command.*-InstallTool.*-JobMode"
    }

    It 'profile redeploy uses pwsh subprocess' {
        $script:WinSetupSrc | Should -Match "pwsh -NoProfile -NonInteractive -Command.*PROFILE"
    }

    It 'no direct & $script invocations of winSetup scripts remain in job scriptblocks' {
        # Check that no Start-Job scriptblock directly invokes a winSetup script
        # via & $scriptPath or & $setupScript without pwsh subprocess
        $allSrc = @($script:WinSetupSrc, $script:ToolsSrc, $script:AddToolSrc)
        foreach ($src in $allSrc) {
            # Find lines inside Start-Job that invoke scripts with & $ but not via pwsh
            $jobBlocks = [regex]::Matches($src, '(?ms)Start-Job\s+-ScriptBlock\s*\{(.+?)\}\s*-ArgumentList')
            foreach ($block in $jobBlocks) {
                $body = $block.Groups[1].Value
                $directInvocations = ($body -split "`n") | Where-Object {
                    $_ -match '^\s*&\s*\$' -and $_ -notmatch 'pwsh' -and $_ -notmatch '^\s*#'
                }
                $directInvocations | Should -BeNullOrEmpty
            }
        }
    }
}
