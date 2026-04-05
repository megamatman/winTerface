#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . "$PSScriptRoot\..\src\Services\ToolWriter.ps1"
}

Describe 'New-InstallFunction' {
    It 'generates valid PowerShell for choco manager' {
        $result = New-InstallFunction -DisplayName 'ripgrep' -PackageManager 'choco' -PackageId 'ripgrep' -VerifyCommand 'rg'
        $result | Should -Match "choco install 'ripgrep' -y"
        $result | Should -Match 'function Install-ripgrep'
    }

    It 'generates valid PowerShell for winget manager' {
        $result = New-InstallFunction -DisplayName 'fzf' -PackageManager 'winget' -PackageId 'junegunn.fzf' -VerifyCommand 'fzf'
        $result | Should -Match "winget install 'junegunn.fzf'"
        $result | Should -Match '--accept-package-agreements'
    }

    It 'generates valid PowerShell for pipx manager' {
        $result = New-InstallFunction -DisplayName 'httpie' -PackageManager 'pipx' -PackageId 'httpie' -VerifyCommand 'http'
        $result | Should -Match "pipx install 'httpie'"
        $result | Should -Match 'function Install-httpie'
    }

    It 'generates valid PowerShell for manual manager' {
        $result = New-InstallFunction -DisplayName 'custom-tool' -PackageManager 'manual' -PackageId '' -VerifyCommand 'custom-tool'
        $result | Should -Match 'must be installed manually'
        $result | Should -Not -Match 'choco'
        $result | Should -Not -Match 'winget'
        $result | Should -Not -Match 'pipx'
    }

    It 'escapes single quotes in DisplayName' {
        $result = New-InstallFunction -DisplayName "O'Reilly" -PackageManager 'choco' -PackageId 'oreilly' -VerifyCommand 'oreilly'
        $result | Should -Match "O''Reilly"
        Test-GeneratedCode -Code $result | Should -BeTrue
    }

    It 'escapes single quotes in PackageId' {
        $result = New-InstallFunction -DisplayName 'test' -PackageManager 'choco' -PackageId "pkg'inject" -VerifyCommand 'test'
        $result | Should -Match "pkg''inject"
        Test-GeneratedCode -Code $result | Should -BeTrue
    }

    It 'escapes single quotes in VerifyCommand' {
        $result = New-InstallFunction -DisplayName 'test' -PackageManager 'choco' -PackageId 'test' -VerifyCommand "cmd'inject"
        $result | Should -Match "cmd''inject"
        Test-GeneratedCode -Code $result | Should -BeTrue
    }

    It 'handles winget IDs with dots' {
        $result = New-InstallFunction -DisplayName 'vscode' -PackageManager 'winget' -PackageId 'Microsoft.VisualStudioCode' -VerifyCommand 'code'
        $result | Should -Match 'Microsoft.VisualStudioCode'
        Test-GeneratedCode -Code $result | Should -BeTrue
    }

    It 'handles winget IDs with slashes' {
        $result = New-InstallFunction -DisplayName 'test' -PackageManager 'winget' -PackageId 'Vendor/Package' -VerifyCommand 'test'
        $result | Should -Match 'Vendor/Package'
        Test-GeneratedCode -Code $result | Should -BeTrue
    }

    It 'generated code passes Test-GeneratedCode for all managers' {
        foreach ($mgr in @('choco', 'winget', 'pipx', 'manual')) {
            $result = New-InstallFunction -DisplayName 'testtool' -PackageManager $mgr -PackageId 'testtool' -VerifyCommand 'testtool'
            Test-GeneratedCode -Code $result | Should -BeTrue -Because "manager '$mgr' should produce valid PowerShell"
        }
    }
}

