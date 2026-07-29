. "$HOME/.zprofile"

if [[ "$OSTYPE" == "darwin"* ]]; then
    source "$HOME/.zsh_mac"
elif [[ "$OSTYPE" == "linux-gnu" ]]; then
    source "$HOME/.zsh_linux"
fi

. "$HOME/.zsh_env"

export PATH=$HOME/.local/bin:$PATH  # I need this as maximum priority

# Completions: initialize once, here, after every fpath addition from the files
# above. Rebuild the dump at most once a day -- a full compinit (security audit
# + dump rewrite) costs ~300ms, `compinit -C` costs ~7ms.
autoload -Uz compinit
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${_zcompdump:h}"
if [[ -n ${_zcompdump}(#qN.mh-24) ]]; then
    compinit -C -d "$_zcompdump"
else
    compinit -d "$_zcompdump"
fi
unset _zcompdump

# Activate Ruby per .ruby-version at init (not only via chruby's preexec hook),
# so tools that snapshot the shell environment at startup (e.g. Claude Code)
# capture the right Ruby instead of system /usr/bin/ruby. Must run last, after
# .zprofile/.zsh_mac have reset PATH. Harmless for normal interactive use.
command -v chruby_auto >/dev/null && chruby_auto
