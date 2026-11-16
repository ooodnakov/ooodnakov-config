# Terminals

Managed terminal configuration: WezTerm workspace ergonomics and the optional Ghostty alternative.

## WezTerm Workspace Ergonomics

Set these environment variables to control WezTerm startup defaults without editing tracked config:

- `OOODNAKOV_WEZTERM_WORKSPACE`
- `OOODNAKOV_WEZTERM_CWD`

Example:

```bash
OOODNAKOV_WEZTERM_WORKSPACE=project-x OOODNAKOV_WEZTERM_CWD=$HOME/src/project-x wezterm
```

The managed WezTerm setup also loads a small, cross-platform plugin layer:

- `LEADER Space`: searchable command picker for managed keybindings
- `LEADER s` / `LEADER S`: smart workspace switching and previous-workspace toggle with zoxide-backed project discovery
- `LEADER r` / `LEADER R` / `LEADER D`: restore, save, and delete resurrected WezTerm workspace state
- `LEADER d` / `LEADER v` / `LEADER h`: quick domain attach, vertical split attach, and horizontal split attach
- `Alt+Shift+X` / `Ctrl+Shift+X` / `Alt+Shift+H` / `Ctrl+Shift+A`: AI Commander command generation, last-results recall, prompt history, and split-pane chat. The chat pane keeps per-pane message context for follow-up questions. It reads API keys from `ANTHROPIC_API_KEY` and `OPENAI_API_KEY`, chooses Anthropic when both are present, and uses `streamdown` for rich markdown rendering when available, falling back to `cat`; set `WEZTERM_AI_COMMANDER_RENDERER` to override the renderer command.
- pane navigation keeps the existing platform `SUPER+h/j/k/l` shortcuts but routes them through `smart-splits.nvim` so they can cross Neovim and WezTerm pane boundaries; `SUPER_REV+h/j/k/l` resizes panes the same way

The tab/status bar remains local to this repo rather than replacing it wholesale with an external tab plugin. It borrows the useful pieces from the retro/tabline ecosystem: workspace and leader/mode cells, zoom indicators, tab indexes, pane counts, host/current-directory context, battery, and clock.

## Ghostty

[Ghostty](https://ghostty.org) is supported as an optional alternative to WezTerm. Its managed config is [`home/.config/ghostty/config`](../home/.config/ghostty/config), linked to `~/.config/ghostty`, and mirrors the WezTerm setup:

- Noctalia palette from [`home/.config/ghostty/themes/Noctalia`](../home/.config/ghostty/themes/Noctalia), copied from the managed WezTerm color scheme
- `MesloLGSDZ Nerd Font Mono`, the same initial 125×30 grid, and matching cursor/padding behavior
- `ALT` as the SUPER modifier, with `ALT+h/j/k/l` pane navigation and `ALT+Ctrl+h/j/k/l` resizing, matching the WezTerm smart-splits bindings
- Shell integration with `ssh-env`/`ssh-terminfo`, so `z <host>`/`ssh-forward` sessions get `TERM` propagation and remote terminfo automatically; `ALT+Shift+Up/Down` jumps between prompts
- Quake-style quick terminal bound to ``Cmd+` `` (macOS global shortcut) with an ``Alt+` `` fallback in-window
- Command-finish notifications when a long command finishes while unfocused, and a Neovide-like cursor trail shader vendored at [`home/.config/ghostty/shaders/cursor_warp.glsl`](../home/.config/ghostty/shaders/cursor_warp.glsl)

`oooconf color` writes the selected theme to `~/.config/ooodnakov/local/ghostty.conf`, which the managed config loads through an optional `config-file` include. Put machine-local font size, opacity, or theme overrides in that file; [`home/.config/ooodnakov/local/ghostty.conf.example`](../home/.config/ooodnakov/local/ghostty.conf.example) shows the format.
