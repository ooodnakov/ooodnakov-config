# Managed by ooodnakov-config.
# Git Bash (MSYS) entrypoint. When the managed zsh is installed (see
# `oooconf deps zsh` on Windows), replace this bash session with it so Git
# Bash windows run the same shell and tools as the Linux/macOS setup.
# Set OOODNAKOV_GITBASH_ZSH=0 to keep plain bash (also works per-invocation:
# `OOODNAKOV_GITBASH_ZSH=0 bash` for a raw bash subshell inside zsh).

# Non-interactive shells (git hooks, scripts) must stay bash.
case "$-" in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

if [ "${OOODNAKOV_GITBASH_ZSH:-1}" = "1" ] \
  && [ -n "${MSYSTEM:-}" ] \
  && command -v zsh >/dev/null 2>&1 \
  && [ -z "${ZSH_VERSION:-}" ]; then
  export SHELL="$(command -v zsh)"
  exec zsh -l
fi

# Fallback while zsh is not installed yet: give bash the shared portable
# environment (PATH helpers, editor, oooconf shortcuts) from common.sh.
OOODNAKOV_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/ooodnakov"
if [ -f "$OOODNAKOV_CONFIG_HOME/env/common.sh" ]; then
  . "$OOODNAKOV_CONFIG_HOME/env/common.sh"
fi
unset OOODNAKOV_CONFIG_HOME

[ ! -f "$HOME/.x-cmd.root/X" ] || . "$HOME/.x-cmd.root/X" # boot up x-cmd.
