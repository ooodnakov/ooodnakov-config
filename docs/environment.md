# Environment and local overrides

Portable tracked environment, machine-local overrides, and the tracked secret references that connect them.

## Tracked and local files

Portable tracked environment belongs in:

- `~/.config/ooodnakov/env/common.sh`
- `~/.config/ooodnakov/env/common.ps1`

Machine-specific or secret values belong in ignored files:

- `~/.config/ooodnakov/local/env.zsh`
- `~/.config/ooodnakov/local/env.ps1`
- `~/.ssh/config.local`

Tracked secret references belong in:

- `~/.config/ooodnakov/secrets/env.template`

## Shell integrations

SSH host aliases come from `~/.ssh/config`, every file it `Include`s (the tracked managed config is `home/.config/ooodnakov/ssh/config`), and `~/.ssh/config.local`. In both zsh and PowerShell, `z <host>` opens an SSH session when `<host>` is one of those aliases; any other argument keeps the zoxide directory jump. In zsh, `z -- <name>` forces the directory jump when an alias shadows a zoxide entry; in PowerShell, `zi` is the interactive directory picker for that case.

In both shells, `y` opens Yazi and changes the shell directory to the directory Yazi exits in. On Windows this also puts Git's `usr\bin` (for `sh`/`file`) on `PATH` and sets `YAZI_FILE_ONE` to Git's `file.exe`.

Tracked shared environment currently covers:

- editor and pager defaults
- `OOODNAKOV_CONFIG_HOME`
- `OOODNAKOV_SHARE_HOME`
- `OOODNAKOV_STATE_HOME`
- `OOODNAKOV_CACHE_HOME`
- `PNPM_HOME`
- `~/.local/bin`
- `~/.local/share/ooodnakov-config/bin`
- `~/.cargo/bin`
- optional `~/.local/bin/env` sourcing when present

Runtime shell artifacts are intentionally not tracked. Zsh history is written under `~/.local/state/ooodnakov-config/zsh/` and the completion dump under `~/.cache/ooodnakov-config/zsh/`.

## OMP links

OMP uses individual links from `home/.omp/`: `agent/config.yml`, `agent/themes/`,
`agent/skills/`, `agent/vibes/`, `extensions/rtk.ts`, and the MCP base file
`agent/mcp.json` (linked as `~/.omp/agent/.mcp.json`). `~/.omp` itself is a
normal local directory, and `~/.omp/agent/mcp.json` is machine-local, so
credentials, per-host MCP servers, databases, sessions, caches, and installed
plugins stay on the machine. OMP's settings file is `config.yml`; legacy
`settings.json` is not managed. See [OMP link migration](symlink-manifest.md#omp-file-and-content-links)
if your existing setup links the whole directory.

## Secrets sync

Additional local-only files you may create per machine:

- `~/.config/ooodnakov/local/env.zsh`
- `~/.config/ooodnakov/local/env.ps1`
- `~/.config/ooodnakov/local/wezterm.lua`
- `~/.config/ooodnakov/local/ghostty.conf`
- `~/.config/task/local/taskrc` for Taskwarrior sync credentials and private overrides

Examples live in [`home/.config/ooodnakov/local`](../home/.config/ooodnakov/local). Taskwarrior's local example lives in [`home/.config/task/local/taskrc.example`](../home/.config/task/local/taskrc.example).

To sync shared secrets across machines, keep Bitwarden references in the tracked template and render local plaintext files on each machine:

- `oooconf secrets login` (prompts for login type)
- `eval "$(oooconf secrets unlock --shell zsh)"`
- `oooconf secrets sync`
- `oooconf secrets sync --dry-run`
- `oooconf secrets doctor`

The generated files stay local and ignored:

- `~/.config/ooodnakov/local/env.zsh`
- `~/.config/ooodnakov/local/env.ps1`

The tracked template supports plain shared values and `bw://item/<item-id>/...` references. The current backend is `Bitwarden CLI` via `bw`, intended for a self-hosted Vaultwarden server such as `https://vaultwarden.ooodnakov.ru`.

Typical Unix flow:

```bash
oooconf install
oooconf secrets login
# or explicitly:
oooconf secrets login --method apikey
eval "$(oooconf secrets unlock --shell zsh)"
oooconf secrets sync
```

Typical PowerShell flow:

```powershell
oooconf install
oooconf secrets login
# or explicitly:
oooconf secrets login --method apikey
oooconf secrets unlock --shell pwsh | Invoke-Expression
oooconf secrets sync
```

For non-interactive or automated setups, you can skip the login/unlock step entirely by setting these environment variables before running `oooconf secrets sync`:

```bash
export BW_CLIENTID="user.xxx"
export BW_CLIENTSECRET="xxx"
export BW_PASSWORD="your-vault-password"
oooconf secrets sync
```

The sync will auto-unlock the vault, create missing local env files if needed, and render them without any manual interaction.

## Local overrides

Rendered files (`~/.config/ooodnakov/local/env.zsh`, `env.ps1`) contain a `# --- LOCAL OVERRIDES START/END ---` block. Lines inside this section survive every `oooconf secrets sync`, making it safe to add machine-specific env vars that are not tracked in the template. Anything outside the markers is overwritten on each sync.
