# winTerface

A PowerShell terminal UI for managing a Windows 11 development environment configured by winSetup.

winTerface removes the complexity of manually editing config files, checking for updates, and managing tools. It is keyboard-driven, pane-based, and accepts slash commands via a persistent input bar.

## Requirements

- **PowerShell 7+**
- **Microsoft.PowerShell.ConsoleGuiTools** module (Terminal.Gui based)
- **winSetup** repository

## Installation

1. Install the required PowerShell module:

   ```powershell
   Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser
   ```

2. Clone this repository:

   ```powershell
   git clone <repo-url> winTerface
   ```

3. Run winTerface:

   ```powershell
   ./winTerface/winTerface.ps1
   ```

## First-run setup

On first launch, winTerface will ask for the path to your winSetup directory. It validates that `Setup-DevEnvironment.ps1` exists at that path before saving.

The configuration is stored at `~/.winTerface/config.json`.

You can also set the `WINSETUP` environment variable beforehand:

```powershell
$env:WINSETUP = "C:\path\to\winSetup"
```

## Keybindings

| Key       | Action                         |
| --------- | ------------------------------ |
| Up / Down | Navigate menu items or lists   |
| Enter     | Select / confirm               |
| Escape    | Go back one level              |
| Tab       | Accept autocomplete suggestion |
| F1        | Show help overlay              |
| /         | Focus the command bar          |
| Ctrl+Q    | Quit                           |

## Slash commands

| Command              | Description                      |
| -------------------- | -------------------------------- |
| `/tools`             | Open the tools screen            |
| `/add-tool`          | Launch the add tool wizard       |
| `/update`            | Open the updates screen          |
| `/check-for-updates` | Force an update check            |
| `/profile`           | Open profile health screen       |
| `/config`            | Open configuration screen        |
| `/about`             | Show version and environment info|
| `/help`              | Show all commands and keybindings|
| `/quit`              | Exit winTerface                  |

## Project structure

```
winTerface/
  winTerface.ps1          # Entry point
  src/
    App.ps1               # Main application loop and layout
    Config.ps1            # Config file read/write
    Navigation.ps1        # Focus management, keybinding routing
    Commands.ps1          # Slash command registry and fuzzy matcher
    Screens/              # Screen modules (Home, Tools, Updates, etc.)
    Services/             # Backend service modules (WinSetup, PackageManager)
    Helpers/              # Shared utility functions (UI, Elevation)
```

See [PHASES.md](PHASES.md) for the development roadmap.
