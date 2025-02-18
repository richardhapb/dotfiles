. "$HOME/.zprofile"

if [[ "$OSTYPE" == "darwin"* ]]; then
    source "$HOME/.zsh_mac"
elif [[ "$OSTYPE" == "linux-gnu" ]]; then
    source "$HOME/.zsh_linux"
fi

export PATH=$HOME/.local/bin:$PATH  # I need this as maximum priority

if command -v tmux &> /dev/null && [ -n "$PS1" ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then
  tmux || echo "Error initializing tmux"
fi

