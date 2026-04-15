# Upstream Audit

This file records what was inspected and what was imported into this repo.

## Imported trees

Upstream reference trees:

- `third_party/upstream/ezsh` managed as a `git subtree`

Your current local WezTerm checkout was also preserved as:

- `third_party/local-snapshots/wezterm-current`

These are reference snapshots only. They are not the active config installed by `scripts/setup.sh`.

## Findings

### KevinSilvester/wezterm-config

Local checkout:

- path: `/mnt/c/Users/coolk/.config/wezterm`
- upstream remote: `https://github.com/KevinSilvester/wezterm-config.git`
- upstream HEAD inspected: `a4356e1b48fe0cec7b50d330afd309eab66e04cc`
- local checked-out commit: `25504d5`

Observed divergence:

- nearly every Lua file differs from upstream
- part of the churn appears to be line-ending noise
- real user-facing differences exist in `config/domains.lua`, `config/launch.lua`, `config/fonts.lua`, `config/general.lua`, and status/tab UI modules

Interpretation:

- the local WezTerm tree is effectively a personal fork
- keeping a reference copy in `third_party/local-snapshots/wezterm-current` is justified
- the vendored upstream snapshot was later removed to keep repo size down; upstream provenance remains documented here
- the active tracked config in `home/.config/wezterm` should stay smaller and more reproducible than this fork

### jotyGill/ezsh

Installed ezsh-like layout was compared against upstream:

- upstream HEAD inspected: `dc679082f61abd760c2e65cae32e152204a673e2`
- local installed base file: `/home/user/.config/ezsh/ezshrc.zsh`

Observed local changes:

- extra plugins enabled locally: `web-search`, `httpie`, `git`, `python`, `docker`, `lol`
- local setup enables `zsh-nvm`
- local `~/.zshrc` had machine-specific exports and a secret token appended after the generated ezsh content
- local `p10k.zsh` is substantially customized relative to upstream

Interpretation:

- ezsh was useful as a layout idea, but the tracked repo should not depend on its generated structure
- the new repo keeps a modular zsh layout while managing plugins directly
- the upstream ezsh tree is retained as a subtree so it can be refreshed from upstream without manual recopying

### Remote host: orange

Inspected host:

- `rem@192.168.1.201`

Portable ideas extracted:

- plugins: `evalcache git git-extras debian tmux screen history extract colorize web-search docker zsh-autosuggestions zsh-syntax-highlighting zsh-autocomplete`
- `menuselect` Enter bindings for `zsh-autocomplete`
- `PNPM_HOME` in `~/.local/share/pnpm`
- Neovim added from `/opt/nvim-linux-arm64/bin`

Imported into active config:

- `zsh-autocomplete`
- `fzf-tab`
- `menuselect` Enter bindings
- `PNPM_HOME` support
- plugin set expanded toward the machine setups with `git-extras`, `history`, `tmux`, `screen`, `colorize`, and `debian`

Left out on purpose:

- host-specific paths
- secrets
- packages not guaranteed to exist on every machine

### Remote host: site

Inspected host:

- `root@45.12.138.163`

Portable ideas extracted:

- plugins: `git zsh-autosuggestions zsh-syntax-highlighting zsh-autocomplete docker z`
- sourcing `~/.local/bin/env` when present
- `PNPM_HOME` in `~/.local/share/pnpm`
- `~/.cargo/bin` on `PATH`

Imported into active config:

- optional sourcing of `~/.local/bin/env`
- `~/.cargo/bin` path
- `PNPM_HOME` support

Left out on purpose:

- cloud project exports
- tokens and API keys
- root-specific paths such as `/root/.opencode/bin`

## Security note

Remote shell files contained secrets. Those were inspected for migration risk but were intentionally not copied into this repo.

## Automated Pin Checks

Last checked (UTC): `2026-04-15T08:31:07+00:00`

| Dependency | Status | Current ref | Latest HEAD |
| --- | --- | --- | --- |
| `auto_uv_env` | `up-to-date` | `76589a0fe4a3eaba9817b7195b9fc05ef4139289` | `76589a0fe4a3eaba9817b7195b9fc05ef4139289` |
| `forgit` | `up-to-date` | `9280ebbb01cd37b26380a16adb15d08354a9f5ee` | `9280ebbb01cd37b26380a16adb15d08354a9f5ee` |
| `fzf_tab` | `up-to-date` | `0983009f8666f11e91a2ee1f88cfdb748d14f656` | `0983009f8666f11e91a2ee1f88cfdb748d14f656` |
| `k` | `up-to-date` | `e2bfbaf3b8ca92d6ffc4280211805ce4b8a8c19e` | `e2bfbaf3b8ca92d6ffc4280211805ce4b8a8c19e` |
| `marker` | `up-to-date` | `c123085891228e51cfa58d555708bad67ed98f02` | `c123085891228e51cfa58d555708bad67ed98f02` |
| `nvm` | `up-to-date` | `d200a215594bdda07e130117c9d392fff29cba84` | `d200a215594bdda07e130117c9d392fff29cba84` |
| `oh_my_zsh` | `up-to-date` | `061f773dd356df52a8bccd5e73377c012f97ef14` | `061f773dd356df52a8bccd5e73377c012f97ef14` |
| `p10k` | `up-to-date` | `604f19a9eaa18e76db2e60b8d446d5f879065f90` | `604f19a9eaa18e76db2e60b8d446d5f879065f90` |
| `todo` | `up-to-date` | `b20f9b45e210129ef020d3ba212d86b9ba9cf70d` | `b20f9b45e210129ef020d3ba212d86b9ba9cf70d` |
| `you_should_use` | `up-to-date` | `ff371d6a11b653e1fa8dda4e61c896c78de26bfa` | `ff371d6a11b653e1fa8dda4e61c896c78de26bfa` |
| `zsh_autocomplete` | `up-to-date` | `20f6c34f20270084b21211428afb6d2534aae8e9` | `20f6c34f20270084b21211428afb6d2534aae8e9` |
| `zsh_autosuggestions` | `up-to-date` | `85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5` | `85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5` |
| `zsh_highlighting` | `up-to-date` | `1d85c692615a25fe2293bdd44b34c217d5d2bf04` | `1d85c692615a25fe2293bdd44b34c217d5d2bf04` |
| `zsh_history` | `up-to-date` | `14c8d2e0ffaee98f2df9850b19944f32546fdea5` | `14c8d2e0ffaee98f2df9850b19944f32546fdea5` |
