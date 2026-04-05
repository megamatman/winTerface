# How to manage your profile

The Profile screen monitors the deployed PowerShell profile (`$PROFILE`) against the canonical source in winSetup (`$env:WINSETUP\profile.ps1`). It detects missing sections, content drift, and provides one-click redeployment.

## Opening the Profile screen

From any screen, type `/profile` in the command bar. Or press `Esc` to go back, navigate to the Home menu, and select **Profile**.

## Understanding health status

The Profile screen shows two types of status:

### Section health (left panel)

Each row represents an expected profile section (SSH Agent, Chocolatey, fzf, PSReadLine, etc.). A checkmark means the section's signature pattern was found in `$PROFILE`. An X means the pattern is missing.

Missing sections indicate the deployed profile is incomplete, typically because it predates a winSetup update that added the section.

### Drift status (header)

Drift compares the full content of `$PROFILE` against `$env:WINSETUP\profile.ps1`:

| Status | Meaning |
|--------|---------|
| In sync | The files are identical |
| Drifted | The files differ (even if all sections are present) |
| Source not found | `$env:WINSETUP\profile.ps1` does not exist |

The Home screen shows a combined status: "Healthy" if all sections are present and in sync, "Drifted" if sections are present but content differs, or "N sections missing" if sections are absent.

## Viewing drift details

Press `D` to open a modal showing the differences between the deployed and source profiles. Lines unique to the deployed profile and lines unique to the source are listed separately.

## Comparing in VS Code

Press `C` to open both files in VS Code's diff view. This shows a full side-by-side comparison with syntax highlighting.

## Opening in VS Code

Press `O` to open a dialog with three options:
1. **profile.ps1 (source)**: the winSetup canonical profile. Edit this to make changes.
2. **$PROFILE (deployed)**: the active profile. View-only; changes here are overwritten on redeploy.
3. **Compare both**: opens the diff view (same as `C`).

## Redeploying the profile

Press `R` to redeploy. A confirmation dialog explains what will happen:
- The current `$PROFILE` is backed up to `$PROFILE.bak-<timestamp>`.
- `$env:WINSETUP\profile.ps1` is copied to `$PROFILE`.
- Old backups are pruned, keeping the most recent 3.

The redeploy runs as a background job. Progress streams to the detail panel. When complete, a reminder dialog prompts you to run:

```powershell
. $PROFILE
```

This reloads the profile in the current session. New terminal sessions load the updated profile automatically.

## After redeployment

1. The health checks refresh automatically after redeploy completes.
2. The drift status updates to "In sync".
3. Run `. $PROFILE` in your terminal to apply changes to the current session.

## Workflow for profile changes

The canonical profile lives in `$env:WINSETUP\profile.ps1`. To make changes:

1. Edit `$env:WINSETUP\profile.ps1` directly (press `O` then select "source").
2. Open the Profile screen and press `R` to redeploy.
3. Run `. $PROFILE` to apply.

Do not edit `$PROFILE` directly. Changes made to `$PROFILE` are overwritten on the next redeploy.
