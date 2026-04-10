#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $script:ChecksumScript = Get-Content "$PSScriptRoot\..\New-Checksums.ps1" -Raw
    $script:ChecksumFile   = "$PSScriptRoot\..\checksums.sha256"
    $script:RepoRoot       = (Resolve-Path "$PSScriptRoot\..").Path

    # Compute expected file list: tracked .ps1 + quotes.txt, minus tests/ and New-Checksums.ps1
    $ps1Files = @(& git -C $script:RepoRoot ls-files "*.ps1")
    $txtFiles = @(& git -C $script:RepoRoot ls-files "src/Screens/quotes.txt")
    $script:ExpectedFiles = @(($ps1Files + $txtFiles) | Where-Object {
        $_ -notmatch '^tests/' -and $_ -ne 'New-Checksums.ps1'
    } | Sort-Object)
}

Describe 'New-Checksums.ps1 structure' {
    It 'has a .SYNOPSIS help block' {
        $script:ChecksumScript | Should -Match '\.SYNOPSIS'
    }

    It 'does not require Administrator' {
        $script:ChecksumScript | Should -Not -Match '#Requires.*RunAsAdministrator'
        $script:ChecksumScript | Should -Not -Match 'Assert-Administrator'
    }

    It 'uses git ls-files to enumerate tracked files' {
        $script:ChecksumScript | Should -Match 'git.*ls-files'
    }

    It 'uses Get-FileHash with SHA256 algorithm' {
        $script:ChecksumScript | Should -Match 'Get-FileHash.*SHA256'
    }
}

Describe 'checksums.sha256 output' {
    It 'exists at the repo root' {
        Test-Path $script:ChecksumFile | Should -BeTrue
    }

    It 'contains no test file entries' {
        $lines = @(Get-Content $script:ChecksumFile | Where-Object { $_ -ne '' })
        $testLines = $lines | Where-Object { $_ -match 'tests/' }
        $testLines | Should -BeNullOrEmpty
    }

    It 'does not contain a New-Checksums.ps1 entry' {
        $lines = @(Get-Content $script:ChecksumFile | Where-Object { $_ -ne '' })
        $selfLines = $lines | Where-Object { $_ -match 'New-Checksums\.ps1' }
        $selfLines | Should -BeNullOrEmpty
    }

    It 'each entry matches sha256sum format: 64 hex chars, two spaces, forward-slash path' {
        $lines = @(Get-Content $script:ChecksumFile | Where-Object { $_ -ne '' })
        foreach ($line in $lines) {
            $line | Should -Match '^[0-9a-f]{64}  \S+$'
        }
        $backslashLines = $lines | Where-Object { $_ -match '\\' }
        $backslashLines | Should -BeNullOrEmpty
    }

    It 'includes quotes.txt' {
        $content = Get-Content $script:ChecksumFile -Raw
        $content | Should -Match 'quotes\.txt'
    }

    It 'entry count matches the number of tracked non-test source and data files' {
        $lines = @(Get-Content $script:ChecksumFile | Where-Object { $_ -ne '' })
        $lines.Count | Should -Be $script:ExpectedFiles.Count
    }

    It 'hash for a sample file matches Get-FileHash output' {
        $expected = (Get-FileHash -Path "$script:RepoRoot\src\App.ps1" -Algorithm SHA256).Hash.ToLower()
        $line = Get-Content $script:ChecksumFile | Where-Object { $_ -match '  src/App\.ps1$' }
        $fileHash = ($line -split '\s{2}')[0]
        $fileHash | Should -Be $expected
    }
}
