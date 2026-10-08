# Upstream Audit

This file records what was inspected and what was imported into this repo.

## Imported trees

Upstream reference trees:

- `third_party/upstream/ezsh` managed as a `git subtree`

Your current local WezTerm checkout was also preserved as:

- `third_party/local-snapshots/wezterm-current`

These are reference snapshots only. They are not the active config installed by `scripts/setup/setup.sh`.

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

Last checked (UTC): `2026-10-08T21:29:13+00:00`

| Dependency | Status | Current ref | Latest HEAD |
| --- | --- | --- | --- |
| `auto-uv-env` | `up-to-date` | `7bc8c17b4c7e0e34f170c1c940abfd184a3c15f0` | `7bc8c17b4c7e0e34f170c1c940abfd184a3c15f0` |
| `forgit` | `up-to-date` | `af6c459f3f2b2a72372ea6c2044b91e45c893573` | `af6c459f3f2b2a72372ea6c2044b91e45c893573` |
| `fzf-tab` | `up-to-date` | `24105b15714bfec37989ed5c5b6e60f572253019` | `24105b15714bfec37989ed5c5b6e60f572253019` |
| `k` | `up-to-date` | `e2bfbaf3b8ca92d6ffc4280211805ce4b8a8c19e` | `e2bfbaf3b8ca92d6ffc4280211805ce4b8a8c19e` |
| `marker` | `up-to-date` | `0f1fad95e9c3268c3077bc9d2c94ec6c58ab76a5` | `0f1fad95e9c3268c3077bc9d2c94ec6c58ab76a5` |
| `nvm` | `up-to-date` | `913b8cb6254aa0de7085d3e13c1b3b386845e570` | `913b8cb6254aa0de7085d3e13c1b3b386845e570` |
| `oh-my-zsh` | `up-to-date` | `60c9a7a839b790cd905d0fd4419435124fd1bdc0` | `60c9a7a839b790cd905d0fd4419435124fd1bdc0` |
| `powerlevel10k` | `up-to-date` | `d05a1b00f9a61f9578bf9dc19b8451942dde8734` | `d05a1b00f9a61f9578bf9dc19b8451942dde8734` |
| `s3cmd` | `up-to-date` | `97945760736bee4fd79eb3d357e48bd55d0ee60c` | `97945760736bee4fd79eb3d357e48bd55d0ee60c` |
| `todo-txt` | `up-to-date` | `4a140a370c952ff019a829ef677949849292012b` | `4a140a370c952ff019a829ef677949849292012b` |
| `you-should-use` | `up-to-date` | `5f3d129864ee4505043d88c3486224f1d75b692e` | `5f3d129864ee4505043d88c3486224f1d75b692e` |
| `zsh-autocomplete` | `up-to-date` | `77706d4cf24866bf62b865d97e9ef7d8bc38bd6e` | `77706d4cf24866bf62b865d97e9ef7d8bc38bd6e` |
| `zsh-autosuggestions` | `up-to-date` | `85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5` | `85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5` |
| `zsh-fzf-history-search` | `up-to-date` | `4b8826cfa64d1495237c1f6506f274e4cde1e0b3` | `4b8826cfa64d1495237c1f6506f274e4cde1e0b3` |
| `zsh-history-substring-search` | `up-to-date` | `a0bdb0d47dbaba31dba2db7af8c48a5d9c74049a` | `a0bdb0d47dbaba31dba2db7af8c48a5d9c74049a` |
| `zsh-syntax-highlighting` | `up-to-date` | `0bfcb582e71d3abe604ce67bc0fe5a21f377507e` | `0bfcb582e71d3abe604ce67bc0fe5a21f377507e` |
