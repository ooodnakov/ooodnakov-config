# Symlink Manifest

The repo uses a manifest-driven auto-discovery symlink system to link `home/` config into the user's profile.

## Architecture

```
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
scripts/setup/setup.sh link_file() / scripts/setup/setup.ps1 New-Symlink
      │
      ▼
  Symlinks created in $CONFIG_HOME, $HOME, etc.
```

## Files

- `scripts/links.toml` — canonical manifest of all managed symlinks
- `scripts/link_manager.py` — engine: manifest parsing, auto-discovery, platform filtering, local override merging
- `scripts/setup/setup.sh` / `scripts/setup/setup.ps1` — consumers that call `link_manager.py` to get the link list, then create symlinks
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

`autolink_dirs` lists directories scanned for auto-linking. Each subdirectory in those dirs becomes a symlink target unless it matches a configured `exclude` pattern or has an explicit `[[links]]` entry with a platform restriction. The current manifest does not define active excludes.

**What is auto-linked:**
- Every directory under `home/.config/`, `home/.local/`, and `home/.glzr/` is a candidate for linking, unless:
  - It matches an `exclude` pattern in `scripts/links.toml` (none are active today)
  - An explicit `[[links]]` entry exists for the same `key` and that entry has an `only` or `except` platform tag that excludes the current platform
- Auto-linked dirs always map to `{CONFIG_HOME}/<key>` — no manifest edit needed

Examples: `home/.config/wezterm/` → `~/.config/wezterm`, `home/.config/yazi/` → `~/.config/yazi`, `home/.config/nvim/` → `~/.config/nvim`

**What is auto-linked today:**
- The current manifest has no active discovery excludes, so `home/.config/ooodnakov` is also linked into `~/.config/ooodnakov`. Its ignored `local/` children hold machine-specific overrides while tracked examples stay reproducible.

**When to add an explicit `[[links]]` entry:**
- Files (not directories), e.g., `home/.zshrc` → `~/.zshrc`
- Platform-specific links (`only = "windows" | "linux" | "macos"`)
- Non-standard targets that don't follow the `{CONFIG_HOME}/<key>` convention

## Platform Tags

An entry can be restricted to a specific platform:

```toml
[[links]]
key = "noctalia"
source = "home/.config/noctalia"
target = "{CONFIG_HOME}/noctalia"
only = "linux"
```

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

```
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

Entries in `links.local.toml` take precedence over `links.toml` for matching keys. New `[links.<key>]` tables are also merged in. Platform filters (`only` / `except`) are currently supported in `scripts/links.toml`, not in local overrides.

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

### Dry-run

```bash
oooconf link --dry-run    # preview links without creating them
```

The underlying tool is `scripts/link_manager.py`, which can be run directly:

```bash
python scripts/link_manager.py --repo-root . --format text
# key|source|target lines, one per link
```

## Link Command Integration

| Command         | Role                                                            |
|-----------------|-----------------------------------------------------------------|
| `oooconf install` | Calls `oooconf link` after repo bootstrap and dependency setup |
| `oooconf doctor`  | Reads manifest via `link_manager.py` to check for missing links |
| `oooconf delete`  | Reads manifest to identify and remove all managed links          |
| `oooconf remove`  | Like delete, but skips backup restore                           |
| `oooconf link`    | Directly invokes the link creation logic (idempotent)          |
| `oooconf dry-run` | Shows what `oooconf install` would do without making changes    |
