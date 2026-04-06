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
