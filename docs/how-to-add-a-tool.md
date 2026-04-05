# How to add a tool

The Add Tool wizard registers a new tool with winSetup so it can be installed, updated, and uninstalled from winTerface.

## When to use the wizard

Use the wizard when you want to add a tool that is not already in `$script:KnownTools`. The wizard writes to three winSetup files:

1. **Setup-DevEnvironment.ps1**: adds an `Install-<Name>` function and a call in the main execution block.
2. **Update-DevEnvironment.ps1**: adds an entry to `$PackageRegistry` so the tool is included in updates.
3. **profile.ps1** (optional): adds an alias or config block if you provide one.

It also registers the tool in winTerface's `$script:KnownTools` array so it appears on the Tools screen.

## Opening the wizard

From the Tools screen, press `A`. Or type `/add-tool` in the command bar from any screen.

## Search path

Best for well-known tools available in Chocolatey, winget, or PyPI.

1. Select **Search package managers** on the first screen.
2. Enter a search term (e.g. `httpie`, `ripgrep`, `jq`).
3. Three sources are searched concurrently:
   - **Chocolatey**: Windows system tools and CLI utilities.
   - **Winget**: Windows apps and developer tools.
   - **PyPI**: Python CLI tools via pipx. Uses exact name lookup with common variations.
4. Select a result from any source. The wizard populates all fields automatically.
5. Review the auto-populated fields. Press `Enter` to continue or select "Edit fields" to adjust.
6. The confirmation screen shows a diff preview of all changes. Press `C` to write.

## Manual entry path

Best for tools not found in package search, or when you need precise control.

1. Select **Enter tool details manually** on the first screen.
2. Fill in each field:

| Field | Required | Description | Allowed characters |
|-------|----------|-------------|-------------------|
| Display name | Yes | Friendly name (e.g. `ripgrep`). Used in function names and UI. | Letters, digits, hyphens, dots, underscores, spaces |
| Package manager | Yes | Select from `choco`, `winget`, `pipx`, `manual`. | Selection list |
| Package ID | Yes | Exact ID used by the package manager (e.g. `BurntSushi.ripgrep.MSVC` for winget). | Letters, digits, hyphens, dots, underscores, slashes |
| Verify command | Yes | Command to test installation (e.g. `rg`). | Letters, digits, hyphens, dots, underscores |
| Profile alias | No | Alias or config line for `profile.ps1` (e.g. `Set-Alias rg ripgrep`). | Letters, digits, common PS syntax characters |

3. The confirmation screen shows the generated code. Press `C` to write.

## Package managers

| Source | Best for | Install command generated |
|--------|----------|--------------------------|
| Chocolatey | Windows system tools, CLI utilities | `choco install '<id>' -y` |
| winget | Windows apps, developer tools | `winget install '<id>' --silent --accept-package-agreements --accept-source-agreements` |
| pipx | Python CLI tools | `pipx install '<id>'` |
| manual | Tools with custom install steps | No install command; marks tool as "must be installed manually" |

## After registration

### What gets written

The wizard performs an atomic write: all three files are modified in memory, validated by the PowerShell parser, and written together. If any write fails, all files are rolled back to their originals.

Backups of each modified file are created automatically (`.bak-<timestamp>`), with old backups pruned to the most recent 3.

### Verifying the registration

1. The tool appears on the **Tools** screen with its install status.
2. Running `.\Update-DevEnvironment.ps1 -Package <name>` updates the tool.
3. Running `.\Uninstall-Tool.ps1 -Tool <name>` removes it from all files.

### Installing after registration

After confirming the wizard changes, a dialog asks whether to install the tool immediately. Selecting "Install now" navigates to the Tools screen and runs the `Install-<Name>` function via a background job.

## Troubleshooting

See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) for:
- Search returns no results
- Description panel issues
- PyPI exact match limitation
