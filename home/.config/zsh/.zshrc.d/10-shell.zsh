SAVEHIST=50000
HISTSIZE=50000

setopt hist_ignore_dups
setopt share_history
setopt auto_cd

alias l="ls -lAhrtF"
alias a="eza -lah --git --color-scale all -g --smart-group --icons always --hyperlink"
alias aa="a -s modified -r"
alias e="exit"
alias ip="ip --color=auto"
alias myip="wget -qO- https://wtfismyip.com/text"
alias we="curl -Ss https://wttr.in/"
alias ff='fastfetch'
alias du='dua i'
alias n='nvim'
alias tt='taskwarrior-tui'

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

# Advanced SSH Port Forwarding
# Usage: ssh-forward [-r] <host> <local-port> [remote-port]
ssh-forward() {
    local reverse=0
    # Check for reverse flag
    if [[ "$1" == "-r" ]]; then
        reverse=1
        shift
    fi

    if [[ -z "$1" || -z "$2" ]]; then
        echo "Usage:"
        echo "  Local (default):  ssh-forward <host> <local-port> [remote-port]"
        echo "  Reverse:          ssh-forward -r <host> <remote-port> [local-port]"
        return 1
    fi

    local host="$1"
    local port1="$2"
    local port2="${3:-$port1}"

    # Generate a unique control socket path for this specific connection
    local socket="/tmp/ssh-fwd-${host}-${port1}.sock"

    if [[ $reverse -eq 1 ]]; then
        echo "Forwarding remote Port ${port1} to local http://localhost:${port2} on ${host}..."
        # -M and -S set up a control socket so we can close it easily later
        ssh -f -N -M -S "$socket" -R "${port1}:localhost:${port2}" "$host"
    else
        echo "Forwarding local localhost:${port1} to remote Port ${port2} on ${host}..."
        ssh -f -N -M -S "$socket" -L "${port1}:localhost:${port2}" "$host"
    fi

    if [ $? -eq 0 ]; then
        echo "✔ Tunnel established in background."
    else
        echo "✘ Failed to establish tunnel."
    fi
}

# List and kill active tunnels created by ssh-forward
ssh-forward-ls() {
    local sockets=(/tmp/ssh-fwd-*.sock(N))
    
    if [[ ${#sockets} -eq 0 ]]; then
        echo "No active ssh-forward tunnels found."
        return 0
    fi

    echo "Active Tunnels:"
    echo "----------------------------------------"
    for s in $sockets; do
        # Extract host and port from filename
        local filename=$(basename "$s")
        local details=${filename#ssh-fwd-}
        details=${details%.sock}
        local host=${details%-*}
        local port=${details#*-}
        
        echo "Host: $host | Primary Port: $port"
    done
    echo "----------------------------------------"
    echo -n "Would you like to stop a tunnel? (Enter host name or 'all' / 'no'): "
    read answer

    if [[ "$answer" == "all" ]]; then
        for s in $sockets; do
            ssh -S "$s" -O exit dummy-host 2>/dev/null
        done
        echo "All tunnels closed."
    elif [[ -n "$answer" && "$answer" != "no" ]]; then
        # Close specific matching sockets
        for s in /tmp/ssh-fwd-${answer}-*.sock(N); do
            ssh -S "$s" -O exit dummy-host 2>/dev/null
            echo "Closed tunnel for $answer."
        done
    fi
}

# Smarter tab completion
# Smarter tab completion reading from both standard and custom SSH configs
_ssh_forward_advanced() {
    local -a hosts
    local -A unique_hosts  # Associative array to handle deduplication
    local config_file

    # Array of config paths to check
    local config_files=(
        ~/.ssh/config
        ~/.config/ooodnakov/ssh/config
    )

    for config_file in $config_files; do
        if [[ -f $config_file ]]; then
            # Parse 'Host' lines, ignoring wildcards like '*'
            for h in $(awk '/^Host / && !/\*/ {print $2}' "$config_file"); do
                unique_hosts[$h]=1
            done
        fi
    done

    # Convert the unique keys back into a standard array
    hosts=(${(k)unique_hosts})

    # If first arg is -r, adjust the argument positions for completion
    if [[ "$words[2]" == "-r" ]]; then
        _arguments '1:flags:(-r)' '2:hosts:($hosts)' '3:ports:(80 443 3000 5432 8080 27017)' '4:ports:(80 443 3000 5432 8080 27017)'
    else
        _arguments '1:hosts:($hosts -r)' '2:ports:(80 443 3000 5432 8080 27017)' '3:ports:(80 443 3000 5432 8080 27017)'
    fi
}
