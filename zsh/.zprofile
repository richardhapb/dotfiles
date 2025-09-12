
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

# Locals
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

export XDG_CONFIG_HOME="$HOME/.config"

# Essential paths (minimal set at startup)
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/share/nvim/mason/bin:$HOME/go/bin:/usr/local/go/bin"

# Cache expensive operations

# Create a cache file that gets regenerated daily or when needed
CACHE_FILE="$HOME/.zsh_cache"
CACHE_EXPIRY=86400 # 24 hours in seconds

# Only regenerate cache if it doesn't exist or is older than expiry time
if [[ ! -f "$CACHE_FILE" ]]; then
    # Cache file doesn't exist, create it
    mkdir -p "$(dirname "$CACHE_FILE")"
    touch "$CACHE_FILE"
    NEEDS_REGEN=true
else
    # Check if cache is older than expiry time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS uses different stat format
        FILE_MOD_TIME=$(stat -f %m "$CACHE_FILE" 2>/dev/null)
    else
        # Linux stat format
        FILE_MOD_TIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null)
    fi

    CURRENT_TIME=$(date +%s)
    if (( CURRENT_TIME - FILE_MOD_TIME > CACHE_EXPIRY )); then
        NEEDS_REGEN=true
    else
        NEEDS_REGEN=false
    fi
fi

if [[ "$NEEDS_REGEN" == true ]]; then  # Cache Homebrew prefixes to avoid slow `brew --prefix` calls
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "export HOMEBREW_PREFIX=\"$(brew --prefix)\"" > "$CACHE_FILE"
        echo "export JAVA_HOME=\"$(brew --prefix java)@17\"" >> "$CACHE_FILE"
        echo "export SPARK_HOME=\"$(brew --prefix apache-spark)/libexec\"" >> "$CACHE_FILE"
        echo "export LLVM_PATH=\"$(brew --prefix llvm)/bin\"" >> "$CACHE_FILE"
        echo "export ZSH_HIGHLIGHT_PATH=\"$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh\"" >> "$CACHE_FILE"
        echo "export ZSH_SUGGESTIONS_PATH=\"$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh\"" >> "$CACHE_FILE"
        echo "export P10K_PATH=\"$HOMEBREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme\"" >> "$CACHE_FILE"

        # Compilation paths
        echo "export SDKROOT=\"$(xcrun --show-sdk-path)\"" >> "$CACHE_FILE"
        echo "export PKG_CONFIG_PATH=\"/opt/homebrew/lib/pkgconfig:/opt/homebrew/share/pkgconfig:${PKG_CONFIG_PATH}\"" >> "$CACHE_FILE"
        echo "export LIBRARY_PATH=\"/opt/homebrew/lib:${LIBRARY_PATH}\"" >> "$CACHE_FILE"
        echo "export CPATH=\"$SDKROOT/usr/include:${CPATH}\"" >> "$CACHE_FILE"
    fi
fi

source "$CACHE_FILE"

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null; then
    eval "$(pyenv init --path)"
fi

alias d="cd $DEV"
alias cdd='cd ~/dev'
alias va="source .venv/bin/activate"
alias ls="ls -G"
alias ll="ls -lhAG"
alias cdn='cd ~/.config/nvim'
alias grep='grep --color=auto'

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gp='git push'
alias gpl='git pull --rebase'
alias gco='git checkout'
alias gb='git branch'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gbm='git branch -m'
alias gbu='git branch -u origin/$(git rev-parse --abbrev-ref HEAD)'
alias gbs='git branch --show-current'
alias gl='git log'
alias gd='git diff'
alias gds='git diff --staged'
alias gdw='git diff --word-diff'
alias gdc='git diff --cached'
alias gsw='git switch'
alias gt='git tree'
alias grb='git rebase'
alias grs='git restore'
alias grf='git reflog'
alias gcl='git clone'
alias gf='git fetch'
alias gm='git merge'

alias h='eval $(history 0 | sed -E "s/\s*[0-9]+\s+//" | sort | uniq | fzf)'
alias v="nvim"

bindkey -s ^f "tmux-sessionizer\n"

export NVIM="$HOME/.config/nvim"
export DOTFILES="$HOME/dotfiles"

export EDITOR="nvim"
export VISUAL="nvim"
export SYSTEMD_EDITOR="nvim"

. "$HOME/.cargo/env"

eval "$(fnm env --use-on-cd --shell zsh)"

export LUA_PATH="./?.lua;/usr/local/share/lua/5.4/?.lua;$HOME/.luarocks/share/lua/5.4/?.lua;;"
export LUA_CPATH="./?.so;/usr/local/lib/lua/5.4/?.so;$HOME/.luarocks/lib/lua/5.4/?.so;;"

export TERMINAL=/usr/bin/ghostty
export RAINFROG_CONFIG=~/.config/rainfrog

export HISTSIZE=100000
export HISTFILESIZE=100000
export HISTCONTROL=ignoredups:ignorespace
