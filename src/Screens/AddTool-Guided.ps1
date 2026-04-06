# AddTool-Guided.ps1 - Guided wizard path: all guided input steps and
#                      field validation

# ---------------------------------------------------------------------------
# Guided step builder (generic)
# ---------------------------------------------------------------------------

function Build-WizardGuidedStep {
    <#
    .SYNOPSIS
        Builds a single step of the guided wizard.
    .PARAMETER Container
        Parent view.
    .PARAMETER StepIndex
        Zero-based index into $script:GuidedSteps.
    #>
    param($Container, [int]$StepIndex)

    $step = $script:GuidedSteps[$StepIndex]
    $stepNum = $StepIndex + 1
    $totalSteps = $script:GuidedSteps.Count

    Add-WizardHeader -Container $Container -Breadcrumb "Step $stepNum of $totalSteps"

    $titleLabel = [Terminal.Gui.Label]::new("  $($step.Title)")
    $titleLabel.X = 0; $titleLabel.Y = 2; $titleLabel.Width = [Terminal.Gui.Dim]::Fill()
    if ($script:Colors.Header) { $titleLabel.ColorScheme = $script:Colors.Header }
    $Container.Add($titleLabel)

    $descLabel = [Terminal.Gui.Label]::new("  $($step.Desc)")
    $descLabel.X = 0; $descLabel.Y = 3; $descLabel.Width = [Terminal.Gui.Dim]::Fill()
    $Container.Add($descLabel)

    # $step is function-local and resolves to $null in .NET event handlers.
    # Stored as $script:_CurrentStep before registering OpenSelectedItem.
    # Also used by the guided text KeyPress handler for the same reason.
    $script:_CurrentStep = $step

    if ($step.Type -eq 'select') {
        Add-GuidedSelectInput -Container $Container -Step $step
    } else {
        Add-GuidedTextInput -Container $Container -Step $step
    }
}

# ---------------------------------------------------------------------------
# Select input
# ---------------------------------------------------------------------------

function Add-GuidedSelectInput {
    <#
    .SYNOPSIS
        Builds the selection list branch of a guided wizard step.
    #>
    param($Container, $Step)

    $optStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($o in $Step.Options) { $optStrings.Add("  $o") }

    $selList = [Terminal.Gui.ListView]::new($optStrings)
    $selList.X = 4; $selList.Y = 5
    $selList.Width = [Terminal.Gui.Dim]::Fill(4)
    $selList.Height = $Step.Options.Count
    $selList.AllowsMarking = $false
    if ($script:Colors.Menu) { $selList.ColorScheme = $script:Colors.Menu }

    $currentVal = $script:WizardData[$Step.Key]
    if ($currentVal) {
        $idx = $Step.Options.IndexOf($currentVal)
        if ($idx -ge 0) { $selList.SelectedItem = $idx }
    }

    $selList.add_OpenSelectedItem({
        param($e)
        $script:WizardData[$script:_CurrentStep.Key] = $script:_CurrentStep.Options[$e.Item]
        $script:WizardStep = $script:_CurrentStep.Next
        Switch-Screen -ScreenName 'AddTool'
    })

    $selList.add_KeyPress({
        param($e)
        if ($e.KeyEvent.Key -eq [Terminal.Gui.Key]::Esc) {
            Step-WizardBack
            $e.Handled = $true
        }
    })

    $Container.Add($selList)
    $script:Layout.MenuList = $selList
    $selList.SetFocus()
}

# ---------------------------------------------------------------------------
# Text input with validation
# ---------------------------------------------------------------------------

