# Managed by ooodnakov-config.
# Login-shell entrypoint for Git Bash; mirrors the stock Git for Windows
# behavior of chaining into ~/.profile and ~/.bashrc (which execs the managed
# zsh when installed).
test -f "$HOME/.profile" && . "$HOME/.profile"
test -f "$HOME/.bashrc" && . "$HOME/.bashrc"
