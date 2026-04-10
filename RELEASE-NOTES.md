# Release Notes: v1.1.0

Released: 2026-04-10

## Fixes

- `PackageManager.ps1` uses `Invoke-Pipx` instead of calling pipx
  directly. On some Windows configurations, pipx.exe is a Python launcher
  script and fails with StandardOutputEncoding errors. `Invoke-Pipx`
  retries via `python -m pipx` when the direct call throws. 3 call sites
  replaced: `Get-PipxTools` (JSON and text paths) and
  `Get-PipxUpdateAvailable`.
- `Get-ChocoUpdates` now accepts an optional `-KnownTools` parameter.
  When provided, results are filtered to only packages registered in
  `$PackageRegistry` with Manager = 'choco'. The call site in
  `UpdateCache.ps1` passes KnownTools entries extracted before the job
  boundary. Unmanaged packages (7zip, filezilla, etc.) no longer appear
  on the Updates screen.
- `Get-ProfileDriftStatus` strips the winTerface launcher block from the
  deployed `$PROFILE` before diffing, via `Remove-WinTerfaceLauncherBlock`.
  The block is identified by the `# winTerface launcher` comment header.
  Prevents false positive drift detection on every machine where
  winTerface is installed.
- `UpdateCache.ps1` job state access wrapped in try/catch. Accessing
  `.State` on a disposed job no longer throws.
- Guided wizard shows inline validation error on invalid input instead of
  clearing the input silently.
- Background job cleanup on application exit: the `Start-WinTerface`
  finally block explicitly stops and removes all 9 job variables to
  prevent orphaned pwsh.exe processes.
- Output pane text capped at 500 lines to prevent memory growth during
  long update runs.
- `Save-NewToolRegistration` errors surfaced to the user instead of
  swallowed.
- VerifyCommand defaults to the package ID with source-appropriate
  transforms: winget IDs strip the publisher prefix, choco and PyPI IDs
  are lowercased as-is.
- `F6` replaces `Ctrl+R` for full update on the Updates screen. `Ctrl+R`
  was intercepted by the terminal driver.
- Update output now visible in the output pane. Write-Output replaced
  with the correct output stream for background job capture.

## Features

- SHA256 checksums for all source files via `New-Checksums.ps1`.
  `checksums.sha256` published as a release asset.

## Refactoring

- `AddTool.ps1` split into `AddTool.ps1` (dispatcher and shared
  helpers), `AddTool-Search.ps1` (search wizard path with job
  management), and `AddTool-Guided.ps1` (guided wizard steps and field
  validation).
- `KnownTools` derived from winSetup's `$PackageRegistry` at startup via
  `Get-KnownToolsFromRegistry`. Each entry now includes a `PackageId`
  field. No static duplicate maintained.

## Documentation

- `CONTRIBUTING.md`: poll table updated to reflect 7 named poll functions
  (`Invoke-UpdateCheckPoll`, `Invoke-UpdateRunPoll`, etc.). em dashes
  replaced. `Switch-Screen` Esc handler documented as known exception.
- `README.md`: "Verifying files" section with `Get-FileHash`
  instructions. Project structure updated with all test files and
  missing screen files.
- Documentation links section updated to include `RELEASE-NOTES.md`.

## Tests

126 Pester v5 tests across 7 files (up from 25 at v1.0.0):

| File | Tests | Coverage |
|------|------:|---------|
| ToolWriter.Tests.ps1 | 25 | Code generation for all 4 managers, quote injection, parser validation |
| PackageManager.Tests.ps1 | 29 | choco/winget/pipx output parsing, search functions, KnownTools filter, pipx fallback |
| Commands.Tests.ps1 | 24 | Fuzzy matching, scoring, tab completion cycling, suggestions |
| Config.Tests.ps1 | 15 | Interval validation boundaries, path validation, read/write round-trip |
| UpdateCache.Tests.ps1 | 12 | ISO 8601 date round-tripping, locale independence, staleness, structure |
| WinSetup.Tests.ps1 | 10 | KnownTools registry parsing, metadata merge, fallback behaviour, profile drift with launcher block |
| New-Checksums.Tests.ps1 | 11 | Output format, entry count, hash verification, exclusions |

---

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
