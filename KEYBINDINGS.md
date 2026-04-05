# Key bindings

Key bindings are also shown in the `F1` help overlay available on every screen.

## Global

These keys work on every screen.

| Key | Action |
|-----|--------|
| `F1` | Open help overlay |
| `/` | Focus the slash command bar |
| `Tab` | Cycle slash command tab completion |
| `Esc` | Dismiss autocomplete, go back one level, or return to previous screen |
| `Ctrl+Q` | Quit winTerface |
| `Up` / `Down` | Navigate lists |
| `Enter` | Select or confirm |

## Home

| Key | Action |
|-----|--------|
| `Enter` | Navigate to the highlighted menu item |
| `/` | Focus command bar |

## Updates

When updates are available:

| Key | Action |
|-----|--------|
| `Space` | Toggle selection on a single update |
| `A` | Select all updates |
| `U` | Update selected tools individually |
| `Ctrl+R` | Run full update (all registered tools) |
| `F5` | Check for new updates |
| `/` | Focus command bar |

When no updates are available:

| Key | Action |
|-----|--------|
| `F5` | Check for new updates |
| `/` | Focus command bar |

## Tools

| Key | Action |
|-----|--------|
| `A` | Open the Add Tool wizard |
| `I` | Install the highlighted tool |
| `U` | Update the highlighted tool |
| `X` | Remove the highlighted tool (shows confirmation dialog) |
| `O` | Open the install location in File Explorer |
| `F5` | Rescan tool inventory |
| `/` | Focus command bar |

## Add Tool

Key bindings vary by wizard step.

### Choose path

| Key | Action |
|-----|--------|
| `Enter` | Select the highlighted path (Search or Manual) |

### Search input

| Key | Action |
|-----|--------|
| `Enter` | Start search |
| `Esc` | Go back |

### Search results

| Key | Action |
|-----|--------|
| `Enter` | Select the highlighted result |
| `Tab` | Move focus to the next source section |
| `Shift+Tab` | Move focus to the previous source section |
| `Esc` | Go back |

### Review fields

| Key | Action |
|-----|--------|
| `Enter` | Continue to preview or edit fields |
| `Esc` | Go back |

### Guided steps (text input)

| Key | Action |
|-----|--------|
| `Enter` | Accept value and advance (blank skips optional fields) |
| `Esc` | Go back |

### Guided steps (selection)

| Key | Action |
|-----|--------|
| `Enter` | Select option and advance |
| `Esc` | Go back |

### Confirmation

| Key | Action |
|-----|--------|
| `C` | Confirm and write changes |
| `Esc` | Go back |

## Profile

| Key | Action |
|-----|--------|
| `R` | Redeploy profile from winSetup source |
| `D` | View drift diff between deployed and source profiles |
| `C` | Compare both profiles side by side in VS Code |
| `O` | Open a profile file in VS Code |
| `F5` | Refresh health checks |
| `/` | Focus command bar |

## Config

Key actions depend on the selected section.

| Key | Section | Action |
|-----|---------|--------|
| `E` | winTerface, winSetup | Edit the selected field |
| `S` | winTerface | Save settings |
| `V` | winSetup | Verify the winSetup path |
| `C` | Update cache | Clear the update cache |
| `R` | Update cache | Force an update check |
| `T` | Tools | Open the Tools screen |
| `/` | All | Focus command bar |
