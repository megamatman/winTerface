# Troubleshooting

Find your symptom below. Each entry gives the cause in one sentence and the fix as a command or action.

## Startup and installation

### winTerface fails to launch with "ConsoleGuiTools module not found"

**Cause:** The Microsoft.PowerShell.ConsoleGuiTools module is not installed.

**Fix:**
```powershell
Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser
```

### `Install-WinTerface.ps1` fails with "winSetup not found"

**Cause:** `$env:WINSETUP` is not set, or winSetup has not been installed.

**Fix:** Install and run winSetup first:
```powershell
cd path\to\winSetup
.\Setup-DevEnvironment.ps1
```
Then re-run `.\Install-WinTerface.ps1`.

### `Install-WinTerface.ps1` fails with "does not support -InstallTool"

**Cause:** The installed winSetup version predates the `-InstallTool` parameter.

**Fix:** Pull the latest winSetup and re-run setup:
```powershell
cd $env:WINSETUP
git pull
.\Setup-DevEnvironment.ps1
```

### winTerface launches but profile health shows an error

**Cause:** `$env:WINSETUP` is not set, or `Setup-DevEnvironment.ps1` has not been run.

**Fix:** Run the winSetup setup script, which sets `$env:WINSETUP` automatically:
```powershell
cd path\to\winSetup
.\Setup-DevEnvironment.ps1
```

## Home screen

### Profile health shows "Healthy" on Home but "Drifted" on Profile screen

**Cause:** The Home screen checks whether all expected profile sections are present (pattern matching). The Profile screen compares the deployed `$PROFILE` byte-for-byte against the winSetup source. A profile can have all sections present but differ from the source in whitespace or comments.

**Fix:** Open the Profile screen and press `R` to redeploy from the winSetup source. Run `. $PROFILE` to apply changes.

### Update count does not change after running updates

**Cause:** The update cache refreshes asynchronously after the update job completes.

**Fix:** Wait a few seconds for the background recheck, or press `F5` on the Updates screen to force a fresh check.

## Updates screen

### winget packages show "upgrade failed"

**Cause:** winget returns exit code `-1978335189` (`0x8A15002B`) when no update is available. This is a winget convention, not a failure.

**Fix:** This exit code is handled automatically and reported as "already up to date". If you see an actual failure message, check the output pane for details.

### `Ctrl+U` does not trigger updates

**Cause:** Some terminal emulators intercept `Ctrl+U` as a line-clear signal before it reaches the application.

**Fix:** Use `F6` instead. Function keys are not intercepted by terminal drivers or PSReadLine.

### Updates screen shows a parse error or no updates on a non-English Windows locale

**Cause:** winget outputs localised column headers on non-English locales. winTerface cannot parse these and reports a failure rather than silently showing no updates.

**Fix:** There is no workaround for non-English locales currently. Raise an issue on the winTerface repository with your locale and the winget output from running `winget upgrade` in your terminal.

## Tools screen

### A tool shows "not found" despite being installed

**Cause:** The tool is not registered in `$script:KnownTools`. winTerface only tracks tools registered through winSetup or the Add Tool wizard.

**Fix:** Use the Add Tool wizard (`A` on the Tools screen or `/add-tool`) to register the tool.

### pyenv shows "not found" despite being installed

**Cause:** pyenv-win installed via pip creates a different directory structure (`~\.pyenv\pyenv-win\pyenv-win\bin`) than Chocolatey/winget (`~\.pyenv\pyenv-win\bin`). The inventory job probes both layouts.

**Fix:** The inventory scan handles both layouts automatically. If pyenv is still not detected, confirm the directory exists:
```powershell
Get-ChildItem "$env:USERPROFILE\.pyenv" -Recurse -Depth 3 |
    Where-Object { $_.Name -eq 'pyenv.bat' } |
    Select-Object FullName
```
The directory containing `pyenv.bat` must be on PATH when the inventory job runs. If it is not found, [raise an issue](https://github.com/megamatman/winTerface/issues).

## Add Tool wizard

### Search returns no results

**Cause:** Network connectivity issue, or the queried package managers are not installed.

**Fix:** Verify each source is available:
```powershell
choco --version        # Chocolatey
winget --version       # winget
pip --version          # pip (required for PyPI lookup)
```
PyPI search uses `Invoke-RestMethod` and requires internet access.

### Description panel shows "No description available"

**Cause:** Descriptions for Chocolatey and winget results are fetched lazily via a background job. The fetch may not have completed yet.

**Fix:** Wait a moment, or move the highlight away and back to retrigger the fetch.

### Wizard reports "anchor not found" or "file structure may have changed"

**Cause:** The anchor patterns used to locate insertion points in winSetup's Setup-DevEnvironment.ps1 or Update-DevEnvironment.ps1 have changed. This typically happens after a winSetup update that restructures the files.

**Fix:** Pull the latest winSetup and re-run the setup script:
```powershell
cd $env:WINSETUP
git pull
.\Setup-DevEnvironment.ps1
```
If the error persists, raise an issue on the winTerface repository with the exact error message.

### PyPI search only finds exact matches

**Cause:** PyPI does not provide a public fuzzy search API. The search queries the exact package name and common variations (`python-<term>`, `py<term>`, `<term>-cli`).

**Fix:** Enter the exact PyPI package name. Check [pypi.org](https://pypi.org) to confirm the package name.

## Profile screen

### Redeploy completed but changes are not visible in the current session

**Cause:** Redeploying copies the source `profile.ps1` to `$PROFILE`, but the current session still has the old profile loaded.

**Fix:**
```powershell
. $PROFILE
```
winTerface shows a reminder dialog after successful redeploy.

### Profile screen shows drift on a fresh Windows installation even after redeploying

**Cause:** Windows writes CRLF line endings by default. If the winSetup source uses LF line endings, a strict byte comparison reports drift. This is resolved automatically by the line ending normalisation in the drift check.

**Fix:** If drift persists after redeploying, press R to redeploy again. The redeployed file will use consistent line endings.

### Drift view shows differences but all sections pass health checks

**Cause:** Health checks verify section presence via pattern matching. Drift detection compares full file content. Minor whitespace or comment changes cause drift without failing health checks.

**Fix:** Press `R` to redeploy if you want the profiles to match exactly.

## Config screen

### Saving settings shows a validation error

**Cause:** The entered winSetup path does not exist, or `Setup-DevEnvironment.ps1` is not found inside it.

**Fix:**
```powershell
Test-Path "path\to\winSetup\Setup-DevEnvironment.ps1"
```
