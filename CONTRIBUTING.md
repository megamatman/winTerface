# Contributing to winTerface

## Terminal.Gui constraints

winTerface uses Terminal.Gui via ConsoleGuiTools. The following rules
must be followed to avoid crashes:

- **Never call Write-Host inside a callback, event handler, or timer handler.**
  Write-Host corrupts Terminal.Gui's console driver. Use job return
  values or `$script:` variables to pass data back to the UI.
  Write-Host inside `Start-Job` scriptblocks still leaks to the console
  via the information stream when `Receive-Job` is called. All winSetup
  script invocations inside jobs must use subprocess isolation
  (`pwsh -NoProfile -NonInteractive -Command`) to prevent bleed.
  See the critical constraints in CLAUDE.md for the pattern.

- **Never execute code after Switch-Screen inside an event handler.**
  `Switch-Screen` calls `RemoveAll()` on the content container, which
  destroys all child views. Code that runs after the call and accesses
  a view from the replaced screen will throw on a disposed object.
  Safe patterns: `OpenSelectedItem` handlers and `KeyPress` handlers
  where `Switch-Screen` is the final action before `return`. The
  global `KeyPress` handler on `$top` in `Navigation.ps1` is also safe
  because `$top` is the application root, not a child view. See the
  "Switch-Screen safety" section below for the full reference.

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

- **Dialog input fields must be stored at `$script:` scope before registering
  event handlers.** A `TextField` or any other view stored in a function-local
  variable resolves to `$null` inside `.add_Clicked` and similar handlers.
  Use `$script:_<DescriptiveName>` as the naming convention.

  Confirmed `$script:` variables used for event handler scope in this codebase:

  | Variable | Screen | Purpose |
  |---|---|---|
  | `$script:Layout.MenuList` | Multiple | Main navigation list |
  | `$script:_EditInput` | Config | TextField in config edit dialogs |
  | `$script:_EditResult` | Config | Return value from edit dialog |
  | `$script:_PathConfirmed` | Config | Confirmation flag for path change dialog |
  | `$script:_ClearConfirmed` | Config | Confirmation flag for cache clear dialog |
  | `$script:_SearchInput` | AddTool | TextField in package search step |
  | `$script:_CurrentStep` | AddTool | Step definition hashtable in guided wizard |
  | `$script:_GuidedInput` | AddTool | TextField in guided text input steps |
  | `$script:_InstallNow` | AddTool | Flag from install-now dialog |
  | `$script:_RedeployConfirmed` | Profile | Confirmation flag for redeploy dialog |
  | `$script:_OpenChoice` | Profile | Selection index from open-file dialog |
  | `$script:_UpdateItems` | Updates | Cached update list for mark checking |
  | `$script:_UpdateListStrings` | Updates | Mutable List backing the ListView |
  | `$script:_ToolDetailView` | Tools | Detail panel TextView reference |
  | `$script:_RemoveChoice` | Tools | Selection from remove confirmation dialog |
  | `$script:_RemovingToolName` | Tools | Tool name being uninstalled (for cleanup) |
  | `$script:_ElevWarningResult` | WinSetup | Return value from elevation warning dialog |
  | `$script:_UpdateColWidths` | Updates | Column widths calculated from dataset for table formatting |
  | `$script:_ChoosePathDesc` | AddTool | Dynamic description label on choose-path screen |
  | `$script:_ChoosePathDescriptions` | AddTool | Description strings array for choose-path options |
  | `$script:_SearchLists` | AddTool | Ordered array of search result ListViews (choco, winget, pypi) |
  | `$script:_SearchResults` | AddTool | Ordered array of search result data arrays |
  | `$script:_SearchManagers` | AddTool | Ordered array of manager strings for search sections |
  | `$script:_ResultDescView` | AddTool | Description panel TextView on search results screen |
  | `$script:DescriptionJob` | AddTool | Background job for lazy choco/winget description fetch |
  | `$script:_DescriptionResult` | AddTool | Metadata (ListIndex, ItemIndex) for pending description fetch |
  | `$script:_HomeStatusLabels` | Home | Status label references for in-place updates (avoids full rebuild) |

  When adding new dialogs or handlers, follow this pattern and add new
  variables to this table.

