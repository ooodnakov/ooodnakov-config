# Troubleshooting

## Bootstrap fails on a fresh machine

1. **Verify prerequisites** — the bootstrap assumes core tools are present. See the [Prerequisites table in the README](../README.md#prerequisites) and ensure they are installed first.
   - **Linux (Debian/Ubuntu):** `sudo apt install -y git zsh`
   - **Windows:** install PowerShell 7+ and Git, then run from `pwsh`
2. **Clone first, run after** — avoid `curl | bash` pipelines. Clone the repo, inspect `scripts/setup/setup.sh` / `scripts/setup/ooodnakov.sh` (or the PowerShell counterparts under `scripts/setup/`), then run the entrypoint directly:

   ```bash
   git clone https://github.com/ooodnakov/ooodnakov-config.git "$HOME/src/ooodnakov-config"
   cd ooodnakov-config
   ./home/.config/ooodnakov/bin/oooconf install
   ```

3. **Check the log** — on first run, setup writes a log file under `~/.local/state/ooodnakov-config/logs/`. The latest run is symlinked as `setup-latest.log`.

## Missing tools after install

- **`oooconf` (or `o`) not found** — setup links `oooconf` and alias `o` into `~/.local/bin` (Unix: `oooconf`, `o`; Windows: `oooconf.ps1`, `oooconf.cmd`, `o.ps1`, `o.cmd`). Ensure that directory is on your `PATH`. New shell sessions pick it up automatically.
- **Optional dependency not installed** — run `oooconf deps` to see the interactive picker (requires `gum`). Without `gum`, a text prompt lists available keys (from `optional-deps.toml`). Use `oooconf deps <key>` for specific tools.
- **A tool is listed as "install attempted" but not present** — the installer respects your consent prompt. Re-run `oooconf deps <key>` to retry, or install the tool manually.

## Default zsh prompt after install

If zsh opens with the default prompt, check the managed shell runtime:

```bash
oooconf doctor
oooconf install
```

`oooconf doctor` validates that the pinned Oh My Zsh, Powerlevel10k, and zsh plugin checkouts exist under `~/.local/share/ooodnakov-config/` and contain the files sourced by the managed profile. `oooconf install` retries failed git syncs, including an HTTP/1.1 fallback for transient GitHub TLS/HTTP failures.

To switch only zsh between Powerlevel10k and Oh My Posh, run `oooconf shell prompt p10k` or `oooconf shell prompt ohmyposh` and open a new zsh session. To reduce prompt verbosity across managed prompt engines, run `oooconf shell prompt-style concise`; restore the full layout with `oooconf shell prompt-style verbose`.

## Completion generation issues

- **Completion files look stale** — run `oooconf completions` (or `oooconf completions --dry-run` to preview). This regenerates local autogen zsh completions under `home/.config/ooodnakov/zsh/completions/autogen`, prunes stale autogen files, and refreshes tracked `oooconf` command completion scripts.
- **A specific tool completion is missing** — the autogen generator only emits entries for binaries currently on `PATH`; install the tool first, then re-run `oooconf completions`.
- **Manifest parse errors** — verify `scripts/generate/tool-completions.toml` keeps argv as arrays and maps each zsh entry to an `_name` output plus `provides` commands.

## Stale or broken symlinks

Managed config is linked into `~/.config`. If something is misbehaving:

Managed-link applies are journaled. To apply only the validated link transaction or
undo the latest eligible transaction:

```bash
oooconf apply
oooconf rollback --last
```

If apply is interrupted, `oooconf doctor` reports an incomplete transaction. Run
`oooconf rollback --last` to resume safe reverse-order cleanup. Rollback never
deletes a target that no longer matches the link recorded in the journal and never
overwrites an existing target while restoring a backup. If it reports manual
recovery, inspect the referenced journal under
`~/.local/state/ooodnakov-config/transactions/`, preserve the user-created target,
and restore the recorded `backup_path` manually if appropriate.

For automation, run `oooconf doctor --format json`. An interrupted transaction is
reported with stable check ID `transactions.incomplete`, error severity, and a
rollback remediation. `oooconf status --format json` reports the same state while
remaining suitable for inventory workflows that should not fail merely because a
health check is unhealthy.

## Transaction journal retention and cleanup

Transaction journals live under
`${XDG_STATE_HOME:-$HOME/.local/state}/ooodnakov-config/transactions/`. Backup paths
are recorded per operation and normally live under
`~/.local/state/ooodnakov-config/backups/` (or `OOODNAKOV_BACKUP_ROOT` when set).
There is intentionally no automatic retention window: journals are small, and
deleting one can make its backups impossible to associate with rollback.

Use this sequence for safe manual cleanup:

1. Run `oooconf doctor` and resolve every incomplete or `rollback_failed`
   transaction. Never routinely prune a journal in `applying`, `failed`, or
   `rollback_failed` state.
2. Open the journal and confirm its `status` is `complete` or `rolled_back`. For a
   completed transaction, explicitly decide that rollback is no longer required.
3. Review every non-null `backup_path`. Preserve anything that is still the only
   copy of user data. Delete only reviewed backup paths belonging to that journal.
4. Remove the journal only after its backups have been restored, archived, or
   deliberately removed. Never delete the whole backups or transactions directory
   based only on age.
5. Run `oooconf doctor` again. A subsequent idempotent `oooconf apply` should report
   no changes when managed links are healthy.

The active `apply.lock` directory is removed automatically. Do not manually remove
it merely because an apply is slow. After a confirmed process crash, preserve the
transaction directory and run `oooconf doctor`; a later apply can reclaim a stale
lock whose recorded process no longer exists.

## Snapshot import is rejected

Run `oooconf snapshot inspect FILE` before applying it. Imports are rejected when
the schema version is unsupported, fields or preferences are unknown, preference
values are outside the safe allowlist, or recorded capabilities no longer match the
named profile. Re-export the snapshot with the current checkout rather than editing
capability lists by hand.

```bash
# Check all managed links and key commands
oooconf doctor

# Remove all managed links without restoring backups
oooconf remove

# Remove managed links and restore the latest backups
oooconf delete

# Re-apply from the repo
oooconf install
```

Individual link issues show up in `oooconf doctor` as `[missing]` entries. The backup directory is `~/.local/state/ooodnakov-config/backups/`, with timestamped subfolders.

## Local override conflicts

Two places can introduce machine-specific env vars:

| File                                | Source                 | Overwritten by `oooconf secrets sync`?                                |
| ----------------------------------- | ---------------------- | --------------------------------------------------------------------- |
| `~/.config/ooodnakov/local/env.zsh` | rendered from template | **No** — the `# --- LOCAL OVERRIDES START/END ---` block is preserved |
| `~/.config/ooodnakov/local/env.ps1` | rendered from template | **No** — same LOCAL OVERRIDES block                                   |

**If your local value disappears after `oooconf secrets sync`:**
Make sure it sits between the `START` and `END` markers. Lines outside that block are overwritten on every sync.

**If sync fails with `BW_SESSION is not set`:**
You need an active Bitwarden session. Either:

```bash
eval "$(oooconf secrets unlock --shell zsh)"
```

Or set `BW_CLIENTID`, `BW_CLIENTSECRET`, and `BW_PASSWORD` in your local env — the sync will auto-unlock using those credentials.

**If a secret resolves to the wrong value:**
Check the template entry at `home/.config/ooodnakov/secrets/env.template`. The `bw://item/<id>/...` reference must match the correct Bitwarden item ID. Update the template and re-sync.

## Secrets sync errors

| Symptom                                | Cause                            | Fix                                                     |
| -------------------------------------- | -------------------------------- | ------------------------------------------------------- |
| `BW_SESSION is not set`                | Vault not unlocked in this shell | Run `oooconf secrets unlock` and eval/source the output |
| `Bitwarden CLI (bw) is not installed`  | `bw` missing from PATH           | Run `oooconf deps bw` or install manually               |
| `failed to resolve KEY from Bitwarden` | Item ID invalid or vault locked  | Verify the item ID in the template, then unlock         |
| `Template not found`                   | Repo root resolved incorrectly   | Pass `--repo-root /path/to/repo` explicitly             |

Run `oooconf secrets doctor` for a full prerequisite check.

## Cross-platform WM modifiers (Win/Cmd) for komorebi + OmniWM

### Windows (komorebi)

- `whkd` can bind `lwin` combos directly (for example `lwin + h/j/k/l`).
- If your keyboard/IME/tooling eats Win combinations, run komorebi with AutoHotkey instead of whkd:
  - `oooconf wm komorebi stop --bar` stops the full stack
  - `oooconf wm komorebi start --bar --ahk` starts with AutoHotkey instead of whkd
  - Or manually: `komorebic stop --whkd` / `komorebic start --ahk`
- AutoHotkey is optional; use it when Win hotkeys are unreliable on your machine.

### macOS (OmniWM)

- macOS has no AutoHotkey-equivalent requirement for OmniWM hotkeys.
- OmniWM captures shortcuts via macOS Accessibility permissions and its own hotkey system.
- For reliable multi-monitor/workspace behavior, turn **off** “Displays have separate Spaces” and log out/in after changing it.
- If you want hardware-level key remaps (outside OmniWM), use Karabiner-Elements as an optional separate layer.
