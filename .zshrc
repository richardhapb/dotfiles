# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

if [[ "$OSTYPE" == "darwin" ]]; then
    export ICLOUD="/Users/richard/Library/Mobile Documents/com~apple~CloudDocs"
    export IN="$HOME/Documents/Brain/Inbox"
    export DEV="$HOME/Documents/Developer"
    # To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
    [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
    source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    eval "$(fnm env --use-on-cd)"
    source $(brew --prefix)/share/powerlevel10k/powerlevel10k.zsh-theme
elif [[ "$OSTYPE" == "linux-gnu" ]]; then
    source ~/powerlevel10k/powerlevel10k.zsh-theme
    source .p10k.zsh
    export DEV="$HOME"/dev
fi
export NOTES="$HOME/Documents/notes"

export PYENV_ROOT="$HOME/.pyenv"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH:/Users/richard/mongodb/bin"

PATH=~/.console-ninja/.bin:$PATH
export PATH="/opt/homebrew/bin:$PATH"

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"

alias d="cd $DEV"
alias va="source .venv/bin/activate"
alias ll="ls -la"

# TMUX
if command -v tmux &> /dev/null && [ -z "$TMUX" ]; then
    tmux attach-session -t main || tmux new-session -s main
fi

