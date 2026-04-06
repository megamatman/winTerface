# Release Notes: v1.0.0

Released: 2026-04-06

## What this is

winTerface is a PowerShell 7+ terminal UI for managing a Windows 11
development environment configured by winSetup. Keyboard-driven,
pane-based, with slash commands and background job polling.

## Screens

| Screen | Purpose |
|--------|---------|
| Home | Dashboard with environment health, profile status, update count, and poll error indicator |
| Updates | Check and apply updates per-tool or in bulk, with streaming output |
| Tools | View installed tools, install, update, or remove individually |
| Add Tool | Multi-step wizard: search choco/winget/PyPI or enter details manually |
| Profile | Health checks, drift detection, redeploy, VS Code integration |
| Config | Settings editor, winSetup path management, update cache viewer |
| About | Version, environment info, project links |

## What is included

| File | Purpose |
|------|---------|
| `winTerface.ps1` | Entry point: dependency check, first-run wizard, launches TUI |
| `Install-WinTerface.ps1` | Idempotent installer: PS7 check, ConsoleGuiTools, env var, alias |
| `src/App.ps1` | Terminal.Gui bootstrap, layout, 500ms poll timer, job cleanup |
| `src/Config.ps1` | Config file read/write/validation |
| `src/Commands.ps1` | Slash command registry, fuzzy matching, tab completion |
| `src/Navigation.ps1` | Screen switching, global key handler, autocomplete overlay |
| `src/Helpers/` | Elevation check, colour schemes, UI helpers |
| `src/Services/WinSetup.ps1` | winSetup interface: path validation, profile health, tool inventory |
| `src/Services/PackageManager.ps1` | choco/winget/pipx/PyPI query, search, description |
| `src/Services/UpdateCache.ps1` | Background update checking, ISO 8601 cache |
| `src/Services/ToolWriter.ps1` | Code generation for new tools, atomic file writer |
| `src/Screens/` | 7 screen files plus AddTool-Search.ps1 and AddTool-Guided.ps1 |
| `tests/` | Pester test suite (6 files, 107 tests) |

## Key features

- Background update checking with configurable interval
- Per-tool and full update execution with streaming output
- Add Tool wizard with concurrent choco/winget/PyPI search
- Profile health checks and drift detection against winSetup source
- Slash commands with fuzzy matching and tab completion cycling
- KnownTools derived from winSetup's PackageRegistry at startup (no static duplicate)
- Output pane text capped at 500 lines to prevent memory growth
- Background job cleanup on application exit (9 job variables)
- Poll errors surfaced in home screen status panel
- Inline validation errors in guided wizard (no silent input clearing)

## Test coverage

107 Pester v5 tests across 6 files:

| File | Tests | Coverage |
|------|------:|---------|
| ToolWriter.Tests.ps1 | 25 | Code generation for all 4 managers, quote injection, parser validation |
| PackageManager.Tests.ps1 | 24 | choco/winget/pipx output parsing, search functions, empty/error cases |
| Commands.Tests.ps1 | 24 | Fuzzy matching, scoring, tab completion cycling, suggestions |
| Config.Tests.ps1 | 15 | Interval validation boundaries, path validation, read/write round-trip |
| UpdateCache.Tests.ps1 | 12 | ISO 8601 date round-tripping, locale independence, staleness, structure |
| WinSetup.Tests.ps1 | 7 | KnownTools registry parsing, metadata merge, fallback behaviour |

## Requirements

- Windows 11
- PowerShell 7+
- Microsoft.PowerShell.ConsoleGuiTools module
- winSetup installed and configured (`$env:WINSETUP` set)

## Known limitations

- Terminal.Gui v1 constraint: `Switch-Screen` must not be called from
  child view key event handlers. The global `$top` KeyPress handler in
  Navigation.ps1 is a documented exception (see CONTRIBUTING.md).
- `$script:UpdateFlowActive` must guard all modal dialogs to prevent
  the 500ms timer from calling `Switch-Screen` during nested event loops.
- KnownTools parsing depends on the `$PackageRegistry` regex format
  defined in winSetup's INTERFACE.md (contract version 1). Format changes
  in winSetup require a corresponding update here.

## Documentation

| Document | Contents |
|----------|---------|
| `README.md` | Installation, screens, key bindings, slash commands |
| `KEYBINDINGS.md` | Complete key binding reference for all screens |
| `CONTRIBUTING.md` | Terminal.Gui constraints, poll architecture, screen/search-source guides |
| `TROUBLESHOOTING.md` | 16 symptom-first troubleshooting entries |
| `docs/how-to-add-a-tool.md` | Guide to registering tools via the wizard |
| `docs/how-to-manage-profile.md` | Guide to profile health and redeployment |