Describe 'New-RegistryEntry' {
    It 'generates correct entry for choco manager' {
        $result = New-RegistryEntry -DisplayName 'ripgrep' -PackageManager 'choco' -PackageId 'ripgrep'
        $result | Should -Match '"ripgrep"\s*=\s*@\{\s*Manager\s*=\s*"choco";\s*Id\s*=\s*"ripgrep"\s*\}'
    }

    It 'generates correct entry for winget manager' {
        $result = New-RegistryEntry -DisplayName 'fzf' -PackageManager 'winget' -PackageId 'junegunn.fzf'
        $result | Should -Match '"fzf"\s*=\s*@\{\s*Manager\s*=\s*"winget";\s*Id\s*=\s*"junegunn.fzf"\s*\}'
    }

    It 'generates correct entry for pipx manager' {
        $result = New-RegistryEntry -DisplayName 'httpie' -PackageManager 'pipx' -PackageId 'httpie'
        $result | Should -Match '"httpie"\s*=\s*@\{\s*Manager\s*=\s*"pipx";\s*Id\s*=\s*"httpie"\s*\}'
    }

    It 'entry format matches $PackageRegistry pattern' {
        $result = New-RegistryEntry -DisplayName 'delta' -PackageManager 'choco' -PackageId 'delta'
        # Must start with whitespace + "key" = @{ Manager = "..."; Id = "..." }
        $result | Should -Match '^\s+"[^"]+"\s*=\s*@\{.*Manager.*Id.*\}$'
    }

    It 'escapes double quotes in PackageId' {
        $result = New-RegistryEntry -DisplayName 'test' -PackageManager 'choco' -PackageId 'pkg"inject'
        $result | Should -Not -Match 'pkg"inject'
        # The escaped form uses backtick-quote
        $result | Should -Match 'pkg`"inject'
    }

    It 'lowercases and strips special chars from key' {
        $result = New-RegistryEntry -DisplayName 'Oh My Posh' -PackageManager 'winget' -PackageId 'JanDeDobbeleer.OhMyPosh'
        $result | Should -Match '"ohmyposh"'
    }

    It 'generated code passes Test-GeneratedCode' {
        $result = New-RegistryEntry -DisplayName 'testtool' -PackageManager 'pipx' -PackageId 'testtool'
        # Wrap in a script block to make it valid PowerShell
        $code = "`$PackageRegistry = @{`n$result`n}"
        Test-GeneratedCode -Code $code | Should -BeTrue
    }
}

Describe 'New-ProfileSection' {
    It 'generates a section block with header bars and content' {
        $result = New-ProfileSection -DisplayName 'lazygit' -ProfileContent 'Set-Alias lg lazygit'
        $result | Should -Match '# lazygit'
        $result | Should -Match 'Set-Alias lg lazygit'
        $result | Should -Match '# ={10,}'
    }

    It 'generates a section block even when ProfileContent is empty' {
        # New-ProfileSection itself does not filter empty content.
        # The empty check is in Get-ModifiedProfileContent.
        $result = New-ProfileSection -DisplayName 'test' -ProfileContent ''
        $result | Should -Match '# test'
        $result | Should -Match '# ={10,}'
    }

    It 'generated code passes Test-GeneratedCode' {
        $result = New-ProfileSection -DisplayName 'delta' -ProfileContent '$env:DELTA_FEATURES = "side-by-side"'
        Test-GeneratedCode -Code $result | Should -BeTrue
    }
}

Describe 'Test-GeneratedCode' {
    It 'returns true for valid PowerShell' {
        Test-GeneratedCode -Code 'function Test { Write-Host "hello" }' | Should -BeTrue
    }

    It 'returns true for empty string' {
        Test-GeneratedCode -Code '' | Should -BeTrue
    }

    It 'returns false for unmatched single quotes' {
        Test-GeneratedCode -Code "Write-Host 'unclosed" | Should -BeFalse
    }

    It 'returns false for unmatched braces' {
        Test-GeneratedCode -Code 'function Broken {' | Should -BeFalse
    }

    It 'returns false for syntax errors' {
        Test-GeneratedCode -Code 'function { invalid syntax }}}' | Should -BeFalse
    }
}
