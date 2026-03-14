SAVEHIST=50000
HISTSIZE=50000

setopt hist_ignore_dups
setopt share_history
setopt auto_cd

alias l="ls --hyperlink=auto -lAhrtF"
alias a="eza -la --git --colour-scale all -g --smart-group --icons always"
alias aa="eza -la --git --colour-scale all -g --smart-group --icons always -s modified -r"
alias e="exit"
alias ip="ip --color=auto"
alias myip="wget -qO- https://wtfismyip.com/text"

cheat() {
  if [ -n "$2" ]; then
    curl "https://cheat.sh/$1/$2+$3+$4+$5+$6+$7+$8+$9+$10"
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

