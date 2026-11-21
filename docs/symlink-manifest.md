# Symlink Manifest

The repo uses a manifest-driven auto-discovery symlink system to link `home/` config into the user's profile.

## Architecture

```text
scripts/links.toml
      │
      ▼
scripts/link_manager.py
      │
      ├── read_links_manifest()     → explicit [[links]] entries (files, platform-tagged, non-standard targets)
      ├── discover_links()         → auto-discovered dirs from autolink_dirs (home/.config/*, home/.local/*, home/.glzr/*)
      └── merge_with_local()       → merges home/.config/ooodnakov/local/links.local.toml target/source overrides
      │
      ▼
get_all_links()  →  [(source, target, key), ...]
      │
      ▼
scripts/cli/operation_plan.py  →  validate and emit planned link operations
      │
      ▼
scripts/setup/setup.sh link_file() / scripts/setup/setup.ps1 New-Symlink
      │
      ▼
  Symlinks created in $CONFIG_HOME, $HOME, etc.
```

## Files

- `scripts/links.toml` — canonical manifest of all managed symlinks
- `scripts/link_manager.py` — engine: manifest parsing, auto-discovery, platform filtering, local override merging
- `scripts/cli/operation_plan.py` — safety and planning layer consumed by both setup implementations
- `scripts/setup/setup.sh` / `scripts/setup/setup.ps1` — consumers that apply the planner's validated link stream
- `home/.config/ooodnakov/local/links.local.toml` — machine-local override file (not in git)

## Manifest Format

`scripts/links.toml` defines two sections:

```toml
[discovery]
autolink_dirs = ["home/.config", "home/.local", "home/.glzr"]
[[links]]
key = "zshrc"
source = "home/.zshrc"
target = "{HOME}/.zshrc"
```

### Discovery Section

`autolink_dirs` lists directories scanned for auto-linking. Each subdirectory in those dirs becomes a symlink target unless it matches a configured `exclude` pattern or has an explicit `[[links]]` entry with a platform restriction. Active excludes: `home/.config/noctty` (Windows-only, linked explicitly because it needs the extra `%LOCALAPPDATA%` target) and `home/.config/herdr-app` (Herdr writes runtime state into it; only the files this repo owns are linked).

**What is auto-linked:**

- Every directory under `home/.config/`, `home/.local/`, and `home/.glzr/` is a candidate for linking, unless:
  - It matches an `exclude` pattern in `scripts/links.toml` (e.g. `home/.config/herdr-app`)
  - An explicit `[[links]]` entry exists for the same `key` and that entry has an `only` or `except` platform tag that excludes the current platform
- Auto-linked dirs always map to `{CONFIG_HOME}/<key>` — no manifest edit needed

Examples: `home/.config/wezterm/` → `~/.config/wezterm`, `home/.config/yazi/` → `~/.config/yazi`, `home/.config/nvim/` → `~/.config/nvim`

**What is auto-linked today:**

- `home/.config/ooodnakov` is linked into `~/.config/ooodnakov`. Its ignored `local/` children hold machine-specific overrides while tracked examples stay reproducible.
- Everything under `home/.config/`, `home/.local/`, and `home/.glzr/` except the excludes above; see the Herdr App section for the one partial tree.

**When to add an explicit `[[links]]` entry:**

- Files (not directories), e.g., `home/.zshrc` → `~/.zshrc` or managed Taskwarrior `home/.config/task/taskrc` → `~/.taskrc`
- Platform-specific links (`only = "windows" | "linux" | "macos"`)
- Non-standard targets that don't follow the `{CONFIG_HOME}/<key>` convention

## OMP File and Content Links

OMP deliberately uses explicit child links instead of linking `~/.omp` or
`~/.omp/agent` wholesale:

| Key | Managed source | Target |
|-----|----------------|--------|
| `omp-config` | `home/.omp/agent/config.yml` | `~/.omp/agent/config.yml` |
| `omp-themes` | `home/.omp/agent/themes/` | `~/.omp/agent/themes` |
| `omp-vibes` | `home/.omp/agent/vibes/` | `~/.omp/agent/vibes` |
| `omp-rtk` | `home/.omp/extensions/rtk.ts` | `~/.omp/extensions/rtk.ts` |
| `omp-mcp` | `home/.omp/agent/mcp.json` | `~/.omp/agent/.mcp.json` |

