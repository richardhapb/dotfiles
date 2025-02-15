source .zprofile

if [[ "$OSTYPE" == "darwin"* ]]; then
    source .zsh_mac
elif [[ "$OSTYPE" == "linux-gnu" ]]; then
    source .zsh_linux
fi

if command -v tmux &> /dev/null && [ -n "$PS1" ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then
  exec tmux
fi

