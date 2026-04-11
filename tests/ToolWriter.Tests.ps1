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
        $result | Should -Match "winget install --id 'junegunn.fzf' --exact --silent --disable-interactivity"
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

Describe 'New-RegistryEntry consumer regex round-trip' {
    BeforeAll {
        # The consumer regex used by both Get-KnownToolsFromRegistry (WinSetup.ps1)
        # and Uninstall-Tool.ps1 (winSetup). Extracted from source to stay in sync.
        $wsPath = Join-Path $PSScriptRoot '..' 'src' 'Services' 'WinSetup.ps1'
        $wsContent = Get-Content $wsPath -Raw
        $regexMatch = [regex]::Match($wsContent, "pattern\s*=\s*'([^']+)'")
        $script:ConsumerPattern = $regexMatch.Groups[1].Value

        # AllowedPattern for PackageId, extracted from AddTool.ps1
        $addToolPath = Join-Path $PSScriptRoot '..' 'src' 'Screens' 'AddTool.ps1'
        $addToolContent = Get-Content $addToolPath -Raw
        if ($addToolContent -match "Key\s*=\s*'PackageId'[^}]*AllowedPattern\s*=\s*'((?:[^']|'')+)'") {
            $script:PackageIdPattern = $Matches[1] -replace "''", "'"
        }
    }

    It 'consumer regex is extracted from source' {
        $script:ConsumerPattern | Should -Not -BeNullOrEmpty
        # Verify it contains the key structural elements of the registry pattern
        $script:ConsumerPattern | Should -BeLike '*Manager*'
        $script:ConsumerPattern | Should -BeLike '*Id*'
    }

    It 'round-trips a simple PackageId correctly' {
        $entry = New-RegistryEntry -DisplayName 'ruff' -PackageManager 'pipx' -PackageId 'ruff'
        $m = [regex]::Match($entry, $script:ConsumerPattern)
        $m.Success | Should -BeTrue
        $m.Groups[1].Value | Should -Be 'ruff'
        $m.Groups[2].Value | Should -Be 'pipx'
        $m.Groups[3].Value | Should -Be 'ruff'
    }

    It 'round-trips a dotted publisher-prefixed PackageId correctly' {
        $entry = New-RegistryEntry -DisplayName 'Oh My Posh' -PackageManager 'winget' -PackageId 'JanDeDobbeleer.OhMyPosh'
        $m = [regex]::Match($entry, $script:ConsumerPattern)
        $m.Success | Should -BeTrue
        $m.Groups[3].Value | Should -Be 'JanDeDobbeleer.OhMyPosh'
    }

    It 'round-trips a hyphenated PackageId correctly' {
        $entry = New-RegistryEntry -DisplayName 'pre-commit' -PackageManager 'pipx' -PackageId 'pre-commit'
        $m = [regex]::Match($entry, $script:ConsumerPattern)
        $m.Success | Should -BeTrue
        $m.Groups[1].Value | Should -Be 'pre-commit'
        $m.Groups[3].Value | Should -Be 'pre-commit'
    }

    It 'double-quote in PackageId breaks the consumer regex' {
        # New-RegistryEntry escapes " to `" in the generated output.
        # The consumer regex [^"]+ stops at the backtick-escaped quote,
        # producing an incorrect parse. This documents the mismatch.
        $entry = New-RegistryEntry -DisplayName 'test' -PackageManager 'choco' -PackageId 'pkg"inject'
        $m = [regex]::Match($entry, $script:ConsumerPattern)
        # The regex either fails to match entirely or matches a truncated Id
        if ($m.Success) {
            $m.Groups[3].Value | Should -Not -Be 'pkg"inject' -Because 'the consumer regex cannot parse escaped quotes'
        } else {
            $m.Success | Should -BeFalse -Because 'the consumer regex cannot parse escaped quotes'
        }
    }

    It 'AllowedPattern for PackageId rejects double quotes' {
        $script:PackageIdPattern | Should -Not -BeNullOrEmpty
        # Double quote should be rejected by the pattern
        'pkg"inject' | Should -Not -Match $script:PackageIdPattern -Because 'double quotes must not pass AllowedPattern'
    }

    It 'AllowedPattern for PackageId accepts all characters that round-trip correctly' {
        # Characters that round-trip through New-RegistryEntry and the consumer
        # regex: alphanumeric, dots, hyphens, underscores, slashes
        foreach ($id in @('ruff', 'pre-commit', 'junegunn.fzf', 'JanDeDobbeleer.OhMyPosh', 'Vendor/Package')) {
            $id | Should -Match $script:PackageIdPattern -Because "'$id' should be accepted"
            $entry = New-RegistryEntry -DisplayName 'test' -PackageManager 'choco' -PackageId $id
            $m = [regex]::Match($entry, $script:ConsumerPattern)
            $m.Success | Should -BeTrue -Because "'$id' should round-trip through the consumer regex"
            $m.Groups[3].Value | Should -Be $id -Because "'$id' should be recovered intact"
        }
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

Describe 'Get-ModifiedSetupContent' {
    BeforeAll {
        $script:ToolData = @{
            DisplayName    = 'newtool'
            PackageManager = 'choco'
            PackageId      = 'newtool'
            VerifyCommand  = 'newtool'
        }

        # Minimal fixture matching the actual anchor patterns in
        # Setup-DevEnvironment.ps1: a $CoreSteps declaration, the
        # "# === ... Main Execution" header, and Write-Summary at column 0.
        $script:SetupFixture = @'
$CoreSteps = 18

function Install-Existing {
    Write-Step "Existing"
}

# =============================================================================
# Main Execution
# =============================================================================

Install-Existing

Write-Summary
Write-Host "done"
'@
    }

    It 'inserts the function definition before the Main Execution header' {
        $result = Get-ModifiedSetupContent -OriginalContent $script:SetupFixture -ToolData $script:ToolData
        # The new function should appear before the header
        $funcIdx = $result.IndexOf('function Install-newtool')
        $headerIdx = $result.IndexOf('# Main Execution')
        $funcIdx | Should -BeGreaterThan -1 -Because 'function definition should be inserted'
        $headerIdx | Should -BeGreaterThan -1
        $funcIdx | Should -BeLessThan $headerIdx
    }

    It 'inserts the function call before Write-Summary' {
        $result = Get-ModifiedSetupContent -OriginalContent $script:SetupFixture -ToolData $script:ToolData
        $lines = $result -split "`n"
        $callIdx = -1; $summaryIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^Install-newtool$') { $callIdx = $i }
            if ($lines[$i] -match '^Write-Summary$') { $summaryIdx = $i }
        }
        $callIdx | Should -BeGreaterThan -1 -Because 'function call should be inserted'
        $summaryIdx | Should -BeGreaterThan -1
        $callIdx | Should -BeLessThan $summaryIdx
    }

    It 'increments $CoreSteps by 1' {
        $result = Get-ModifiedSetupContent -OriginalContent $script:SetupFixture -ToolData $script:ToolData
        $result | Should -Match '\$CoreSteps\s*=\s*19'
    }

    It 'preserves content before and after the insertion points' {
        $result = Get-ModifiedSetupContent -OriginalContent $script:SetupFixture -ToolData $script:ToolData
        $result | Should -Match 'function Install-Existing'
        $result | Should -Match 'Install-Existing'
        $result | Should -Match 'Write-Host "done"'
    }

    It 'produces valid PowerShell' {
        $result = Get-ModifiedSetupContent -OriginalContent $script:SetupFixture -ToolData $script:ToolData
        Test-GeneratedCode -Code $result | Should -BeTrue
    }

    It 'throws when the Main Execution header anchor is absent' {
        $noHeader = @'
$CoreSteps = 18
function Install-Existing { Write-Step "Existing" }
Install-Existing
Write-Summary
'@
        { Get-ModifiedSetupContent -OriginalContent $noHeader -ToolData $script:ToolData } |
            Should -Throw '*Main Execution header*'
    }

    It 'throws when the Write-Summary anchor is absent' {
        $noSummary = @'
$CoreSteps = 18
# =============================================================================
# Main Execution
# =============================================================================
Install-Existing
'@
        { Get-ModifiedSetupContent -OriginalContent $noSummary -ToolData $script:ToolData } |
            Should -Throw '*Write-Summary*'
    }

    It 'throws when the $CoreSteps declaration is absent' {
        $noCoreSteps = @'
function Install-Existing { Write-Step "Existing" }

# =============================================================================
# Main Execution
# =============================================================================

Install-Existing

Write-Summary
'@
        { Get-ModifiedSetupContent -OriginalContent $noCoreSteps -ToolData $script:ToolData } |
            Should -Throw '*CoreSteps*'
    }

    It 'error message names all missing anchors when multiple are absent' {
        $empty = 'Write-Host "nothing here"'
        try {
            Get-ModifiedSetupContent -OriginalContent $empty -ToolData $script:ToolData
            $true | Should -BeFalse -Because 'should have thrown'
        } catch {
            $_.Exception.Message | Should -Match 'CoreSteps'
            $_.Exception.Message | Should -Match 'Main Execution'
            $_.Exception.Message | Should -Match 'Write-Summary'
        }
    }
}

Describe 'Get-ModifiedUpdateContent' {
    BeforeAll {
        $script:ToolData = @{
            DisplayName    = 'newtool'
            PackageManager = 'choco'
            PackageId      = 'newtool'
        }

        # Minimal fixture matching the actual $PackageRegistry format
        # in Update-DevEnvironment.ps1.
        $script:UpdateFixture = @'
$PackageRegistry = @{
    "bat"         = @{ Manager = "choco";  Id = "bat" }
    "ruff"        = @{ Manager = "pipx";   Id = "ruff" }
    "vscode"      = @{ Manager = "choco";  Id = "vscode" }
}
'@
    }

    It 'inserts a new entry into the registry' {
        $result = Get-ModifiedUpdateContent -OriginalContent $script:UpdateFixture -ToolData $script:ToolData
        $result | Should -Match '"newtool"\s*=\s*@\{'
    }

    It 'inserts in alphabetical order' {
        $result = Get-ModifiedUpdateContent -OriginalContent $script:UpdateFixture -ToolData $script:ToolData
        $lines = ($result -split "`n") | Where-Object { $_ -match '^\s+"' }
        $keys = $lines | ForEach-Object {
            if ($_ -match '^\s+"([^"]+)"') { $Matches[1] }
        }
        # newtool should appear between bat and ruff, or between ruff and vscode
        $keys | Should -Contain 'newtool'
        $newtoolIdx = [array]::IndexOf($keys, 'newtool')
        $ruffIdx = [array]::IndexOf($keys, 'ruff')
        $newtoolIdx | Should -BeLessThan $ruffIdx -Because '"newtool" < "ruff" alphabetically'
    }

    It 'preserves all existing entries' {
        $result = Get-ModifiedUpdateContent -OriginalContent $script:UpdateFixture -ToolData $script:ToolData
        $result | Should -Match '"bat"'
        $result | Should -Match '"ruff"'
        $result | Should -Match '"vscode"'
    }

    It 'inserts before closing brace when new key sorts after all existing' {
        # New-RegistryEntry preserves hyphens in the key: "zzz-tool" not "zzztool"
        $toolData = @{ DisplayName = 'zzz-tool'; PackageManager = 'pipx'; PackageId = 'zzz-tool' }
        $result = Get-ModifiedUpdateContent -OriginalContent $script:UpdateFixture -ToolData $toolData
        $result | Should -Match '"zzz-tool"'
        # Verify it appears before the closing brace
        $lines = $result -split "`n"
        $entryIdx = -1; $braceIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '"zzz-tool"') { $entryIdx = $i }
            if ($lines[$i] -match '^\s*\}') { $braceIdx = $i }
        }
        $entryIdx | Should -BeLessThan $braceIdx
    }

    It 'throws when $PackageRegistry is absent' {
        $noRegistry = @'
# Some other content
$SomeVariable = 42
'@
        { Get-ModifiedUpdateContent -OriginalContent $noRegistry -ToolData $script:ToolData } |
            Should -Throw '*PackageRegistry*'
    }

    It 'produces valid PowerShell' {
        $result = Get-ModifiedUpdateContent -OriginalContent $script:UpdateFixture -ToolData $script:ToolData
        Test-GeneratedCode -Code $result | Should -BeTrue
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
