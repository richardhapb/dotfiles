. "$HOME/.zprofile"

if [[ "$OSTYPE" == "darwin"* ]]; then
    source "$HOME/.zsh_mac"
elif [[ "$OSTYPE" == "linux-gnu" ]]; then
    source "$HOME/.zsh_linux"
fi

export PATH=$HOME/.local/bin:$PATH  # I need this as maximum priority

. "$HOME/.zsh_env"

# Activate Ruby per .ruby-version at init (not only via chruby's preexec hook),
# so tools that snapshot the shell environment at startup (e.g. Claude Code)
# capture the right Ruby instead of system /usr/bin/ruby. Must run last, after
# .zprofile/.zsh_mac have reset PATH. Harmless for normal interactive use.
command -v chruby_auto >/dev/null && chruby_auto
