#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . "$PSScriptRoot\..\src\Services\PackageManager.ps1"
}

# ---------------------------------------------------------------------------
# Get-ChocoUpdates
# ---------------------------------------------------------------------------

Describe 'Get-ChocoUpdates' {
    BeforeAll {
        # Fixture: realistic choco outdated -r output (pipe-delimited)
        $script:ChocoOutdatedFixture = @(
            'git|2.44.0|2.45.1|false'
            'delta|0.17.0|0.18.0|false'
            'python|3.12.3|3.12.4|false'
        )

        $script:ChocoEmptyFixture = @()
    }

    It 'parses standard choco outdated output correctly' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'choco.exe' } } -ParameterFilter { $Name -eq 'choco' }
        Mock choco { $script:ChocoOutdatedFixture } -ParameterFilter { $args[0] -eq 'outdated' }
        $global:LASTEXITCODE = 2  # choco returns 2 when outdated packages found

        $result = Get-ChocoUpdates

        $result.Count | Should -Be 3
        $result[0].Name | Should -Be 'git'
        $result[0].CurrentVersion | Should -Be '2.44.0'
        $result[0].AvailableVersion | Should -Be '2.45.1'
        $result[0].Source | Should -Be 'choco'
        $result[1].Name | Should -Be 'delta'
        $result[2].Name | Should -Be 'python'
    }

    It 'returns empty array when no packages are outdated' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'choco.exe' } } -ParameterFilter { $Name -eq 'choco' }
        Mock choco { $script:ChocoEmptyFixture } -ParameterFilter { $args[0] -eq 'outdated' }
        $global:LASTEXITCODE = 0

        $result = Get-ChocoUpdates

        $result.Count | Should -Be 0
    }

    It 'skips blank and malformed lines' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'choco.exe' } } -ParameterFilter { $Name -eq 'choco' }
        Mock choco {
            @(
                ''
                'git|2.44.0|2.45.1|false'
                '   '
                'incomplete-line'
                'delta|0.17.0|0.18.0|false'
            )
        } -ParameterFilter { $args[0] -eq 'outdated' }
        $global:LASTEXITCODE = 2

        $result = Get-ChocoUpdates

        $result.Count | Should -Be 2
        $result[0].Name | Should -Be 'git'
        $result[1].Name | Should -Be 'delta'
    }

    It 'returns empty array when choco is not installed' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'choco' }

        $result = Get-ChocoUpdates

        $result.Count | Should -Be 0
    }

    It 'returns empty array on unexpected exit code' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'choco.exe' } } -ParameterFilter { $Name -eq 'choco' }
        Mock choco { @('some error output') } -ParameterFilter { $args[0] -eq 'outdated' }
        $global:LASTEXITCODE = 1  # unexpected failure

        $result = Get-ChocoUpdates

        $result.Count | Should -Be 0
    }

    It 'filters to known choco tools when -KnownTools is provided' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'choco.exe' } } -ParameterFilter { $Name -eq 'choco' }
        Mock choco {
            @(
                'git|2.44.0|2.45.1|false'
                '7zip|23.01|24.08|false'
                'delta|0.17.0|0.18.0|false'
                'filezilla|3.66.5|3.67.0|false'
            )
        } -ParameterFilter { $args[0] -eq 'outdated' }
        $global:LASTEXITCODE = 2

        $tools = @(
            @{ Manager = 'choco'; PackageId = 'git' }
            @{ Manager = 'choco'; PackageId = 'delta' }
            @{ Manager = 'winget'; PackageId = 'junegunn.fzf' }
        )

        $result = Get-ChocoUpdates -KnownTools $tools

        $result.Count | Should -Be 2
        $result[0].PackageId | Should -Be 'git'
        $result[1].PackageId | Should -Be 'delta'
    }

    It 'returns empty when -KnownTools has no matching choco packages' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'choco.exe' } } -ParameterFilter { $Name -eq 'choco' }
        Mock choco {
            @('7zip|23.01|24.08|false', 'filezilla|3.66.5|3.67.0|false')
        } -ParameterFilter { $args[0] -eq 'outdated' }
        $global:LASTEXITCODE = 2

        $tools = @(
            @{ Manager = 'choco'; PackageId = 'git' }
        )

        $result = Get-ChocoUpdates -KnownTools $tools

        $result.Count | Should -Be 0
    }

    It 'excludes entries where current version equals available version' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'choco.exe' } } -ParameterFilter { $Name -eq 'choco' }
        Mock choco {
            $global:LASTEXITCODE = 2
            @(
                'git|2.44.0|2.45.1|false'
                'delta|0.19.2|0.19.2|false'
            )
        } -ParameterFilter { $args[0] -eq 'outdated' }

        $result = @(Get-ChocoUpdates)

        $result.Count | Should -Be 1
        $result[0].PackageId | Should -Be 'git'
    }

    It 'applies both KnownTools and version filters together' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'choco.exe' } } -ParameterFilter { $Name -eq 'choco' }
        Mock choco {
            $global:LASTEXITCODE = 2
            @(
                'git|2.44.0|2.45.1|false'
                '7zip|23.01|24.08|false'
                'delta|0.19.2|0.19.2|false'
                'bat|0.26.1|0.26.1|false'
            )
        } -ParameterFilter { $args[0] -eq 'outdated' }

        $tools = @(
            @{ Manager = 'choco'; PackageId = 'git' }
            @{ Manager = 'choco'; PackageId = 'delta' }
            @{ Manager = 'choco'; PackageId = 'bat' }
        )

        $result = @(Get-ChocoUpdates -KnownTools $tools)

        # git passes both filters (registry + different version)
        # 7zip filtered by KnownTools (not in registry)
        # delta filtered by version (same version)
        # bat filtered by version (same version)
        $result.Count | Should -Be 1
        $result[0].PackageId | Should -Be 'git'
    }

    It 'returns all packages when -KnownTools is not provided' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'choco.exe' } } -ParameterFilter { $Name -eq 'choco' }
        Mock choco {
            @('git|2.44.0|2.45.1|false', '7zip|23.01|24.08|false')
        } -ParameterFilter { $args[0] -eq 'outdated' }
        $global:LASTEXITCODE = 2

        $result = Get-ChocoUpdates

        $result.Count | Should -Be 2
    }
}

