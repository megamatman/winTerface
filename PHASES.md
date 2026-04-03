# Development Phases

## Phase 1 -- Shell and navigation ✓ complete
Layout, command bar, fuzzy autocomplete, first-run wizard, status dashboard.

## Phase 2 -- Update management ✓ complete
Updates screen, choco/winget/pipx update status, streaming update output,
elevation detection, update caching.

## Phase 3 -- Add tool wizard and individual updates ✓ complete
Package manager search (choco + winget), guided wizard, diff preview,
atomic file writes to winSetup config files. Individual per-tool updates
via Update-DevEnvironment.ps1 -Package.
Post-phase fixes: Three latent closure bugs in AddTool.ps1 (search input
KeyPress, guided select OpenSelectedItem, guided text KeyPress). All
handlers now reference $script: scoped variables. Post-fix audit of all
11 handlers confirmed clean.

## Phase 4 -- Profile management ✓ complete
Profile health checks, drift detection, diff view, redeploy action.
Post-phase fixes: Terminal.Gui crash prevention (closure variables,
Switch-Screen in key handlers, nested Application.Run), update cache
correctness (ISO 8601 dates, job metadata pollution, empty array
checks, count mismatch), pipx update support, profile detail panel
improvements (plain-language descriptions, closure fix), F5/check
feedback, PSScriptAnalyzer cleanup across all files.

## Phase 5 -- Config management ✓ complete
winTerface settings editor with validation. winSetup path management
with env var + profile.ps1 fallback update and backup. Tool inventory
with background version scanning. Update cache viewer with clear and
refresh.

## Phase 6 -- Tools screen and install script ✓ complete
Tools screen: full tool inventory with install, update, remove, and
add actions. Remove calls Uninstall-Tool.ps1 with output streaming.
Install calls Setup-DevEnvironment.ps1 -InstallTool. Config screen
tools section replaced with navigation link to Tools screen.
Install-WinTerface.ps1: idempotent installer, sets WINTERFACE env
var, installs ConsoleGuiTools, creates config directory, adds 'wti'
profile alias.

## Phase 7 -- Polish and public release ✓ complete
Error handling audit: all 37 event handlers verified for closure safety,
all 11 job scriptblocks wrapped in try/catch, job lifecycle and nested
Application.Run verified clean. Help overlay expanded with screen-specific
keybindings. Install script hardened with version upgrade check, per-step
failure handling, and 'wti' alias (avoids Windows Terminal 'wt' conflict).
README.md rewritten for release.
