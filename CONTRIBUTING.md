# Contributing to winTerface

## Terminal.Gui constraints

winTerface uses Terminal.Gui via ConsoleGuiTools. The following rules
must be followed to avoid crashes:

- **Never call Write-Host inside a background job or timer callback.**
  Write-Host corrupts Terminal.Gui's console driver. Use job return
  values or `$script:` variables to pass data back to the UI.

- **Never call Switch-Screen from a key event handler.**
  This destroys the view that owns the event mid-dispatch. Trigger
  screen changes from the timer poll instead.

- **Never use nested Application.Run() for modal dialogs during active
  background jobs without guarding screen rebuilds.** The timer
  continues to fire during modal dialogs and may call Switch-Screen,
  destroying views the caller still holds references to. Set
  `$script:UpdateFlowActive` or an equivalent flag before entering
  a modal dialog.

- **Always capture job state before Remove-Job.**
  Accessing properties on a disposed job object throws.

- **Do not reference function-local variables from .NET event handlers.**
  PowerShell scriptblocks used as .NET delegates do not close over
  function-local scope. Use `$script:` variables instead.

- **Always wrap timer callbacks in try/catch.**
  Unhandled exceptions inside .NET timer delegates propagate through
  Application.Run() and crash the process.

## PowerShell gotchas

- `-not @()` evaluates to `$true`. Use `$null -eq $variable` to
  distinguish "key missing" from "empty array".

- `[DateTime]::Parse()` round-tripped through `.ToString()` can
  mangle dates in non-US locales (DD/MM vs MM/DD). Store dates as
  ISO 8601 strings and parse with `[DateTimeOffset]::Parse()`.

- `Receive-Job` injects `PSComputerName`, `RunspaceId`, and
  `PSShowComputerName` into deserialized objects. Strip these before
  writing to disk.

## Code style

- Use `$e` (not `$eventArgs`) for event handler parameters to avoid
  shadowing PowerShell's automatic variable.
- Use approved verbs for function names (`Add-`, not `Append-`).
- Every function has a comment block describing purpose, parameters,
  and return value.
- All file I/O in try/catch with clear error messages.
- No hardcoded paths -- derive from `$env:WINSETUP` or `$env:USERPROFILE`.
