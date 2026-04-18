# Managed Neovim + WezTerm CI Smoke Checks

This note proposes low-risk CI checks for managed terminal/editor config under:

- `home/.config/nvim/`
- `home/.config/wezterm/`

## What exists today (relevant context)

- Neovim config bootstraps `lazy.nvim` by cloning from GitHub if missing, then loads plugin spec/imports via LazyVim.
- WezTerm config is modular Lua, with dynamic event/module loading and optional local override from `~/.config/ooodnakov/local/wezterm.lua`.
- The current CI workflow does not run dedicated checks for `home/.config/nvim` or `home/.config/wezterm`.

## Definitely safe now (low flake risk)

These checks are deterministic and do not depend on GUI/session state.

### Neovim

1. **JSON validity checks**
   - Validate `home/.config/nvim/lazy-lock.json`
   - Validate `home/.config/nvim/lazyvim.json`
   - Command idea: `python3 -m json.tool <file> > /dev/null`
2. **Managed file presence checks**
   - Ensure at least these files exist:
     - `home/.config/nvim/init.lua`
     - `home/.config/nvim/lua/config/lazy.lua`

### WezTerm

1. **Managed entrypoint presence checks**
   - Ensure these files exist:
     - `home/.config/wezterm/wezterm.lua`
     - `home/.config/wezterm/config/init.lua`
2. **Reference asset presence checks (if configured as defaults)**
   - If a default backdrop list is expected, ensure files referenced by default config exist.

## Possible with extra setup (good value, but adds runtime/dependency complexity)

### Neovim

1. **Headless startup sanity**
   - Install Neovim in CI.
   - Run with isolated temp dirs to avoid mutating runner state:
     - `XDG_CONFIG_HOME=$PWD/home/.config`
     - temp `XDG_DATA_HOME`/`XDG_STATE_HOME`/`XDG_CACHE_HOME`
   - Example: `nvim --headless '+qall'`
   - Caveat: first run may clone `lazy.nvim`; plugin bootstrap/network outages can make this flaky.

2. **Pinned plugin lock consistency**
   - Run Lazy lock/check command headlessly and compare lockfile diff.
   - Useful, but more likely to break due to upstream/plugin API changes.

### WezTerm

1. **Config load check via WezTerm CLI**
   - Install WezTerm in CI.
   - Run a command that loads config without opening a full GUI session (platform-specific).
   - Caveat: runner platform differences and font availability can cause false negatives.

2. **Lua syntax check for all WezTerm Lua files**
   - Install Lua toolchain and run parse-only checks (`luac -p`) for `home/.config/wezterm/**/*.lua`.
   - Useful but requires consistent Lua version and package availability.

## Not worth automating (at least initially)

1. **Visual appearance checks** (themes, blur/background rendering, glyph aesthetics)
   - High maintenance, low signal for CI.
2. **Interactive keybinding ergonomics**
   - Better validated manually on real machines.
3. **Plugin functional behavior requiring external tools**
   - Example: lazygit plugin behavior depends on `lazygit`, git repo state, terminal semantics.

## Recommended minimal first implementation

Start with **static, deterministic checks only** in CI:

1. Validate Neovim JSON files (`lazy-lock.json`, `lazyvim.json`).
2. Verify core Neovim/WezTerm managed entrypoint files exist.

Why this first:

- Almost zero flake risk.
- No new CI dependencies.
- Catches accidental deletes/corruption quickly.
- Preserves reproducibility goals while keeping CI fast.

## Suggested second phase

After the first phase stabilizes, add **optional/non-blocking** headless startup checks behind a separate job or matrix entry, so regressions are visible without making every PR flaky.
