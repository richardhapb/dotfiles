autoload -Uz vcs_info
precmd() { vcs_info }

# Git branch info
zstyle ':vcs_info:git:*' formats ' (%b)'
zstyle ':vcs_info:*' enable git

setopt PROMPT_SUBST

# Two-line prompt: path on first line, symbol on second
PROMPT='%F{blue}%~%f%F{yellow}${vcs_info_msg_0_}%f
%F{green}❯%f '

bindkey -v  # Enable vi mode
export KEYTIMEOUT=1  # Reduce ESC delay from 400ms to 10ms

# bash/emacs shortcuts in insert mode
bindkey -M viins '^A' beginning-of-line
bindkey -M viins '^E' end-of-line
bindkey -M viins '^F' tmux-sessionizer
bindkey -M viins '^K' kill-line
bindkey -M viins '^U' backward-kill-line
bindkey -M viins '^W' backward-kill-word
bindkey -M viins '^Y' yank

# Make backspace and delete work properly
bindkey -M viins '^?' backward-delete-char
bindkey -M viins '^H' backward-delete-char

# Look for history!!
bindkey '^R' fzf-history-widget

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

        # Compilation paths
        echo "export SDKROOT=\"$(xcrun --show-sdk-path)\"" >> "$CACHE_FILE"
        echo "export PKG_CONFIG_PATH=\"/opt/homebrew/lib/pkgconfig:${PKG_CONFIG_PATH}\"" >> "$CACHE_FILE"
        echo "export LIBRARY_PATH=\"/opt/homebrew/lib:${LIBRARY_PATH}\"" >> "$CACHE_FILE"
        echo "export CPATH=\"$(xcrun --show-sdk-path)/usr/include:${CPATH}\"" >> "$CACHE_FILE"
    fi
fi

source "$CACHE_FILE"

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"

alias dd="cd $DEV"
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
alias gpf='git push --force-with-lease'
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


alias lr='ln -sf $(pwd)/target/release/$(dirname $(pwd)) ~/.local/bin'
alias ld='ln -sf $(pwd)/target/debug/$(dirname $(pwd)) ~/.local/bin'

alias h='eval $(history 0 | sort -r | sed -E "s/\s*[0-9]+\s+//" | uniq | fzf)'
alias v="nvim"
alias f='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git | fzf --preview "bat --style=numbers --color=always --line-range :500 {}" | xargs -r nvim'
d() { local dir=$(fd --type d --strip-cwd-prefix --hidden --follow --exclude .git | fzf --preview "ls -lhAG {}"); [ -n "$dir" ] && cd "$dir" }
alias dl='docker ps -a --format "{{.State}} | {{.Names}}" | fzf --preview "docker logs -n 1000 {+2}" | awk -F"|" "{print \$2}" | xargs -r docker logs -n 1000 -f'
dt() { container=$(docker ps --format "{{.Names}}" | fzf --preview "docker logs -n 1000 {}") && [ -n "$container" ] && docker exec -it "$container" bash; }
dx() {
    local prefix=$1
    if [ -z "$prefix" ]; then
        echo "prefix is required"
        return 1
    fi

    local stopped=0

    set +m
    for container in $(docker ps --format "{{.Names}}"); do
        if [[ "$container" == "$prefix"* ]]; then
            echo "Stopping $container"
            docker stop "$container" &
            stopped=$((stopped+1))
        fi
    done

    if [ "$stopped" -gt 0 ]; then
        echo "Waiting for containers to stop..."
        wait
        set -m
        echo "Containers stopped"
    else
        echo "Nothing to stop"
    fi
}

dr() {
    local prefix=$1
    if [ -z "$prefix" ]; then
        echo "prefix is required"
        return 1
    fi

    local started=0

    set +m
    for container in $(docker ps -a --filter "status=exited" --format "{{.Names}}"); do
        if [[ "$container" == "$prefix"* ]]; then
            echo "Starting $container"
            docker start "$container" &
            started=$((started+1))
        fi
    done

    if [ "$started" -gt 0 ]; then
        echo "Waiting for containers to start..."
        wait
        set -m
        echo "Containers started"
    else
        echo "Nothing to start"
    fi
}

n() {
    printf "Title: "
    read TITLE

    if [ -z "$TITLE" ]; then
        return
    fi

    dir=$NOTES/warlog
    mkdir -p "$dir"

    date +%Y%M%d | xargs -I{} nvim "${dir}/{}_${TITLE}.md"
}

docker_norestart() {
    for container in $(docker ps -a --format '{{.Names}}'); do
        docker update --restart no "$container"
    done
}


bindkey -s ^f "tmux-sessionizer\n"

export NVIM="$HOME/.config/nvim"
export DOTFILES="$HOME/dotfiles"

export EDITOR="nvim"
export VISUAL="nvim"
export SYSTEMD_EDITOR="nvim"

export NVIM_LOG_FILE=/tmp/nvim.log

. "$HOME/.cargo/env"

[[ $(command -v fnm 2>&1 /dev/null) ]] && eval "$(fnm env --use-on-cd --shell zsh)"
[[ $(command -v zoxide 2>&1 /dev/null) ]] && eval "$(zoxide init zsh)"
[[ $(command -v pyenv 2>&1 /dev/null) ]] && eval "$(pyenv init - zsh)"

export LUA_PATH="./?.lua;/usr/local/share/lua/5.4/?.lua;$HOME/.luarocks/share/lua/5.4/?.lua;;"
export LUA_CPATH="./?.so;/usr/local/lib/lua/5.4/?.so;$HOME/.luarocks/lib/lua/5.4/?.so;;"

export TERMINAL=wezterm
export RAINFROG_CONFIG=~/.config/rainfrog

export HISTSIZE=100000
export HISTFILESIZE=100000
export HISTCONTROL=ignoredups:ignorespace

setopt INTERACTIVE_COMMENTS  # Allow comments in shell


# Set up fzf key bindings and fuzzy completion
source <(fzf --zsh)
# Open in tmux popup if on tmux, otherwise use --height mode
export FZF_DEFAULT_OPTS='--height 40% --tmux bottom,40% --layout reverse --border top'