- **Always wrap timer callbacks in try/catch.**
  Unhandled exceptions inside .NET timer delegates propagate through
  Application.Run() and crash the process.

## Terminal.Gui patterns

### Screen builder structure

Every screen is a function named `Build-<Name>Screen` that takes a
`$Container` parameter (the content area view). The function:

1. Adds labels, frames, and ListViews to `$Container`.
2. Wires `.add_KeyPress`, `.add_OpenSelectedItem`, and
   `.add_SelectedItemChanged` handlers on interactive views.
3. Sets `$script:Layout.MenuList` to the primary focusable view.
4. Calls `.SetFocus()` on that view.

Views are constructed once inside `Build-*Screen`. They are never
recreated inside poll callbacks or timer handlers. When a screen needs
to refresh (e.g. after a background job completes), the timer calls
`Switch-Screen` which calls `RemoveAll()` then `Build-*Screen` again.

### Modal dialogs

Modal dialogs use `[Terminal.Gui.Application]::Run($dialog)` which
starts a nested event loop. The 500ms timer continues to fire during
this nested loop. To prevent the timer from calling `Switch-Screen`
and destroying the dialog's parent views:

```powershell
$script:UpdateFlowActive = $true
try { [Terminal.Gui.Application]::Run($dialog) } catch {}
$script:UpdateFlowActive = $false
```

The timer poll code checks `$script:UpdateFlowActive` before calling
`Switch-Screen` to rebuild screens.

Simple dismiss dialogs (OK button only, no state changes possible from
the timer) may omit the guard, but adding it is always safe.

### Switch-Screen safety

`Switch-Screen` calls `$script:Layout.Content.RemoveAll()` then
`Build-*Screen`. This destroys all child views of the content area.
The risk is code that runs *after* the call and accesses a view that
was just destroyed. The navigation itself is safe in all contexts
below.

**Safe to call from:**
- The timer callback (`Invoke-BackgroundPoll`), the standard path.
- `OpenSelectedItem` handlers where `Switch-Screen` is the last
  statement. The event fires after selection completes, and no view
  access follows. Used throughout the AddTool wizard and Home menu.
- `KeyPress` handlers where `Switch-Screen` is followed only by
  `$e.Handled = $true; return`. No disposed view is accessed. Used
  in Tools.ps1, Config.ps1, Profile.ps1, and the guided wizard.
- Named functions called from key handlers (e.g. `Step-WizardBack`),
  provided Switch-Screen is the final action before return.
- The global `KeyPress` handler on `$top` in Navigation.ps1, which
  is safe because `$top` is the application root, not a child view.

**Unsafe pattern:** Any code after `Switch-Screen` that reads or
writes a view variable from the previous screen. The view has been
removed by `RemoveAll()` and accessing it throws.

## Background poll architecture

### The 500ms timer

`Start-WinTerface` in `App.ps1` registers a `MainLoop.AddTimeout`
callback that fires every 500ms. This callback calls
`Invoke-BackgroundPoll`, which polls all active background jobs.

All UI updates from background work happen inside this callback.
Because it runs on the `MainLoop` thread, it is safe to modify view
properties (`.Text`, `.SetNeedsDisplay()`) and call `Switch-Screen`.

### Job types

The poll function checks these job types in order:

