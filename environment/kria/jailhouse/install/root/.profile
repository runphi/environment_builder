# Function to get first IPv4 (BusyBox-friendly). Adjust interface order if needed.
first_ip() {
    # Try iproute2/ip from BusyBox
    if command -v ip >/dev/null 2>&1; then
        ip -4 addr show dev eth0 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1 && return
        ip -4 addr show dev wlan0 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1 && return
        ip -4 addr show 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1 && return
    fi
    # Fallback to ifconfig if present
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig eth0 2>/dev/null | awk '/inet /{print $2; exit}' && return
        ifconfig wlan0 2>/dev/null | awk '/inet /{print $2; exit}' && return
        ifconfig 2>/dev/null | awk '/inet /{print $2; exit}' && return
    fi
    echo "no-ip"
}

# Ensure kernel hostname matches /etc/hostname (safe no-op if already set)
[ -r /etc/hostname ] && hostname -F /etc/hostname 2>/dev/null

IP_ADDR="$(first_ip)"

case "$TERM" in
  xterm*|screen*|tmux*)
    # Blank line before prompt, then line1 host@ip (colored), line2 path + >
    PS1='\n\[\e[38;5;75m\]\h\[\e[0m\]@\[\e[38;5;111m\]'"$IP_ADDR"'\[\e[0m\]\n\[\e[38;5;111m\]\w\[\e[0m\] \[\e[38;5;156;1m\]>\[\e[0m\] '
    ;;
  vt100|vt102|vt220|*)
    # Non-colored fallback
    PS1='\n\h@'"$IP_ADDR"'\n\w > '
    ;;
esac

# enable color support of ls and also add handy aliases
# Only enable colored ls for terminals that support it
case "$TERM" in
    xterm*|screen*|tmux*)
        alias ls='ls --color=auto'
        alias grep='grep --color=auto'
        alias fgrep='fgrep --color=auto'
        alias egrep='egrep --color=auto'
        ;;
    *)
        # No color aliases for basic terminals
        alias ls='ls'
        alias grep='grep'
        alias fgrep='fgrep'
        alias egrep='egrep'
        ;;
esac

# some more ls aliases
alias ll='ls -alF'
alias cl='clear'
