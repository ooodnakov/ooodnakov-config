# Upstream Audit

This file records what was inspected and what was imported into this repo.

## Imported trees

Clean upstream snapshots were copied into:

- `third_party/upstream/wezterm-config`
- `third_party/upstream/ezsh`

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
- `menuselect` Enter bindings
- `PNPM_HOME` support

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