| # | Job Variable | Purpose | Polled By |
|---|---|---|---|
| 1 | `$script:UpdateCheckJob` | Background package manager update check | `Invoke-UpdateCheckPoll` (delegates to `Update-BackgroundCheckStatus`) |
| 2 | `$script:UpdateRunJob` | Full or per-package update execution | `Invoke-UpdateRunPoll` |
| 3 | `$script:ChocoSearchJob`, `$script:WingetSearchJob`, `$script:PyPISearchJob` | AddTool wizard package search | `Invoke-SearchPoll` (delegates to `Update-SearchJobStatus`) |
| 3b | `$script:DescriptionJob` | Lazy description fetch for choco/winget results | `Invoke-DescriptionPoll` |
| 4 | `$script:ProfileRedeployJob` | Profile redeploy via Apply-PowerShellProfile.ps1 | `Invoke-ProfileRedeployPoll` |
| 5 | `$script:ToolInventoryJob` | Tool inventory scan (Get-Command + --version) | `Invoke-InventoryPoll` |
| 6 | `$script:ToolActionJob` | Tool install/update/remove from Tools screen | `Invoke-ToolActionPoll` |

### Adding a new job type

1. Declare `$script:YourJob = $null` at file scope in the relevant
   screen or service file.

2. Start the job with `Start-Job -ScriptBlock { ... } -ArgumentList ...`.
   Inside the scriptblock:
   - Refresh PATH: `$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')`
   - Dot-source any needed scripts (e.g. PackageManager.ps1).
   - Wrap the body in `try/catch`, `Write-Error` on failure.
   - Pass data via `-ArgumentList`, not closure capture.

3. Add a polling section in `Invoke-BackgroundPoll` (App.ps1):
   ```powershell
   if ($script:YourJob) {
       $job = $script:YourJob
       $jobState = try { $job.State } catch { 'Failed' }
       if ($jobState -ne 'Running') {
           try { $result = Receive-Job $job -ErrorAction Stop } catch {}
           try { Remove-Job $job -Force -ErrorAction SilentlyContinue } catch {}
           $script:YourJob = $null
           # Update UI with $result
       }
   }
   ```

4. Always capture `$job.State` before `Remove-Job`. Accessing State
   on a disposed job throws.

5. Always `Remove-Job` before setting the variable to `$null`.

6. If the job can be cancelled (e.g. user leaves the screen), add
   cleanup to `Stop-WizardSearchJobs` or the relevant screen's
   teardown path in `Switch-Screen`.

## How to add a new screen

Use `About.ps1` as the simplest reference: it has a header, labels,
and a hint bar with no background jobs or key handlers.

### Step by step

1. **Create the screen file.** Add `src/Screens/NewScreen.ps1` with a
   function `Build-NewScreenScreen($Container)`. Follow the pattern:
   header label, content views, hints bar, set
   `$script:Layout.MenuList` and call `.SetFocus()`.

2. **Dot-source it.** Add a line in `winTerface.ps1` in the Screens
   section (load order matters; screens are loaded after services):
   ```powershell
   . (Join-Path $PSScriptRoot 'src' 'Screens' 'NewScreen.ps1')
   ```

3. **Register in Switch-Screen.** Add a case in the `switch` block in
   `Navigation.ps1`:
   ```powershell
   'NewScreen' { Build-NewScreenScreen -Container $script:Layout.Content }
   ```

4. **Add navigation.** Add a menu item in `$script:HomeMenuItems`
   (Home.ps1) or a key handler on an existing screen that calls
   `Switch-Screen -ScreenName 'NewScreen'`.

5. **Add a slash command.** Add an entry to `$script:SlashCommands`
   in `Commands.ps1`:
   ```powershell
   @{ Command = '/newscreen'; Description = '...'; Screen = 'NewScreen'; Action = $null }
   ```

6. **Update the help overlay.** Add a line to the screen-specific
   section in `Show-HelpOverlay` (App.ps1).

7. **Add key handlers.** Wire `.add_KeyPress` on the primary ListView
   for screen-specific actions. Include the standard `/` handler to
   focus the command bar and `Escape` to return home.

## How to add a new package manager search source

The AddTool wizard searches multiple package managers concurrently.
To add a new source (e.g. npm, cargo):

### 1. Add a search function to PackageManager.ps1