The current OMP settings file is `agent/config.yml`; the legacy
`agent/settings.json` is not linked. OMP-only skills live in
`home/.omp/agent/skills/`. Skills shared by every agent (omp, Claude Code,
Codex) live once under `home/.config/ooodnakov/agents/skills/` and are **not**
in this manifest: `oooconf agents skills sync` reads the `installer = "local"`
specs in `common-data.json` and symlinks each skill folder into the agent's own
skills directory (`~/.omp/agent/skills`, `~/.claude/skills`,
`~/.codex/skills`). `--check` reports them as up to date, `--dry-run` prints the
links, and an existing non-link path is left alone. Add custom themes and vibes
to the corresponding managed directories.

MCP configuration is layered so every machine can keep its own servers:

- `~/.omp/agent/.mcp.json` is the tracked base, linked from the repository.
- `~/.omp/agent/mcp.json` is a real machine-local file, never linked.

OMP reads the primary `mcp.json` before `.mcp.json`, so a local entry can add a
server or shadow a shared one by name. Everything that writes MCP config
(`/mcp add`, `/mcp enable`, `oooconf agents sync`) targets the local file, which
keeps API keys, machine paths, and one-off servers out of git.

`oooconf link` creates the local file when it is missing and seeds it with the
base `enabledServers`/`disabledServers` overrides. If an older release linked
`mcp.json` itself into the repository, `oooconf link` converts that link into a
real file holding only the entries that differ from the committed base.

Everything else stays local, including databases and their WAL files,
credentials, model settings, sessions, blobs, caches, installed plugins, logs,
and daemon sockets/PIDs. `.gitignore` allows only the managed paths under
`home/.omp/`.

**Migrating an older whole-directory link:** close OMP and its daemons first.
Before running `oooconf link`, preserve the old `~/.omp` symlink, then move the
former repository-root `.omp` directory into its place as a real `~/.omp`
directory. For example, on Unix, after verifying `~/.omp` points to this repo's
`.omp` and that the backup name does not exist:

```bash
mv "$HOME/.omp" "$HOME/.omp.whole-directory-link.backup"
mv /path/to/ooodnakov-config/.omp "$HOME/.omp"
oooconf link
```

The new sources are under `home/.omp/`, so moving the former root `.omp` preserves
local state without moving the managed sources. The link transaction backs up
existing config/content at the individual target paths. Keep those backups if
they contain local customizations. On Windows, perform the same moves with
PowerShell `Move-Item`. Do not run the child-link plan while the old whole-root
symlink remains: its parent resolution would keep runtime state inside the repo,
so `oooconf plan`, `apply`, and `link` reject any target that resolves back into
the repository instead of mutating tracked files. If an older release already
turned a tracked source into a self-referential link, `oooconf rollback --last`
removes the loop and restores the backed-up file.
Update any machine-local overrides or custom profiles that selected the old
`omp` key to use the individual keys above. Fresh setups need no migration.

## Herdr App File Links

`~/.config/herdr-app` is Herdr's whole interface, and Herdr rewrites parts of it
on every start (`frame/`, `icons/`, `layouts/.state/`, `view.json`, sockets), so
the folder is in the discovery `exclude` list and only the files this repo owns
are linked:

