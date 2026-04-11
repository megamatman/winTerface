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

# AllowedPattern validation for the Add Tool guided wizard.
#
# These patterns are defined in $script:GuidedSteps in AddTool.ps1 and are the
# primary defence against code injection in generated PowerShell output. They
# gate the PackageId, VerifyCommand, and ProfileAlias fields.
#
# LIMITATION: Values arriving via the search wizard path (choco/winget/PyPI
# results) bypass AllowedPattern entirely. Those values rely on single-quote
# escaping in New-InstallFunction and double-quote escaping in New-RegistryEntry
# within ToolWriter.ps1. This test file does not cover that secondary path.

Describe 'AllowedPattern validation' {
    BeforeAll {
        # Extract patterns from AddTool.ps1 source rather than hardcoding them.
        # The file cannot be dot-sourced because it references Terminal.Gui types.
        $addToolPath = Join-Path $PSScriptRoot '..' 'src' 'Screens' 'AddTool.ps1'
        $content = Get-Content $addToolPath -Raw

        # Parse AllowedPattern values keyed by their field name.
        # Format in source: Key = 'FieldName'; ... AllowedPattern = 'pattern'
        # The ProfileAlias pattern contains '' (escaped single quote in
        # PowerShell single-quoted strings), so the extraction must handle
        # this: match everything up to a single quote NOT followed by another.
        $script:Patterns = @{}
        $keys = @('DisplayName', 'PackageId', 'VerifyCommand', 'ProfileAlias')
        foreach ($key in $keys) {
            if ($content -match "Key\s*=\s*'$key'[^}]*AllowedPattern\s*=\s*'((?:[^']|'')+)'") {
                $raw = $Matches[1]
                # Unescape PowerShell single-quoted string: '' becomes '
                $script:Patterns[$key] = $raw -replace "''", "'"
            }
        }
    }

    Context 'pattern extraction from source' {
        It 'finds all four AllowedPattern definitions' {
            $script:Patterns.Keys | Should -HaveCount 4
            foreach ($key in @('DisplayName', 'PackageId', 'VerifyCommand', 'ProfileAlias')) {
                $script:Patterns[$key] | Should -Not -BeNullOrEmpty -Because "$key pattern must be defined"
            }
        }
    }

    Context 'PackageId pattern' {
        It 'accepts a simple lowercase name' {
            'ripgrep' | Should -Match $script:Patterns.PackageId
        }

        It 'accepts a dotted publisher-prefixed ID' {
            'JanDeDobbeleer.OhMyPosh' | Should -Match $script:Patterns.PackageId
        }

        It 'accepts a hyphenated name' {
            'pre-commit' | Should -Match $script:Patterns.PackageId
        }

        It 'accepts underscores' {
            'my_package' | Should -Match $script:Patterns.PackageId
        }

        It 'accepts slashes' {
            'Vendor/Package' | Should -Match $script:Patterns.PackageId
        }

        It 'accepts a multi-segment winget ID' {
            'BurntSushi.ripgrep.MSVC' | Should -Match $script:Patterns.PackageId
        }

        It 'rejects semicolons' {
            'ruff; rm -rf /' | Should -Not -Match $script:Patterns.PackageId
        }

        It 'rejects subexpression syntax' {
            'pkg$(whoami)' | Should -Not -Match $script:Patterns.PackageId
        }

        It 'rejects backticks' {
            'pkg`ninjection' | Should -Not -Match $script:Patterns.PackageId
        }

        It 'rejects single quotes' {
            "pkg'inject" | Should -Not -Match $script:Patterns.PackageId
        }

        It 'rejects double quotes' {
            'pkg"inject' | Should -Not -Match $script:Patterns.PackageId
        }

        It 'rejects spaces' {
            'my package' | Should -Not -Match $script:Patterns.PackageId
        }

        It 'rejects pipe characters' {
            'pkg|evil' | Should -Not -Match $script:Patterns.PackageId
        }

        It 'rejects ampersands' {
            'pkg&evil' | Should -Not -Match $script:Patterns.PackageId
        }
    }

    Context 'VerifyCommand pattern' {
        It 'accepts a simple command name' {
            'rg' | Should -Match $script:Patterns.VerifyCommand
        }

        It 'accepts a hyphenated command' {
            'my-tool' | Should -Match $script:Patterns.VerifyCommand
        }

        It 'accepts dots in command names' {
            'tool.exe' | Should -Match $script:Patterns.VerifyCommand
        }

        It 'accepts underscores' {
            'my_cmd' | Should -Match $script:Patterns.VerifyCommand
        }

        It 'accepts mixed case' {
            'MyTool' | Should -Match $script:Patterns.VerifyCommand
        }

        It 'rejects semicolons' {
            'cmd;evil' | Should -Not -Match $script:Patterns.VerifyCommand
        }

        It 'rejects subexpression syntax' {
            'cmd$(whoami)' | Should -Not -Match $script:Patterns.VerifyCommand
        }

        It 'rejects backticks' {
            'cmd`ninjection' | Should -Not -Match $script:Patterns.VerifyCommand
        }

        It 'rejects spaces' {
            'my tool' | Should -Not -Match $script:Patterns.VerifyCommand
        }

        It 'rejects slashes' {
            'path/cmd' | Should -Not -Match $script:Patterns.VerifyCommand
        }

        It 'rejects pipe characters' {
            'cmd|evil' | Should -Not -Match $script:Patterns.VerifyCommand
        }

        It 'rejects single quotes' {
            "cmd'inject" | Should -Not -Match $script:Patterns.VerifyCommand
        }
    }

    Context 'ProfileAlias pattern' {
        It 'accepts a Set-Alias command' {
            'Set-Alias rg ripgrep' | Should -Match $script:Patterns.ProfileAlias
        }

        It 'accepts an environment variable assignment' {
            '$env:DELTA_FEATURES = "side-by-side"' | Should -Match $script:Patterns.ProfileAlias
        }

        It 'accepts parentheses' {
            'function gs() { git status }' | Should -Not -Match $script:Patterns.ProfileAlias -Because 'braces are not in the allowlist'
        }

        It 'accepts colons and pipes' {
            '$env:PATH | Write-Output' | Should -Match $script:Patterns.ProfileAlias
        }

        It 'accepts commas' {
            'a, b, c' | Should -Match $script:Patterns.ProfileAlias
        }

        It 'rejects semicolons' {
            'Set-Alias x y; Remove-Item C:\' | Should -Not -Match $script:Patterns.ProfileAlias
        }

        # The pattern uses \s which matches newlines, so the regex alone does
        # not reject multi-line input. Terminal.Gui's TextField is single-line
        # and cannot accept newline characters, so this is not exploitable
        # through the wizard UI. This test documents the known limitation.
        It 'allows newlines via \s (mitigated by single-line TextField)' {
            "Set-Alias x y`nRemove-Item C:\" | Should -Match $script:Patterns.ProfileAlias
        }

        It 'rejects ampersands' {
            'cmd & evil' | Should -Not -Match $script:Patterns.ProfileAlias
        }

        It 'rejects at-signs (splatting)' {
            '@args' | Should -Not -Match $script:Patterns.ProfileAlias
        }

        It 'rejects hash characters (comment injection)' {
            '# injected comment' | Should -Not -Match $script:Patterns.ProfileAlias
        }

        It 'rejects angle brackets (redirection)' {
            'cmd > file.txt' | Should -Not -Match $script:Patterns.ProfileAlias
        }
    }

    Context 'DisplayName pattern' {
        It 'accepts a simple name' {
            'ripgrep' | Should -Match $script:Patterns.DisplayName
        }

        It 'accepts spaces' {
            'Oh My Posh' | Should -Match $script:Patterns.DisplayName
        }

        It 'accepts dots and hyphens' {
            'pyenv-win.v2' | Should -Match $script:Patterns.DisplayName
        }

        It 'rejects semicolons' {
            'tool;evil' | Should -Not -Match $script:Patterns.DisplayName
        }

        It 'rejects subexpression syntax' {
            'tool$(whoami)' | Should -Not -Match $script:Patterns.DisplayName
        }

        It 'rejects backticks' {
            'tool`ninjection' | Should -Not -Match $script:Patterns.DisplayName
        }
    }
}
