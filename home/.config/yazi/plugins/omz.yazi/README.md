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
}
```

## How it works

On startup and on every `cd`/`tab` event the plugin renders the prompt in a
throwaway **non-interactive** zsh running in the directory Yazi is in. The shell
sources your rc file, replays the registered `precmd` hooks so framework prompts
(Powerlevel10k, theme initializers) materialize the way they do before a redraw,
and then prints the fully expanded `$PROMPT`:

```sh
zsh -c 'source "${ZDOTDIR:-$HOME}/.zshrc"; for hook in ${precmd_functions[@]}; do $hook; done; print -r -- ${(%%)PROMPT}'
```

The shell is deliberately not `-i`. An interactive zsh attaches to the terminal
and probes it (device attributes, DECRQM, mouse reporting); the terminal's
answers are left queued in the tty input buffer and later appear as garbage
typed into the shell that launched Yazi. A non-interactive shell never touches
the terminal.

Only the text between the plugin's private markers is used, so banners printed
while sourcing the rc file (version managers, framework notices) never leak into
the header. The command runs as a Yazi job, so a slow shell startup never blocks
the file manager; the header updates as soon as the prompt is ready.

If the rc file leaves `$PROMPT` at zsh's builtin default, the plugin sources
`$ZSH/themes/${ZSH_THEME}.zsh-theme` once before printing, which covers themes
whose initializer could not run outside an interactive shell.

## Notes

- Only the first non-empty line of `$PROMPT` is shown. `$RPROMPT`, right-side
  decorations, and additional prompt lines do not fit the single-line header.
- The prompt is rendered for the directory Yazi is in, not for individual file
  operations performed inside Yazi.
- Rendering cost is one interactive zsh startup per directory change, run
  asynchronously.

## License

MIT — see [LICENSE](LICENSE).
