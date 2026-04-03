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

## Phase 4 -- Profile management ✓ complete
Profile health checks, drift detection, diff view, redeploy action.
Post-phase fixes: Terminal.Gui crash prevention (closure variables,
Switch-Screen in key handlers, nested Application.Run), update cache
correctness (ISO 8601 dates, job metadata pollution, empty array
checks, count mismatch), pipx update support, profile detail panel
improvements (plain-language descriptions, closure fix), F5/check
feedback, PSScriptAnalyzer cleanup across all files.

## Phase 5 -- Config management (current)
winTerface settings editor with validation. winSetup path management
with env var + profile.ps1 fallback update and backup. Tool inventory
with background version scanning. Update cache viewer with clear and
refresh.

## Phase 6 -- Polish and public release
Error handling hardening, performance, help documentation, release packaging.