# ---------------------------------------------------------------------------
# Get-WingetUpdates
# ---------------------------------------------------------------------------

Describe 'Get-WingetUpdates' {
    BeforeAll {
        # Fixture: realistic winget upgrade --list output (fixed-width columns).
        # Column positions MUST match the header exactly. The parser uses
        # IndexOf on the header to derive column start positions.
        #          0         1         2         3         4         5         6         7
        #          0123456789012345678901234567890123456789012345678901234567890123456789012345
        $script:WingetUpgradeFixture = @(
            'Name                            Id                                Version      Available    Source'
            '------------------------------------------------------------------------------------------------------'
            'Mozilla Firefox                 Mozilla.Firefox                   125.0.1      126.0        winget'
            'Oh My Posh                      JanDeDobbeleer.OhMyPosh           19.21.0      19.22.1      winget'
            'GitHub CLI                      GitHub.cli                        2.48.0       2.49.0       winget'
            '3 upgrades available.'
        )

        $script:WingetNoUpdatesFixture = @(
            'No applicable update found.'
        )
    }

    It 'parses standard winget upgrade output correctly' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        Mock winget { $script:WingetUpgradeFixture } -ParameterFilter { $args[0] -eq 'upgrade' }
        $global:LASTEXITCODE = 0

        $result = Get-WingetUpdates

        $result.Count | Should -Be 3
        $result[0].Name | Should -Be 'Mozilla Firefox'
        $result[0].PackageId | Should -Be 'Mozilla.Firefox'
        $result[0].CurrentVersion | Should -Be '125.0.1'
        $result[0].AvailableVersion | Should -Be '126.0'
        $result[0].Source | Should -Be 'winget'
        $result[1].Name | Should -Be 'Oh My Posh'
        $result[1].PackageId | Should -Be 'JanDeDobbeleer.OhMyPosh'
        $result[2].PackageId | Should -Be 'GitHub.cli'
    }

    It 'filters the summary line' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        Mock winget { $script:WingetUpgradeFixture } -ParameterFilter { $args[0] -eq 'upgrade' }
        $global:LASTEXITCODE = 0

        $result = Get-WingetUpdates

        # The "3 upgrades available." line must not appear as a result
        $result | Where-Object { $_.Name -match 'upgrades? available' } | Should -BeNullOrEmpty
    }

    It 'returns empty array when no updates are available' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        Mock winget { $script:WingetNoUpdatesFixture } -ParameterFilter { $args[0] -eq 'upgrade' }
        $global:LASTEXITCODE = 0

        $result = Get-WingetUpdates

        $result.Count | Should -Be 0
    }

    It 'returns empty array when winget is not installed' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' }

        $result = Get-WingetUpdates

        $result.Count | Should -Be 0
    }

    It 'surfaces a warning when headers are in a non-English locale' {
        # French locale: winget uses "Nom", "Identifiant", "Version", "Disponible"
        Mock Get-Command { [PSCustomObject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        Mock winget {
            @(
                'Nom                             Identifiant                       Version      Disponible   Source'
                '------------------------------------------------------------------------------------------------------'
                'Mozilla Firefox                 Mozilla.Firefox                   125.0.1      126.0        winget'
            )
        } -ParameterFilter { $args[0] -eq 'upgrade' }
        $global:LASTEXITCODE = 0
        Mock Write-Warning {}

        $result = Get-WingetUpdates

        # "Identifiant" does not contain "Id" even case-insensitively;
        # "Disponible" does not match "Available". The function returns empty
        # and emits a warning so the failure is not silent.
        $result.Count | Should -Be 0
        Should -Invoke Write-Warning -Times 1
    }

    It 'surfaces a warning when German locale headers lack Available' {
        # German locale: "Name", "ID", "Version", "Verfuegbar"
        # "ID" now matches "Id" case-insensitively, and "Version" matches,
        # but "Verfuegbar" does not match "Available".
        Mock Get-Command { [PSCustomObject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        Mock winget {
            @(
                'Name                            ID                                Version      Verfuegbar   Quelle'
                '------------------------------------------------------------------------------------------------------'
                'Oh My Posh                      JanDeDobbeleer.OhMyPosh           19.21.0      19.22.1      winget'
            )
        } -ParameterFilter { $args[0] -eq 'upgrade' }
        $global:LASTEXITCODE = 0
        Mock Write-Warning {}

        $result = Get-WingetUpdates

        $result.Count | Should -Be 0
        Should -Invoke Write-Warning -Times 1
    }

    It 'parses correctly when headers use uppercase casing (ID, AVAILABLE)' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        Mock winget {
            @(
                'Name                            ID                                Version      Available    Source'
                '------------------------------------------------------------------------------------------------------'
                'Oh My Posh                      JanDeDobbeleer.OhMyPosh           19.21.0      19.22.1      winget'
            )
        } -ParameterFilter { $args[0] -eq 'upgrade' }
        $global:LASTEXITCODE = 0

        $result = @(Get-WingetUpdates)

        $result.Count | Should -Be 1
        $result[0].PackageId | Should -Be 'JanDeDobbeleer.OhMyPosh'
        $result[0].CurrentVersion | Should -Be '19.21.0'
        $result[0].AvailableVersion | Should -Be '19.22.1'
    }

    It 'warning message includes the header line for diagnosis' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        Mock winget {
            @(
                'Nom                             Identifiant                       Version      Disponible   Source'
                '------------------------------------------------------------------------------------------------------'
                'Mozilla Firefox                 Mozilla.Firefox                   125.0.1      126.0        winget'
            )
        } -ParameterFilter { $args[0] -eq 'upgrade' }
        $global:LASTEXITCODE = 0
        $script:_warningMsg = $null
        Mock Write-Warning { $script:_warningMsg = $Message }

        $null = Get-WingetUpdates

        $script:_warningMsg | Should -Match 'Nom'
        $script:_warningMsg | Should -Match 'column headers'
    }

    It 'parses correctly when locale matches English headers' {
        # Confirm that the English-locale path works with the exact header
        # names the parser expects: "Id", "Version", "Available", "Source"
        Mock Get-Command { [PSCustomObject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        Mock winget {
            @(
                'Name                            Id                                Version      Available    Source'
                '------------------------------------------------------------------------------------------------------'
                'GitHub CLI                      GitHub.cli                        2.48.0       2.49.0       winget'
            )
        } -ParameterFilter { $args[0] -eq 'upgrade' }
        $global:LASTEXITCODE = 0

        $result = @(Get-WingetUpdates)

        $result.Count | Should -Be 1
        $result[0].PackageId | Should -Be 'GitHub.cli'
    }

    It 'handles packages with long names correctly' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        #          0         1         2         3         4         5         6         7         8         9
        #          0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789
        Mock winget {
            @(
                'Name                                       Id                                    Version      Available    Source'
                '--------------------------------------------------------------------------------------------------------------'
                'Microsoft Visual Studio Code               Microsoft.VisualStudioCode            1.88.1       1.89.0       winget'
            )
        } -ParameterFilter { $args[0] -eq 'upgrade' }
        $global:LASTEXITCODE = 0

        $result = @(Get-WingetUpdates)

        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'Microsoft Visual Studio Code'
        $result[0].PackageId | Should -Be 'Microsoft.VisualStudioCode'
        $result[0].CurrentVersion | Should -Be '1.88.1'
        $result[0].AvailableVersion | Should -Be '1.89.0'
    }
}

# ---------------------------------------------------------------------------
# Get-PipxTools
# ---------------------------------------------------------------------------

Describe 'Get-PipxTools' {
    It 'parses pipx list JSON output correctly' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'pipx.exe' } } -ParameterFilter { $Name -eq 'pipx' }
        Mock pipx {
            if ($args[0] -eq 'list' -and $args[1] -eq '--json') {
                @'
{
  "venvs": {
    "ruff": { "metadata": { "main_package": { "package_version": "0.3.4" } } },
    "mypy": { "metadata": { "main_package": { "package_version": "1.9.0" } } }
  }
}
'@
            }
        }
        $global:LASTEXITCODE = 0

        $result = Get-PipxTools

        $result.Count | Should -Be 2
        $names = $result | ForEach-Object { $_.Name }
        $names | Should -Contain 'ruff'
        $names | Should -Contain 'mypy'
        ($result | Where-Object { $_.Name -eq 'ruff' }).CurrentVersion | Should -Be '0.3.4'
        ($result | Where-Object { $_.Name -eq 'mypy' }).CurrentVersion | Should -Be '1.9.0'
        $result[0].Source | Should -Be 'pipx'
    }

    It 'falls back to text output parsing when JSON is unavailable' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'pipx.exe' } } -ParameterFilter { $Name -eq 'pipx' }
        $script:PipxCallCount = 0
        Mock pipx {
            $script:PipxCallCount++
            if ($args[0] -eq 'list' -and $args[1] -eq '--json') {
                $global:LASTEXITCODE = 1
                return $null
            }
            if ($args[0] -eq 'list') {
                $global:LASTEXITCODE = 0
                return @(
                    'venvs are in /home/user/.local/pipx/venvs'
                    'apps are exposed on your $PATH at /home/user/.local/bin'
                    '   package ruff 0.3.4, installed using Python 3.12.3'
                    '    - ruff'
                    '   package pre-commit 3.7.0, installed using Python 3.12.3'
                    '    - pre-commit'
                    '    - pre-commit-validate-config'
                    '    - pre-commit-validate-manifest'
                )
            }
        }
        $global:LASTEXITCODE = 1

        $result = Get-PipxTools

        $result.Count | Should -Be 2
        $result[0].Name | Should -Be 'ruff'
        $result[0].CurrentVersion | Should -Be '0.3.4'
        $result[1].Name | Should -Be 'pre-commit'
        $result[1].CurrentVersion | Should -Be '3.7.0'
    }

    It 'returns empty array when nothing is installed' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'pipx.exe' } } -ParameterFilter { $Name -eq 'pipx' }
        Mock pipx {
            if ($args[0] -eq 'list' -and $args[1] -eq '--json') {
                $global:LASTEXITCODE = 0
                return '{ "venvs": {} }'
            }
        }
        $global:LASTEXITCODE = 0

        $result = Get-PipxTools

        $result.Count | Should -Be 0
    }

    It 'returns empty array when pipx is not installed' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'pipx' }

        $result = Get-PipxTools

        $result.Count | Should -Be 0
    }

    It 'falls back to python -m pipx when direct pipx throws' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'pipx.exe' } } -ParameterFilter { $Name -eq 'pipx' }
        Mock pipx { throw [System.Management.Automation.RuntimeException]::new("StandardOutputEncoding error") }
        Mock python {
            $global:LASTEXITCODE = 0
            return $null
        } -ParameterFilter { $args[0] -eq '-m' -and $args[1] -eq 'pipx' }
        $global:LASTEXITCODE = 0

        # When pipx throws, Invoke-Pipx falls back to python -m pipx.
        # Verify the fallback path is invoked.
        $null = Get-PipxTools

        Should -Invoke -CommandName python -Times 1 -Exactly:$false
    }

    It 'returns correct results via the fallback path' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'pipx.exe' } } -ParameterFilter { $Name -eq 'pipx' }
        Mock pipx { throw [System.Management.Automation.RuntimeException]::new("StandardOutputEncoding error") }
        Mock python {
            $global:LASTEXITCODE = 0
            if ($args[2] -eq 'list' -and $args[3] -eq '--json') {
                return @'
{
  "venvs": {
    "ruff": { "metadata": { "main_package": { "package_version": "0.4.0" } } },
    "bandit": { "metadata": { "main_package": { "package_version": "1.7.8" } } }
  }
}
'@
            }
            return $null
        } -ParameterFilter { $args[0] -eq '-m' -and $args[1] -eq 'pipx' }
        $global:LASTEXITCODE = 0

        $result = Get-PipxTools

        $names = $result | ForEach-Object { $_.Name }
        $names | Should -Contain 'ruff'
        $names | Should -Contain 'bandit'
        ($result | Where-Object { $_.Name -eq 'ruff' }).CurrentVersion | Should -Be '0.4.0'
        ($result | Where-Object { $_.Name -eq 'bandit' }).CurrentVersion | Should -Be '1.7.8'
    }
}

