
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

export XDG_CONFIG_HOME="$HOME/.config"

export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

alias d="cd $DEV"
alias cdd='cd ~/dev'
alias va="source .venv/bin/activate"
alias ls="ls -G"
alias ll="ls -lhaG"
alias cdn='cd ~/.config/nvim'
alias vps="ssh ubuntu@3.145.58.151"

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gp='git push'
alias gpl='git pull'
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

bindkey -s ^f "tmux-sessionizer\n"

alias jupyter="$HOME/.config/nvim/.venv/bin/jupyter"

nvm use default > /dev/null

export NVIM="$HOME/.config/nvim"
export DOTFILES="$HOME/dotfiles"

export EDITOR="$HOME/nvim/bin/nvim"
export VISUAL="$HOME/nvim/bin/nvim"

. "$HOME/.cargo/env"

export HISTSIZE=100000
export HISTFILESIZE=100000
export HISTCONTROL=ignoredups:ignorespace  # Avoid duplicate entries

