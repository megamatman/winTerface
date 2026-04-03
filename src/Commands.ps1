# Commands.ps1 - Slash command registry and fuzzy matching

$script:SlashCommands = @(
    @{ Command = '/tools';              Description = 'Open the tools screen';              Screen = 'Tools';   Action = $null }
    @{ Command = '/add-tool';           Description = 'Launch the add tool wizard';         Screen = 'AddTool'; Action = $null }
    @{ Command = '/update';             Description = 'Open the updates screen';            Screen = 'Updates'; Action = $null }
    @{ Command = '/check-for-updates';  Description = 'Force an update check now';          Screen = $null;     Action = 'CheckUpdates' }
    @{ Command = '/profile';            Description = 'Open profile health screen';         Screen = 'Profile'; Action = $null }
    @{ Command = '/config';             Description = 'Open configuration screen';          Screen = 'Config';  Action = $null }
    @{ Command = '/about';              Description = 'Show version and environment info';  Screen = 'About';   Action = $null }
    @{ Command = '/help';               Description = 'Show all commands and keybindings';  Screen = $null;     Action = 'Help' }
    @{ Command = '/quit';               Description = 'Exit winTerface';                    Screen = $null;     Action = 'Quit' }
)

# Tab completion cycling state
$script:TabCompletion = @{
    LastInput = ''       # normalised input when Tab was last pressed
    Matches   = @()      # command names matching LastInput (sorted)
    Index     = 0        # current position in Matches
}

function Get-TabCompletion {
    <#
    .SYNOPSIS
        Returns the next tab completion candidate for the current input.
    .DESCRIPTION
        On first press, builds a sorted list of commands whose names start
        with the typed prefix. On repeated presses with the same input,
        cycles through the list. Typing a new character resets the cycle
        via Reset-TabCompletion.
    .PARAMETER Input
        The current text in the command bar including the leading slash.
    .OUTPUTS
        [string] The completed command string, or $null if no match.
    #>
    param([string]$Input)

    $normalised = $Input.ToLower().TrimEnd()

    # If input changed since last Tab, rebuild the match list
    if ($normalised -ne $script:TabCompletion.LastInput) {
        $script:TabCompletion.LastInput = $normalised
        $script:TabCompletion.Index     = 0

        if ($normalised -eq '' -or $normalised -eq '/') {
            # Show all commands
            $script:TabCompletion.Matches = @(
                $script:SlashCommands | ForEach-Object { $_.Command.TrimStart('/') } | Sort-Object
            )
        } else {
            # Match commands that start with the typed prefix
            $prefix = $normalised.TrimStart('/')
            $script:TabCompletion.Matches = @(
                $script:SlashCommands |
                    ForEach-Object { $_.Command.TrimStart('/') } |
                    Where-Object { $_.StartsWith($prefix) } |
                    Sort-Object
            )
        }

        if ($script:TabCompletion.Matches.Count -eq 0) { return $null }
    } else {
        # Same input -- advance the cycle index
        if ($script:TabCompletion.Matches.Count -eq 0) { return $null }
        $script:TabCompletion.Index =
            ($script:TabCompletion.Index + 1) % $script:TabCompletion.Matches.Count
    }

    return "/$($script:TabCompletion.Matches[$script:TabCompletion.Index])"
}

function Reset-TabCompletion {
    <#
    .SYNOPSIS
        Resets the tab completion cycle. Called on every text change so that
        typing a character after a Tab completion starts a fresh match.
    #>
    $script:TabCompletion.LastInput = ''
    $script:TabCompletion.Matches  = @()
    $script:TabCompletion.Index    = 0
}

function Get-AllSlashCommands {
    <#
    .SYNOPSIS
        Returns all registered slash commands.
    .OUTPUTS
        [array] Array of command hashtables with Command, Description, Screen, Action keys.
    #>
    return $script:SlashCommands
}

