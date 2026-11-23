# The board's IPv4 address, whichever interface has it (on the KR260 it is
# eth1; eth0 has none). Empty output of a command that succeeds must not stop
# the search, so take the first global address of any interface.
first_ip() {
    addr=$(ip -4 -o addr show scope global 2>/dev/null | awk '{split($4, a, "/"); print a[1]; exit}')
    echo "${addr:-no-ip}"
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