| Key | Managed source | Target |
|-----|----------------|--------|
| `herdr-settings` | `home/.config/herdr-app/settings.json` | `~/.config/herdr-app/settings.json` |
| `herdr-keys` | `home/.config/herdr-app/keys.json` | `~/.config/herdr-app/keys.json` |
| `herdr-theme-gruvbox-dark` | `home/.config/herdr-app/themes/gruvbox-dark.json` | `~/.config/herdr-app/themes/gruvbox-dark.json` |
| `herdr-theme-gruvbox-light` | `home/.config/herdr-app/themes/gruvbox-light.json` | `~/.config/herdr-app/themes/gruvbox-light.json` |
| `herdr-mod-oo-tasks` | `home/.config/herdr-app/mods/oo-tasks/` | `~/.config/herdr-app/mods/oo-tasks` |
| `herdr-mod-oo-artifacts` | `home/.config/herdr-app/mods/oo-artifacts/` | `~/.config/herdr-app/mods/oo-artifacts` |
| `herdr-mod-oo-agent-head` | `home/.config/herdr-app/mods/oo-agent-head/` | `~/.config/herdr-app/mods/oo-agent-head` |
| `herdr-mod-tabs-panels` | `home/.config/herdr-app/mods/tabs-panels/` | `~/.config/herdr-app/mods/tabs-panels` |
| `herdr-layout-tasks` | `home/.config/herdr-app/layouts/tasks.json` | `~/.config/herdr-app/layouts/tasks.json` |
| `herdr-layout-tasks-preview` | `home/.config/herdr-app/layouts/tasks.svg` | `~/.config/herdr-app/layouts/tasks.svg` |
| `herdr-layout-main-panels` | `home/.config/herdr-app/layouts/main-panels.json` | `~/.config/herdr-app/layouts/main-panels.json` |
| `herdr-layout-main-panels-preview` | `home/.config/herdr-app/layouts/main-panels.svg` | `~/.config/herdr-app/layouts/main-panels.svg` |
| `herdr-task` | `home/.config/ooodnakov/bin/herdr-task` | `~/.local/bin/herdr-task` |
| `herdr-artifact` | `home/.config/ooodnakov/bin/herdr-artifact` | `~/.local/bin/herdr-artifact` |