function Test-FuzzyMatch {
    <#
    .SYNOPSIS
        Tests if pattern characters appear in order within text (case-insensitive).
    .PARAMETER Pattern
        The search characters to match in order.
    .PARAMETER Text
        The text to match against.
    .OUTPUTS
        [bool] True if the pattern characters appear in order in the text.
    #>
    param(
        [string]$Pattern,
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Pattern)) { return $true }

    $pi = 0
    $patLower = $Pattern.ToLower()
    $txtLower = $Text.ToLower()

    for ($ti = 0; $ti -lt $txtLower.Length -and $pi -lt $patLower.Length; $ti++) {
        if ($txtLower[$ti] -eq $patLower[$pi]) { $pi++ }
    }

    return ($pi -eq $patLower.Length)
}

function Get-FuzzyScore {
    <#
    .SYNOPSIS
        Scores a fuzzy match for ranking. Higher is better, -1 means no match.
    .PARAMETER Pattern
        The search pattern.
    .PARAMETER Text
        The text to score against.
    .OUTPUTS
        [int] Score value. -1 if no match.
    #>
    param(
        [string]$Pattern,
        [string]$Text
    )

    if (-not (Test-FuzzyMatch -Pattern $Pattern -Text $Text)) { return -1 }

    $score = 0
    $patLower = $Pattern.ToLower()
    $txtLower = $Text.ToLower()

    # Bonus for prefix match
    if ($txtLower.StartsWith($patLower)) { $score += 100 }

    # Bonus for substring match
    if ($txtLower.Contains($patLower)) { $score += 50 }

    # Penalty for length difference (prefer shorter commands)
    $score -= ($txtLower.Length - $patLower.Length)

    # Bonus for consecutive character matches
    $pi = 0; $consecutive = 0; $maxConsecutive = 0
    for ($ti = 0; $ti -lt $txtLower.Length -and $pi -lt $patLower.Length; $ti++) {
        if ($txtLower[$ti] -eq $patLower[$pi]) {
            $pi++; $consecutive++
            if ($consecutive -gt $maxConsecutive) { $maxConsecutive = $consecutive }
        } else {
            $consecutive = 0
        }
    }
    $score += ($maxConsecutive * 10)

    return $score
}

function Get-CommandSuggestions {
    <#
    .SYNOPSIS
        Returns slash commands matching the search term, sorted by relevance.
    .PARAMETER SearchTerm
        The text to match against command names (without leading /).
    .OUTPUTS
        [array] Matched command hashtables sorted by descending score.
    #>
    param(
        [string]$SearchTerm
    )

    if ([string]::IsNullOrEmpty($SearchTerm)) {
        return $script:SlashCommands
    }

    $results = @()
    foreach ($cmd in $script:SlashCommands) {
        $cmdName = $cmd.Command.TrimStart('/')
        $score = Get-FuzzyScore -Pattern $SearchTerm -Text $cmdName
        if ($score -ge 0) {
            $results += @{
                Command     = $cmd.Command
                Description = $cmd.Description
                Screen      = $cmd.Screen
                Action      = $cmd.Action
                Score       = $score
            }
        }
    }

    return ($results | Sort-Object { $_.Score } -Descending)
}

function Invoke-SlashCommand {
    <#
    .SYNOPSIS
        Executes a slash command by name.
    .PARAMETER CommandText
        The full command text including leading / (e.g. "/quit").
    #>
    param(
        [string]$CommandText
    )

    $cmdName = $CommandText.Trim().ToLower()
    $matched = $script:SlashCommands | Where-Object { $_.Command -eq $cmdName } | Select-Object -First 1

    if (-not $matched) {
        # Fall back to best fuzzy match
        $searchTerm = $cmdName.TrimStart('/')
        $suggestions = Get-CommandSuggestions -SearchTerm $searchTerm
        if ($suggestions.Count -gt 0) { $matched = $suggestions[0] }
    }

    if (-not $matched) { return }

    if ($matched.Action) {
        switch ($matched.Action) {
            'Quit'         { Request-ApplicationExit }
            'Help'         { Show-HelpOverlay }
            'CheckUpdates' {
                Start-BackgroundUpdateCheck -Force
                Switch-Screen -ScreenName 'Updates'
                Add-UpdateOutput -Text "Checking for updates..."
            }
        }
    }
    elseif ($matched.Screen) {
        Switch-Screen -ScreenName $matched.Screen
    }
}
