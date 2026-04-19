SAVEHIST=50000
HISTSIZE=50000

setopt hist_ignore_dups
setopt share_history
setopt auto_cd

alias l="ls -lAhrtF"
alias a="eza -lah --git --colour-scale all -g --smart-group --icons always"
alias aa="a -s modified -r"
alias e="exit"
alias ip="ip --color=auto"
alias myip="wget -qO- https://wtfismyip.com/text"
alias we="curl -Ss https://wttr.in/"

# Git aliases

case "${OOODNAKOV_FORGIT_ALIAS_MODE:-plain}" in
  forgit)
    ;;
  *)
    alias gs="git status"
    alias gc="git commit -v"
    alias gp="git push"
    alias gl="git pull"
    alias gd="git diff"
    alias gco="git checkout"
    alias glo="git log --oneline --graph --decorate --all"
    ;;
esac

# Dotfiles repo shortcut
alias cd-dotfiles="cd \${OOODNAKOV_CONFIG_HOME:-\$HOME/src/ooodnakov-config}"

cheat() {
  if [ -n "$2" ]; then
    curl "https://cheat.sh/$1/$2+$3+$4+$5+$6+$7+$8+$9+${10}"
  else
    curl "https://cheat.sh/$1"
  fi
}

ipgeo() {
  if [ -n "$1" ]; then
    curl "http://api.db-ip.com/v2/free/$1"
  else
    curl "http://api.db-ip.com/v2/free/$(myip)"
  fi
}
