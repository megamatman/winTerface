# winTerface

Terminal UI for managing a Windows 11 development environment configured by [winSetup](https://github.com/megamatman/winSetup). Keyboard-driven, pane-based, with slash commands. Replaces manual config file editing, update checking, and tool management with a single interactive console.

> **Note:** winTerface uses Terminal.Gui via ConsoleGuiTools. Certain patterns
> -- nested `Application.Run`, `Write-Host` in callbacks, `Switch-Screen` from
> key handlers -- are architectural constraints. See
> [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Prerequisites

- **PowerShell 7+**
- **[winSetup](https://github.com/megamatman/winSetup)** installed and configured (`$env:WINSETUP` set)
- **Microsoft.PowerShell.ConsoleGuiTools** module (installed automatically by the install script)

## Installation

```powershell
git clone https://github.com/megamatman/winTerface.git
cd winTerface
.\Install-WinTerface.ps1
```

The install script:
1. Checks PowerShell 7+
2. Installs/upgrades ConsoleGuiTools
3. Creates `~\.winTerface\` config directory
4. Sets `WINTERFACE` User environment variable
5. Adds `wti` alias to your PowerShell profile

Safe to run multiple times.

## First run

```powershell
wti
```

Or run directly:

```powershell
.\winTerface.ps1
```

On first launch, winTerface asks for the path to your winSetup directory. It validates that `Setup-DevEnvironment.ps1` exists before saving.

## Screens

- **Home** -- Status dashboard, main menu, quick start tips
- **Updates** -- Check for updates across choco, winget, and pipx (with PyPI version checking). Per-tool or full updates with streaming output
- **Tools** -- View all managed tools with version and status. Install, update, remove, or add new tools via the wizard
- **Profile** -- Health checks for all 22 profile sections, drift detection, VS Code diff, one-click redeploy
- **Config** -- Edit winTerface settings, manage winSetup path, view update cache

## Keybindings

| Key | Action |
|---|---|
| Up / Down | Navigate lists |
| Enter | Select or confirm |
| Escape | Go back one level |
| Tab | Cycle slash command completion |
| F1 | Show help overlay |
| / | Focus the command bar |
| Ctrl+Q | Quit |

Screen-specific keys are shown in the hint bar at the bottom of each screen.

## Slash commands

Type `/` to open the command bar. Tab cycles through completions.

| Command | Action |
|---|---|
| `/tools` | Open Tools screen |
| `/add-tool` | Launch the Add Tool wizard |
| `/update` | Open Updates screen |
| `/check-for-updates` | Force an update check |
| `/profile` | Open Profile screen |
| `/config` | Open Config screen |
| `/about` | Version and environment info |
| `/help` | Show all keybindings |
| `/quit` | Exit |

## Project structure

```
winTerface/
  winTerface.ps1              Entry point
  Install-WinTerface.ps1      Installer
  src/
    App.ps1                   Main loop, layout, timer polling
    Config.ps1                Config file read/write/validation
    Commands.ps1              Slash command registry, fuzzy matching, tab completion
    Navigation.ps1            Screen switching, focus, autocomplete overlay
    Helpers/                  Color schemes, elevation check
    Services/                 winSetup interface, package managers, update cache, tool writer
    Screens/                  Home, Updates, Tools, AddTool, Profile, Config, About
```

## Known limitations

- **Remote desktop and SSH** may intercept `Ctrl+` key combinations before they
  reach Terminal.Gui. `Ctrl+Q` (quit) may not work over Chrome Remote Desktop
  or some SSH clients. Use `/quit` from the command bar instead.

## Created by

Matt Lawrence