```powershell
function Search-NewSource {
    param([string]$Name)
    # Query the package manager
    # Return @(@{ Name = '...'; Version = '...'; PackageId = '...'; Description = '...'; Source = 'newsource' })
    # Return @() on failure or no results
}
```

Follow the existing pattern: never throw, return empty array on
failure, wrap in try/catch, add `.SYNOPSIS`.

### 2. Add state variables to AddTool.ps1

At the top of the file alongside the existing job/results variables:

```powershell
$script:NewSourceSearchJob     = $null
$script:NewSourceSearchResults = @()
```

Add `'NewSourceSearchJob'` to the `Stop-WizardSearchJobs` foreach list.
Add `$script:NewSourceSearchResults = @()` to `Reset-WizardState`.

### 3. Start the job in Start-WizardSearch

Add a `Start-Job` block following the choco/winget/pypi pattern:

```powershell
$script:NewSourceSearchJob = Start-Job -ScriptBlock {
    param($sp, $term)
    try {
        . $sp
        Search-NewSource -Name $term
    } catch { Write-Error "Job failed: $_" }
} -ArgumentList $pkgMgrScript, $SearchTerm
```

### 4. Poll the job in Update-SearchJobStatus

Add a block matching the existing pattern:

```powershell
if ($script:NewSourceSearchJob) {
    if ($script:NewSourceSearchJob.State -ne 'Running') {
        try { $script:NewSourceSearchResults = @(Receive-Job $script:NewSourceSearchJob -ErrorAction SilentlyContinue) }
        catch { $script:NewSourceSearchResults = @() }
        try { Remove-Job $script:NewSourceSearchJob -Force } catch {}
        $script:NewSourceSearchJob = $null
    } else { $allDone = $false }
}
```

Update the guard at the top of `Update-SearchJobStatus` to include the
new job variable in the early return check.

### 5. Add a section in Build-WizardSearchResults

Add the new source to the `$script:_SearchResults` and
`$script:_SearchManagers` arrays. Call `Add-SearchResultSection` with
the appropriate title, Y position, and list index.

### 6. Update the search input screen

Add a descriptor line in `Build-WizardSearchInput` alongside the
existing Chocolatey/Winget/PyPI labels.

### 7. Update Build-WizardSearching

Add a status label for the new source in the "Searching..." screen.

## PowerShell gotchas

- `-not @()` evaluates to `$true`. Use `$null -eq $variable` to
  distinguish "key missing" from "empty array".

- `[DateTime]::Parse()` round-tripped through `.ToString()` can
  mangle dates in non-US locales (DD/MM vs MM/DD). Store dates as
  ISO 8601 strings and parse with `[DateTimeOffset]::Parse()`.

- `Receive-Job` injects `PSComputerName`, `RunspaceId`, and
  `PSShowComputerName` into deserialized objects. Strip these before
  writing to disk.

## Release process

1. Run `.\New-Checksums.ps1` in both the winSetup and winTerface repos.
2. Commit `checksums.sha256` before tagging.
3. Tag the release: `git tag -a v<version> -m "v<version>"`
4. Push the tag: `git push origin v<version>`
5. Create the GitHub release, attaching `checksums.sha256` as a release asset:
   `gh release create v<version> --title "v<version>" --notes-file RELEASE-NOTES.md --attach checksums.sha256`
6. Update the bootstrap URL in `README.md` and `bootstrap.ps1` to point to the new release tag.

## Code style

- Use `$script:` scope for anything referenced from .NET event handlers.
  Function-local variables are not visible to event scriptblocks.
- Use `$e` (not `$eventArgs`) for event handler parameters to avoid
  shadowing PowerShell's automatic variable.
- Use approved verbs for function names (`Add-`, not `Append-`).
- Every function has a comment block describing purpose, parameters,
  and return value.
- All file I/O in try/catch with clear error messages.
- No hardcoded paths. Derive from `$env:WINSETUP` or `$env:USERPROFILE`.
