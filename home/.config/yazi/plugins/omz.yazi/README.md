# omz.yazi

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Show your [Oh My Zsh](https://ohmyz.sh) prompt inside [Yazi](https://yazi-rs.github.io).

`omz.yazi` replaces Yazi's default header with the prompt your shell actually
renders — theme colors, git decorations, current directory and all — and keeps
it in sync as you change directories or tabs. It is the Oh My Zsh counterpart of
[omp.yazi](https://github.com/saumyajyoti/omp.yazi) for oh-my-posh.

```
➜  src  main ✔
```

## Requirements

- Yazi `25.5.28` or newer
- zsh with Oh My Zsh installed and working interactively

## Installation

With Yazi's package manager:

```sh
ya pkg add ooodnakov/omz.yazi
```

Or manually:

```sh
git clone https://github.com/ooodnakov/omz.yazi.git ~/.config/yazi/plugins/omz.yazi
```

Then add this to `~/.config/yazi/init.lua`:

```lua
require("omz"):setup()
```

Restart Yazi.

## Configuration

```lua
require("omz"):setup {
	-- Interpreter used to render the prompt.
	-- Defaults to $SHELL when it is zsh, otherwise "zsh" from PATH.
	shell = "/bin/zsh",

	-- Per-request read timeout in milliseconds (default: 5000).
	-- The initial read after spawning the worker uses at least 10000 ms
	-- to give slower .zshrc startups time to finish.
	timeout = 5000,

	-- Case-insensitive substrings of precmd hook names to skip before
	-- rendering the prompt (default below).
	ignore_hooks = {
		"direnv",
		"auto_uv_env",
		"nvm",
		"fnm",
		"pyenv",
		"rbenv",
		"conda",
		"zoxide",
	},
}
```

### Guarding `.zshrc` with `OMZ_YAZI`

The worker exports `OMZ_YAZI=1` before sourcing `"${ZDOTDIR:-$HOME}/.zshrc"`.
You can wrap interactive, directory-mutating, or expensive setup in your `.zshrc`
so it is skipped inside Yazi's prompt worker while still loading Oh My Zsh and
your prompt theme:

```zsh
if [[ -z "${OMZ_YAZI:-}" ]]; then
  eval "$(zoxide init zsh --cmd z)"
fi
```

## How it works

Instead of spawning a new shell on every `cd`, `omz.yazi` runs **a single
persistent non-interactive `zsh` worker** for the Yazi session:

1. On startup, the worker duplicates protocol stdout onto a private file
   descriptor, redirects FD 1 and FD 2 to `/dev/null` so banners and notices
   from `.zshrc` never leak into the header, and sources
   `"${ZDOTDIR:-$HOME}/.zshrc"` once.
2. On each `cd` or `tab` event, Yazi coalesces rapid navigation and sends a
   tokenized request (`<seq> <hex-encoded-cwd>`) over stdin.
3. The worker decodes the path, switches directory with `builtin cd -q` (which
   skips `chpwd` hooks; `chpwd_functions` is also cleared as defense in depth),
   replays `precmd_functions` except hooks matching `ignore_hooks`, expands
   `${(%%)PROMPT}`, and writes a single-line tokenized response back to Yazi.
4. Lua verifies the per-spawn token and sequence number, strips non-SGR escape
   sequences and control bytes (preserving valid SGR colors), and updates the
   header if the active cwd still matches. Because the persistent worker runs
   via `ya.async` (outside Yazi's task manager), quitting Yazi is instant and
   terminates the worker cleanly. On older Yazi versions without `ya.async`, the
   plugin falls back cleanly to a hardened one-shot `entry` call.

The worker is deliberately non-interactive (`zsh -c` rather than `-i`). An
interactive zsh attaches to the terminal and probes it (device attributes,
DECRQM, mouse reporting); the terminal's answers are left queued in the tty
input buffer and later appear as garbage typed into the shell that launched
Yazi.

If the rc file leaves `$PROMPT` at zsh's builtin default, the plugin sources
`$ZSH/themes/${ZSH_THEME}.zsh-theme` once before processing requests, which
covers themes whose initializer could not run outside an interactive shell.

## Notes

- Only the first non-empty line of `$PROMPT` is shown. `$RPROMPT`, right-side
  decorations, and additional prompt lines do not fit the single-line header.
- The prompt is rendered for the directory Yazi is in, not for individual file
  operations performed inside Yazi.
- Rendering cost is one non-interactive zsh startup per Yazi session, followed
  by in-process `builtin cd -q` and prompt evaluation on each directory change.

## License

MIT — see [LICENSE](LICENSE).
