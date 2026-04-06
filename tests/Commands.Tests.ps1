#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . "$PSScriptRoot\..\src\Commands.ps1"
}

# ---------------------------------------------------------------------------
# Test-FuzzyMatch
# ---------------------------------------------------------------------------

Describe 'Test-FuzzyMatch' {
    It 'returns true for exact match' {
        Test-FuzzyMatch -Pattern 'tools' -Text 'tools' | Should -BeTrue
    }

    It 'returns true for prefix match' {
        Test-FuzzyMatch -Pattern 'too' -Text 'tools' | Should -BeTrue
    }

    It 'returns true for subsequence match (non-contiguous characters)' {
        Test-FuzzyMatch -Pattern 'tls' -Text 'tools' | Should -BeTrue
    }

    It 'returns false when characters are not present in order' {
        Test-FuzzyMatch -Pattern 'xyz' -Text 'tools' | Should -BeFalse
    }

    It 'returns false when pattern is longer than text' {
        Test-FuzzyMatch -Pattern 'toolsmith' -Text 'tools' | Should -BeFalse
    }

    It 'returns true for empty pattern (matches everything)' {
        Test-FuzzyMatch -Pattern '' -Text 'tools' | Should -BeTrue
    }

    It 'is case insensitive' {
        Test-FuzzyMatch -Pattern 'TOOLS' -Text 'tools' | Should -BeTrue
        Test-FuzzyMatch -Pattern 'Tools' -Text 'TOOLS' | Should -BeTrue
    }

    It 'handles single-character pattern' {
        Test-FuzzyMatch -Pattern 't' -Text 'tools' | Should -BeTrue
        Test-FuzzyMatch -Pattern 'z' -Text 'tools' | Should -BeFalse
    }
}

# ---------------------------------------------------------------------------
# Get-FuzzyScore
# ---------------------------------------------------------------------------

Describe 'Get-FuzzyScore' {
    It 'returns -1 for no match' {
        Get-FuzzyScore -Pattern 'xyz' -Text 'tools' | Should -Be -1
    }

    It 'returns a positive score for exact match' {
        $score = Get-FuzzyScore -Pattern 'tools' -Text 'tools'
        $score | Should -BeGreaterThan 0
    }

    It 'scores exact match higher than prefix match' {
        $exact  = Get-FuzzyScore -Pattern 'tools' -Text 'tools'
        $prefix = Get-FuzzyScore -Pattern 'tool'  -Text 'tools'
        $exact | Should -BeGreaterThan $prefix
    }

    It 'scores prefix match higher than subsequence match' {
        $prefix = Get-FuzzyScore -Pattern 'too'  -Text 'tools'
        $subseq = Get-FuzzyScore -Pattern 'tls'  -Text 'tools'
        $prefix | Should -BeGreaterThan $subseq
    }

    It 'prefers shorter text (less length penalty)' {
        $short = Get-FuzzyScore -Pattern 'up' -Text 'update'
        $long  = Get-FuzzyScore -Pattern 'up' -Text 'check-for-updates'
        $short | Should -BeGreaterThan $long
    }

    It 'is case insensitive' {
        $lower = Get-FuzzyScore -Pattern 'tools' -Text 'tools'
        $upper = Get-FuzzyScore -Pattern 'TOOLS' -Text 'tools'
        $upper | Should -Be $lower
    }
}

# ---------------------------------------------------------------------------
# Get-TabCompletion
# ---------------------------------------------------------------------------

Describe 'Get-TabCompletion' {
    BeforeEach {
        Reset-TabCompletion
    }

    It 'returns a match for a known prefix' {
        $result = Get-TabCompletion -Text '/too'
        $result | Should -Be '/tools'
    }

    It 'returns null when no commands match' {
        $result = Get-TabCompletion -Text '/zzz'
        $result | Should -BeNullOrEmpty
    }

    It 'cycles through multiple matches on repeated calls with same input' {
        # /a matches: about, add-tool (sorted alphabetically)
        $first = Get-TabCompletion -Text '/a'
        $first | Should -Be '/about'

        $second = Get-TabCompletion -Text '/a'
        $second | Should -Be '/add-tool'
    }

    It 'wraps around after the last match' {
        $first = Get-TabCompletion -Text '/a'
        $first | Should -Be '/about'

        $second = Get-TabCompletion -Text '/a'
        $second | Should -Be '/add-tool'

        # Should wrap back to first
        $third = Get-TabCompletion -Text '/a'
        $third | Should -Be '/about'
    }

    It 'resets cycle when input changes' {
        $first = Get-TabCompletion -Text '/a'
        $first | Should -Be '/about'

        # Change input to /ab -- only 'about' matches
        Reset-TabCompletion
        $changed = Get-TabCompletion -Text '/ab'
        $changed | Should -Be '/about'
    }

    It 'returns all commands for bare slash input' {
        $result = Get-TabCompletion -Text '/'
        # Should return the first command alphabetically
        $result | Should -Not -BeNullOrEmpty
        # The slash commands sorted: about, add-tool, check-for-updates, config, help, profile, quit, tools, update
        $result | Should -Be '/about'
    }

    It 'returns single match without cycling' {
        # /q only matches 'quit'
        $result = Get-TabCompletion -Text '/q'
        $result | Should -Be '/quit'

        # Cycling with single match returns the same
        $again = Get-TabCompletion -Text '/q'
        $again | Should -Be '/quit'
    }
}

# ---------------------------------------------------------------------------
# Get-CommandSuggestions
# ---------------------------------------------------------------------------

Describe 'Get-CommandSuggestions' {
    It 'returns all commands for empty search term' {
        $result = @(Get-CommandSuggestions -SearchTerm '')
        $result.Count | Should -Be $script:SlashCommands.Count
    }

    It 'returns matching commands sorted by score' {
        $result = @(Get-CommandSuggestions -SearchTerm 'tool')
        $result.Count | Should -BeGreaterThan 0
        # 'tools' should score highest (exact prefix)
        $result[0].Command | Should -Be '/tools'
    }

    It 'returns empty for a term that matches nothing' {
        $result = @(Get-CommandSuggestions -SearchTerm 'zzzzz')
        $result.Count | Should -Be 0
    }
}
