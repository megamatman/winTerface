# Troubleshooting

## pyenv shows as "not found" on the Tools screen

**Symptom:** pyenv shows as "not found" on the Tools screen despite being
installed and working in the shell.

**Cause:** pyenv-win installed via pip uses a different directory structure to
the standard choco or git install. The bin directory is one level deeper:

```
pip install:         ~\.pyenv\pyenv-win\pyenv-win\bin
choco/git install:   ~\.pyenv\pyenv-win\bin
```

winTerface's inventory job probes both paths but if neither matches the
actual install location, pyenv will not resolve.

**Fix:** Run the following to confirm which path your install uses:

```powershell
Get-ChildItem "$env:USERPROFILE\.pyenv" -Recurse -Depth 3 |
    Where-Object { $_.Name -eq 'pyenv.bat' } |
    Select-Object FullName
```

The directory containing `pyenv.bat` must be on PATH when the inventory job
runs. If it is not, [raise an issue](https://github.com/megamatman/winTerface/issues).
