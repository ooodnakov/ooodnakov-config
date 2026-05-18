# CLI Extension Guide

Use this guide when adding, renaming, or moving `oooconf` commands. The goal is to keep the Unix and PowerShell entrypoints stable while extending the shared command model in one predictable place.

## Source of Truth

The public CLI is split across a small set of files:

| Area | File(s) | Notes |
|------|---------|-------|
| Command/completion metadata | `scripts/cli/oooconf-cli-spec.toml` | Recursive command tree used by generated completions. |
| Top-level Unix dispatch | `scripts/setup/ooodnakov.sh` and `scripts/setup/lib/oooconf-dispatch.sh` | Parses global flags, normalizes command aliases, and calls command handlers. |
| Top-level PowerShell dispatch | `scripts/setup/ooodnakov.ps1` and `scripts/setup/lib/oooconf-dispatch.ps1` | Mirrors Unix behavior for Windows and PowerShell users. |
| Command implementation modules | `scripts/setup/lib/oooconf-*.sh` and `scripts/setup/lib/oooconf-*.ps1` | Focused command families such as `shell`, `color`, `wm`, `bar`, `help`, and UI helpers. |
| Setup command modules | `scripts/setup/lib/setup-*.sh` and `scripts/setup/lib/setup-*.ps1` | Installer, links, optional dependency, doctor, completion, and summary helpers called by setup entrypoints. |
| Generated completions | `home/.config/ooodnakov/zsh/completions/_oooconf` and `home/.config/ooodnakov/completions/oooconf-completions.ps1` | Regenerate these; do not hand-edit generated output. |

## Add or Change a Command

1. **Add the command to the CLI spec.**
   - Edit `scripts/cli/oooconf-cli-spec.toml`.
   - Add top-level commands under `[commands.<name>]`.
   - Add nested commands under `[commands.<parent>.subcommands.<child>]`.
   - Add `description`, `options`, `values`, `value_set`, `option_value_sets`, or `completers` on the command node that owns them.

2. **Implement dispatch on both supported shells.**
   - For setup-style commands, prefer routing through `Invoke-SetupCommand` / `exec_setup_command` so global flags such as `--dry-run`, `--skip-deps`, and `--yes-optional` keep consistent behavior.
   - For command families with local logic, add focused handlers to mirrored `scripts/setup/lib/oooconf-<area>.sh` and `scripts/setup/lib/oooconf-<area>.ps1` modules, then call those handlers from the top-level `switch`/`case` in the entrypoint.
   - Keep public entrypoints thin. Avoid moving large command bodies back into `scripts/setup/ooodnakov.sh`, `scripts/setup/ooodnakov.ps1`, `scripts/setup/setup.sh`, or `scripts/setup/setup.ps1`.

3. **Update help text.**
   - Add examples and command-specific help to `scripts/setup/lib/oooconf-help.sh` and `scripts/setup/lib/oooconf-help.ps1`.
   - Verify `oooconf --help` and `oooconf help <command>` stay useful for the new command and its nested commands.

4. **Regenerate completions.**
   - Run `uv run python scripts/cli/generate_oooconf_completions.py`.
   - Commit the regenerated Zsh and PowerShell completion files when they change.

5. **Update documentation when behavior changes.**
   - Update `README.md` for user-facing command changes.
   - Update `docs/architecture.md` for layout or responsibility changes.
   - Update `docs/reproducibility.md` when setup, install, lock, or generated-artifact behavior changes.

## Command Metadata Patterns

Use these TOML patterns in `scripts/cli/oooconf-cli-spec.toml`:

```toml
[commands.example]
description = "run an example workflow"
options = { "--dry-run" = "preview actions without changing files" }
values = { "status" = "show status", "apply" = "apply changes" }
```

For nested commands:

```toml
[commands.example.subcommands.status]
description = "show example status"

[commands.example.subcommands.apply]
description = "apply example changes"
options = { "--force" = "overwrite existing values" }
```

For shared dynamic values, prefer definitions instead of duplicating lists:

```toml
[definitions.example_modes]
fast = "fast mode"
safe = "safe mode"

[commands.example.subcommands.mode]
description = "set example mode"
value_set = "example_modes"
```

## Cross-Platform Checklist

Before opening a PR for CLI changes, check the following:

- The command exists in `scripts/cli/oooconf-cli-spec.toml`.
- Unix and PowerShell dispatch both recognize the command or intentionally report it as unsupported.
- Help text exists for every new public command and important subcommand.
- Generated completions include the new command, options, and values.
- Tests include syntax coverage for touched shell files and completion/spec coverage for metadata changes.
- User-facing docs mention behavior that affects installation, setup, or day-to-day command usage.

## Validation Commands

Run the smallest relevant set for your change, and prefer the full set before merging larger CLI refactors:

```bash
bash -n scripts/setup/setup.sh
bash -n scripts/setup/ooodnakov.sh
bash -n scripts/setup/delete.sh
bash -n scripts/setup/minimal-setup.sh
bash -n scripts/setup/lib/*.sh
uv run python scripts/cli/generate_oooconf_completions.py
uv run pytest tests/test_recursive_completions.py tests/test_static_smoke.py tests/test_optional_deps.py
```

If `pwsh` is available, also run:

```powershell
./tests/test_powershell.ps1
```
