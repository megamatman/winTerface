#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $script:BootstrapScript = Get-Content "$PSScriptRoot\..\bootstrap.ps1" -Raw
}

Describe 'Bootstrap pre-flight checks' {
    It 'requires PowerShell 7 (script contains PS version check)' {
        $script:BootstrapScript | Should -Match 'PSVersionTable\.PSVersion\.Major\s*-lt\s*7'
        $script:BootstrapScript | Should -Match 'exit 1'
    }

    It 'checks that winSetup is installed via $env:WINSETUP' {
        $script:BootstrapScript | Should -Match '\$env:WINSETUP'
        $script:BootstrapScript | Should -Match 'winSetup is not installed'
    }

    It 'prints winSetup bootstrap instructions when WINSETUP is missing' {
        $script:BootstrapScript | Should -Match 'winSetup.*Install it first'
        $script:BootstrapScript | Should -Match 'raw\.githubusercontent\.com/megamatman/winSetup'
    }

    It 'checks for git and falls back to winget install' {
        $script:BootstrapScript | Should -Match 'Get-Command git'
        $script:BootstrapScript | Should -Match 'winget install Git\.Git'
    }

    It 'detects existing WINTERFACE and skips clone' {
        $script:BootstrapScript | Should -Match '\$env:WINTERFACE'
        $script:BootstrapScript | Should -Match 'already present'
    }

    It 'exits with code 1 when git clone fails' {
        $script:BootstrapScript | Should -Match 'git clone.*winTerface'
        $script:BootstrapScript | Should -Match 'LASTEXITCODE.*-ne 0'
    }

    It 'sets WINTERFACE environment variable after clone' {
        $script:BootstrapScript | Should -Match "SetEnvironmentVariable\('WINTERFACE'"
        $script:BootstrapScript | Should -Match '\$env:WINTERFACE\s*='
    }

    It 'invokes Install-WinTerface.ps1 after clone' {
        $script:BootstrapScript | Should -Match 'Install-WinTerface\.ps1'
        $script:BootstrapScript | Should -Match '\& \$installScript'
    }

    It 'offers to launch winTerface after install' {
        $script:BootstrapScript | Should -Match 'Launch winTerface now'
        $script:BootstrapScript | Should -Match 'winTerface\.ps1'
    }
}

Describe 'Bootstrap security notice' {
    It 'displays a security notice before any action' {
        $noticePos = $script:BootstrapScript.IndexOf('Review the source')
        $actionPos = $script:BootstrapScript.IndexOf('PowerShell version')

        $noticePos | Should -BeGreaterThan -1
        $actionPos | Should -BeGreaterThan -1
        $noticePos | Should -BeLessThan $actionPos
    }

    It 'includes the GitHub URL for review' {
        $script:BootstrapScript | Should -Match 'github\.com/megamatman/winTerface'
    }

    It 'prompts for confirmation before proceeding' {
        $script:BootstrapScript | Should -Match 'Continue\?'
    }
}

Describe 'Bootstrap structure' {
    It 'has a .SYNOPSIS help block' {
        $script:BootstrapScript | Should -Match '\.SYNOPSIS'
    }

    It 'does not require Administrator' {
        $script:BootstrapScript | Should -Not -Match '#Requires.*RunAsAdministrator'
        $script:BootstrapScript | Should -Not -Match 'Assert-Administrator'
    }

    It 'exits cleanly when user declines launch' {
        $script:BootstrapScript | Should -Match 'To launch later.*wti'
    }
}
