# Troubleshooting

## Bootstrap fails on a fresh machine

1. **Verify prerequisites** — the bootstrap assumes core tools are present. See the [Prerequisites table in the README](../README.md#prerequisites) and ensure they are installed first.
   - **Linux (Debian/Ubuntu):** `sudo apt install -y git zsh`
   - **Windows:** install PowerShell 7+ and Git, then run from `pwsh`
2. **Clone first, run after** — avoid `curl | bash` pipelines. Clone the repo, inspect `scripts/setup.sh` (or `setup.ps1`), then run the entrypoint directly:
   ```bash
   git clone https://github.com/ooodnakov/ooodnakov-config.git "$HOME/src/ooodnakov-config"
   cd ooodnakov-config
   ./home/.config/ooodnakov/bin/oooconf install
   ```
3. **Check the log** — on first run, setup writes a log file under `~/.local/state/ooodnakov-config/logs/`. The latest run is symlinked as `setup-latest.log`.

## Missing tools after install

- **`oooconf` not found** — the setup script links it into `~/.local/bin/oooconf` (Unix) or `~/.local/bin/oooconf.ps1` / `oooconf.cmd` (Windows). Ensure that directory is on your `PATH`. New shell sessions pick it up automatically.
- **Optional dependency not installed** — run `oooconf deps` to see the interactive picker (requires `gum`). Without `gum`, a text prompt lists available keys you can type explicitly: `oooconf deps bat delta glow`.
- **A tool is listed as "install attempted" but not present** — the installer respects your consent prompt. Re-run `oooconf deps <key>` to retry, or install the tool manually.

## Stale or broken symlinks

Managed config is linked into `~/.config`. If something is misbehaving:

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

| File | Source | Overwritten by `oooconf secrets sync`? |
|------|--------|----------------------------------------|
| `~/.config/ooodnakov/local/env.zsh` | rendered from template | **No** — the `# --- LOCAL OVERRIDES START/END ---` block is preserved |
| `~/.config/ooodnakov/local/env.ps1` | rendered from template | **No** — same LOCAL OVERRIDES block |

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

| Symptom | Cause | Fix |
|---------|-------|-----|
| `BW_SESSION is not set` | Vault not unlocked in this shell | Run `oooconf secrets unlock` and eval/source the output |
| `Bitwarden CLI (bw) is not installed` | `bw` missing from PATH | Run `oooconf deps bw` or install manually |
| `failed to resolve KEY from Bitwarden` | Item ID invalid or vault locked | Verify the item ID in the template, then unlock |
| `Template not found` | Repo root resolved incorrectly | Pass `--repo-root /path/to/repo` explicitly |

Run `oooconf secrets doctor` for a full prerequisite check.