# ---------------------------------------------------------------------------
# Search-ChocolateyPackage
# ---------------------------------------------------------------------------

Describe 'Search-ChocolateyPackage' {
    It 'parses choco search output correctly' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'choco.exe' } } -ParameterFilter { $Name -eq 'choco' }
        Mock choco {
            @(
                'ripgrep|14.1.0'
                'ripgrep-all|1.0.0-alpha.5'
            )
        } -ParameterFilter { $args[0] -eq 'search' }
        $global:LASTEXITCODE = 0

        $result = Search-ChocolateyPackage -Name 'ripgrep'

        $result.Count | Should -Be 2
        $result[0].Name | Should -Be 'ripgrep'
        $result[0].Version | Should -Be '14.1.0'
        $result[0].PackageId | Should -Be 'ripgrep'
        $result[0].Source | Should -Be 'choco'
    }

    It 'returns empty array for empty search term' {
        $result = Search-ChocolateyPackage -Name ''

        $result.Count | Should -Be 0
    }

    It 'returns empty array when choco is not installed' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'choco' }

        $result = Search-ChocolateyPackage -Name 'test'

        $result.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# Search-WingetPackage
# ---------------------------------------------------------------------------

Describe 'Search-WingetPackage' {
    It 'parses winget search output correctly' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        #          Name(0-20)  Id(20-48)                 Version(48-57) Source(57+)
        Mock winget {
            @(
                'Name                Id                            Version  Source'
                '------------------------------------------------------------------'
                'fzf                 junegunn.fzf                  0.50.0   winget'
                'fzf (Fork)          fzf-fork.fzf                  0.1.0    winget'
                '2 packages found.'
            )
        } -ParameterFilter { $args[0] -eq 'search' }
        $global:LASTEXITCODE = 0

        $result = Search-WingetPackage -Name 'fzf'

        $result.Count | Should -Be 2
        $result[0].Name | Should -Be 'fzf'
        $result[0].PackageId | Should -Be 'junegunn.fzf'
        $result[0].Source | Should -Be 'winget'
    }

    It 'filters the summary line from results' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        Mock winget {
            @(
                'Name                Id                            Version  Source'
                '------------------------------------------------------------------'
                'fzf                 junegunn.fzf                  0.50.0   winget'
                '1 package found.'
            )
        } -ParameterFilter { $args[0] -eq 'search' }
        $global:LASTEXITCODE = 0

        $result = @(Search-WingetPackage -Name 'fzf')

        $result.Count | Should -Be 1
    }

    It 'returns empty array for empty search term' {
        $result = Search-WingetPackage -Name ''

        $result.Count | Should -Be 0
    }

    It 'returns empty array when winget is not installed' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' }

        $result = Search-WingetPackage -Name 'test'

        $result.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# Search-PyPI
# ---------------------------------------------------------------------------

Describe 'Search-PyPI' {
    It 'returns result for exact name match' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                info = [PSCustomObject]@{
                    name    = 'requests'
                    version = '2.31.0'
                    summary = 'HTTP library for Python'
                    description = ''
                }
            }
        }

        $result = @(Search-PyPI -Term 'requests')

        $result.Count | Should -BeGreaterOrEqual 1
        $result[0].Name | Should -Be 'requests'
        $result[0].Version | Should -Be '2.31.0'
        $result[0].Description | Should -Be 'HTTP library for Python'
        $result[0].Source | Should -Be 'pypi'
    }

    It 'returns empty array when package is not found' {
        Mock Invoke-RestMethod { throw "404 Not Found" }

        $result = @(Search-PyPI -Term 'nonexistent-package-xyz')

        $result.Count | Should -Be 0
    }

    It 'uses "No description available." when summary is empty' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                info = [PSCustomObject]@{
                    name        = 'bare-pkg'
                    version     = '1.0.0'
                    summary     = ''
                    description = ''
                }
            }
        }

        $result = @(Search-PyPI -Term 'bare-pkg')

        $result.Count | Should -BeGreaterOrEqual 1
        $result[0].Description | Should -Be 'No description available.'
    }
}