function Get-AllowedPatternDescription {
    <#
    .SYNOPSIS
        Returns a human-readable description of an AllowedPattern regex.
    #>
    param([string]$Pattern)

    # Map known patterns to plain-language descriptions
    switch -Regex ($Pattern) {
        'a-zA-Z0-9\\-\\._\\s'  { return 'letters, digits, hyphens, dots, underscores, spaces' }
        'a-zA-Z0-9\\-\\.\_\/'  { return 'letters, digits, hyphens, dots, underscores, slashes' }
        'a-zA-Z0-9\\-\\.\_\]'  { return 'letters, digits, hyphens, dots, underscores' }
        default                 { return $Pattern }
    }
}

function Add-GuidedTextInput {
    <#
    .SYNOPSIS
        Builds the text input branch of a guided wizard step.
    #>
    param($Container, $Step)

    # $tf and $step are function-local and resolve to $null in .NET event
    # handlers. Stored as $script:_GuidedInput and $script:_CurrentStep.
    $currentVal = $script:WizardData[$Step.Key]
    $script:_GuidedInput = [Terminal.Gui.TextField]::new($(if ($currentVal) { $currentVal } else { '' }))
    $script:_GuidedInput.X = 4; $script:_GuidedInput.Y = 5
    $script:_GuidedInput.Width = [Terminal.Gui.Dim]::Fill(4); $script:_GuidedInput.Height = 1
    if ($script:Colors.CommandBar) { $script:_GuidedInput.ColorScheme = $script:Colors.CommandBar }

    # Inline error label -- hidden until validation fails
    $script:_GuidedErrorLabel = [Terminal.Gui.Label]::new('')
    $script:_GuidedErrorLabel.X = 4; $script:_GuidedErrorLabel.Y = 6
    $script:_GuidedErrorLabel.Width = [Terminal.Gui.Dim]::Fill(4); $script:_GuidedErrorLabel.Height = 1
    if ($script:Colors.StatusError) { $script:_GuidedErrorLabel.ColorScheme = $script:Colors.StatusError }
    $Container.Add($script:_GuidedErrorLabel)

    # Clear the error label when the user modifies the text
    $script:_GuidedInput.add_TextChanged({
        param($oldText)
        if ($script:_GuidedErrorLabel) {
            $script:_GuidedErrorLabel.Text = ''
            try { $script:_GuidedErrorLabel.SetNeedsDisplay() } catch {}
        }
    })

    $script:_GuidedInput.add_KeyPress({
        param($e)
        if ($e.KeyEvent.Key -eq [Terminal.Gui.Key]::Enter) {
            $val = $script:_GuidedInput.Text.ToString().Trim()
            if ($script:_CurrentStep.Required -and [string]::IsNullOrWhiteSpace($val)) {
                $e.Handled = $true
                return
            }
            # Validate against field-specific allowlist to prevent code injection
            if ($val -and $script:_CurrentStep.AllowedPattern -and
                $val -notmatch $script:_CurrentStep.AllowedPattern) {
                # Show inline error -- leave the user's input in place
                if ($script:_GuidedErrorLabel) {
                    $desc = Get-AllowedPatternDescription -Pattern $script:_CurrentStep.AllowedPattern
                    $script:_GuidedErrorLabel.Text = "Invalid input. Allowed: $desc"
                    try { $script:_GuidedErrorLabel.SetNeedsDisplay() } catch {}
                }
                $e.Handled = $true
                return
            }
            $script:WizardData[$script:_CurrentStep.Key] = $val
            $script:WizardStep = $script:_CurrentStep.Next
            Switch-Screen -ScreenName 'AddTool'
            $e.Handled = $true
        }
        if ($e.KeyEvent.Key -eq [Terminal.Gui.Key]::Esc) {
            Step-WizardBack
            $e.Handled = $true
        }
    })

    $optionalHint = if (-not $Step.Required) { ' (press Enter to skip)' } else { '' }
    Add-WizardHint -Container $Container -Y 8 `
        -Text "Enter to continue${optionalHint}, Escape to go back"

    $Container.Add($script:_GuidedInput)
    $script:Layout.MenuList = $null
    $script:_GuidedInput.SetFocus()
}