Any `themes/<name>.json` Herdr finds becomes selectable in Settings → Look;
`settings.json`'s `"theme": {"light": "<name>", "dark": "<name>"}` is the default
for layouts that set none (Herdr's `main` layout does), and the theme picker
stores a per-layout choice in `layouts/.state/`, which is app-written and never
tracked. Add another managed theme as a new file plus a `[[links]]` entry.

`keys.json` is the live key map copied into the repo, plus two global bindings:
`alt-shift-t` sends `tabs-panels.tasks` and `alt-shift-a` sends
`tabs-panels.artifacts`. One key runs one command and opening a panel takes two
(`layout.select {stack: "panel-body", child}` then `layout.show {id: "panel"}`),
so the tab-bar mod's `nextCommand()` loop does both, exactly like its Tasks and
Artifacts buttons. The keys work in a layout that shows that bar
(`main-panels`); Herdr's own `main` has no `panel-body`, so they do nothing
there. Herdr keeps any edited keys file as yours and never merges later shipped
defaults, so add new defaults by hand. On macOS these two chords are
Option+Shift+T/A, which type a character in apps that do not take them; rebind
them in `keys.json` if that matters.

The `tasks` layout places the two repo-owned mods side by side; `main-panels` is a
clone of Herdr's `main` whose panel stack (`panel-body`) adds them after Files and
Changes, plus an `oo-agent` column: the `oo-agent-head` header (the selected
task's title and a `← Tasks` chip, fed by shared `oo-tasks.selected`) above a
`{ "agent": "focused" }` block that shows the agent chosen with `agent.focus`, so
a task's terminal can fill the panel. Reaching the
panels from the top-right tab bar needs buttons there, so
`tabs-panels` is a clone of the shipped `tabs` mod with two `panelButton` calls
added (Tasks, Artifacts) and the `workspace.panels` merge in its `init` that keeps
the tab bar's per-space panel restore aware of the new ids. The panels read the
per-folder lists that `herdr-task` and `herdr-artifact` write under the root
recorded in `~/.config/ooodnakov/herdr-data` (on the space's own machine, over
herdr-core for remote spaces), falling back to `~/.local/share/ooodnakov/herdr`.
A task may carry an agent: `herdr-task spawn` starts it with
`hc run --label herdr.task=<slug>#<id>` and stores `terminal` on the task.
`--keep-open` runs the program through `sh -c '<command>; exec "${SHELL:-sh}"'`
so the terminal survives the program exiting, and `--worktree [PATH]` first makes
`herdr/<id>` in its own worktree (default `<repo>-wt/<id>` beside the repo) —
through worktrunk (`git-wt` on Windows, `wt` elsewhere) when installed, else
`git worktree add -b` — spawns there and records `branch`, `worktree` and
`worktree_tool` on the task; `--dry-run` prints those commands without running
them. The
mod matches that label (or the stored address) in `terminals()`, counts the
sub-agents whose `parent` is that terminal, and its detail shows the terminal in
the panel (`agent.focus`), keeps it as a pane (`terminal.keep`), peeks when it
reports no status (`terminal.peek`), or stops it (`terminal.kill`). The list
header adds a task (`herdr-task add` remotely), the detail rewrites its status
(`herdr-task set`) and deletes it after asking (`herdr-task rm`): each local
write is a compare-and-set rewrite of the same list file, and a folder the index
has no slug for yet is named in `index.json` first; on a remote machine the
command does the write under its own lock through `hc exec`. The Artifacts detail
deletes an artifact the same way (`herdr-artifact rm` remotely) and copies its
latest version's path. The detail also reads the agent's screen (`hc read`, last
120 lines) into an OUTPUT block, live or after it ended. Those two
commands import `home/.config/ooodnakov/bin/_herdr_store.py` by resolving their
own symlink, so only the commands themselves are linked, not the module.

## Platform Tags

An entry can be restricted to a specific platform:

```toml
[[links]]
key = "noctalia"
source = "home/.config/noctalia"
target = "{CONFIG_HOME}/noctalia"
only = "linux"
```text

Valid values for `only`: `windows`, `linux`, `macos`.

An entry can also be excluded from a platform using `except`:

```toml
[[links]]
key = "noctalia"
source = "home/.config/noctalia"
target = "{CONFIG_HOME}/noctalia"
except = "windows"  # linked everywhere except Windows
```

If both `only` and `except` are absent, the entry is linked on all platforms.

## Path Templates

Target paths support four placeholders:

| Template         | Unix                          | Windows                       |
|------------------|-------------------------------|-------------------------------|
| `{HOME}`         | `~`                           | `C:\Users\<user>`             |
| `{CONFIG_HOME}`  | `~/.config` (or `$XDG_CONFIG_HOME`) | `C:\Users\<user>\.config`     |
| `{DATA_HOME}`    | `~/.local/share`              | `C:\Users\<user>\.local\share` |
| `{LOCAL_BIN}`    | `~/.local/bin`                | `C:\Users\<user>\.local\bin`  |

The `{CONFIG_HOME}` expansion honors `XDG_CONFIG_HOME` on Unix if set.

## Local Overrides

Machine-specific symlink targets are managed in:

```text
home/.config/ooodnakov/local/links.local.toml
```

This file is ignored when named exactly `links.local.toml`. Copy `links.local.toml.example` as a starting point. Local override `source` and `target` values support the same `{HOME}`-style path templates as `scripts/links.toml`, so overrides can stay portable across machines and user accounts.

Format:

```toml
# =============================================================================
# OVERRIDE A TARGET
# Change where an existing link points to on this machine
# =============================================================================

# Override wezterm target to a custom location on this machine
[links.wezterm]
target = "{HOME}/.config/wezterm-work"

# Override the oooconf-bin to point to a different location
[links.oooconf-bin]
target = "{DATA_HOME}/custom-bin/oooconf"

# =============================================================================
# ADD A NEW LINK
# One not in the manifest - specify both source and target
# =============================================================================

[links.my-secret-config]
source = "{HOME}/.config/my-secret"
target = "{CONFIG_HOME}/my-secret"

# =============================================================================
# {LOCAL_BIN} OVERRIDE
# Put a binary somewhere other than ~/.local/bin
# =============================================================================

# Override o-bin to live in a custom bin directory
[links.o-bin]
target = "/home/alice/.local/share/custom-bin/o"
```

Entries in `links.local.toml` take precedence over `links.toml` for matching keys. New `[links.<key>]` tables are also merged in, and optional `only` / `except` platform tags are supported.

## Private overlay repository

An optional private overlay repository can supply personal hostnames, SSH configs, domains, or overrides without storing them in this public repository.

### Discovery order

`scripts/lib/private_overlay.py` (`resolve_private_overlay_root`) checks in order:

1. `OOOCONF_PRIVATE_DIR` environment variable (`""` or `none`, case-insensitive, explicitly disables overlay discovery).
2. Pointer files (first non-empty, non-`#`-comment line, with `~` expanded and relative paths resolved against the repo root):
   - `home/.config/ooodnakov/local/private-repo`
   - `~/.config/ooodnakov/local/private-repo`
3. Sibling directory `../ooodnakov-config-private` next to the public repository root.

### Overlay manifest and targets

When resolved, `<private_root>/links.local.toml` is merged before `home/.config/ooodnakov/local/links.local.toml`, so precedence is:

```text
scripts/links.toml + auto-discovery < <private_root>/links.local.toml < home/.config/ooodnakov/local/links.local.toml
```

Entries in `links.local.toml` can use `{PRIVATE_ROOT}` in `source` or `target` templates alongside `{HOME}`, `{CONFIG_HOME}`, `{DATA_HOME}`, and `{LOCAL_BIN}`.

Overlay targets must live outside the public repository tree (for example `{HOME}/.ssh/config.local`, `{DATA_HOME}/ooodnakov-config/...`, or `{HOME}/.omp/agent/config.yml`). Never target `{CONFIG_HOME}/ooodnakov/local/...`: `home/.config/ooodnakov` is itself symlinked into `{CONFIG_HOME}/ooodnakov`, so targeting inside it would write into the public checkout and is rejected by `scripts/cli/operation_plan.py`.

During `oooconf update`, if a private overlay git checkout has a configured upstream tracking branch, setup pulls it with `--ff-only` (warning only if unreachable).

## How to Add a New Config Folder

1. Create the directory inside `home/.config/` (or `home/.local/` or `home/.glzr/` as appropriate)

2. It auto-links on next run — no manifest edit needed

3. Only add an explicit `[[links]]` entry for:
   - Files (not directories)
   - Platform restrictions (`only` / `except`)
   - Non-standard targets that don't follow `{CONFIG_HOME}/<key>`

## `oooconf link` Command

`oooconf link` creates or updates all managed symlinks by reading the manifest. It is called internally by:

- `oooconf install` — after setting up the repo, runs `oooconf link` to apply all symlinks
- `oooconf doctor` — reads the manifest to validate that expected links exist
- `oooconf delete` / `oooconf remove` — reads the manifest to know which links to remove

Unix and PowerShell setup both consume the validated link operations from
`scripts/cli/operation_plan.py` through `scripts/cli/transaction_apply.py`. The
planner uses `link_manager.py` for manifest discovery, then verifies source
existence, unique targets, and target containment before the transaction executor
creates backups or links.

```bash
oooconf plan --scope links
oooconf plan --scope links --format json
oooconf apply
oooconf rollback --last
```

### Dry-run

```bash
oooconf link --dry-run    # preview links without creating them
```

The underlying manifest reader is `scripts/link_manager.py`, which can still be run
directly for low-level inspection:

```bash
python scripts/link_manager.py --repo-root . --format text
# key|source|target lines, one per link
```

## Link Command Integration

| Command         | Role                                                            |
|-----------------|-----------------------------------------------------------------|
| `oooconf install` | Applies the shared validated link plan as a transaction          |
| `oooconf doctor`  | Reads manifest via `link_manager.py` to check for missing links |
| `oooconf delete`  | Reads manifest to identify and remove all managed links          |
| `oooconf remove`  | Like delete, but skips backup restore                           |
| `oooconf link`    | Directly invokes the link creation logic (idempotent)          |
| `oooconf plan`    | Emits a side-effect-free text or versioned JSON operation plan |
| `oooconf apply`   | Journals and transactionally applies the managed link plan     |
| `oooconf rollback` | Safely reverses the latest eligible managed-link transaction |
| `oooconf dry-run` | Compatibility alias for `oooconf plan`                         |
