# CLI Style TODO (oooconf)

This checklist tracks the remaining visual/UX polish work for `oooconf` help output.

- [x] Normalize command-row rendering helpers in shell wrappers (`ui_command_row` / `Write-UiCommandRow`).
- [x] Align command and icon columns for readable scanability in ASCII mode.
- [x] Ensure color roles include `hint` and `muted` in PowerShell formatter.
- [x] Keep section separators consistent with UTF/Nerd-font capability detection.
- [x] Remove Unix-only commands from PowerShell command suggestion set (`$KnownCommands`).
- [x] Update PowerShell help note/workflow examples to avoid suggesting Unix-only commands.
- [x] Re-run shell help output checks after visual updates.
- [x] Add explicit UTF/encoding gate for Nerd Font icons in Bash wrapper output detection.
- [x] Apply visual heading styling to command-specific help pages (`oooconf help <command>`) in both wrappers.
- [x] Add PowerShell CLI help smoke checks to CI on Windows runner.

## Done criteria

All items above are checked and reflected in tracked CLI wrappers:

- `scripts/ooodnakov.sh`
- `scripts/ooodnakov.ps1`
