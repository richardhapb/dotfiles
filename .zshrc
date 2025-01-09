# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
    export ICLOUD="/Users/richard/Library/Mobile Documents/com~apple~CloudDocs"
    export IN="$HOME/Documents/Brain/Inbox"
    export DEV="$HOME/Documents/Developer"
    export NOTES="$HOME/Documents/notes"
    # To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
    source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    eval "$(fnm env --use-on-cd)"
    source $(brew --prefix)/share/powerlevel10k/powerlevel10k.zsh-theme

    # SPARK
    export JAVA_HOME=$(brew --prefix java)@17 
    export PATH=$JAVA_HOME/bin:$PATH
    export SPARK_HOME=$(brew --prefix apache-spark)/libexec
    export PATH=$SPARK_HOME/bin:$PATH
    export PATH=$HOME/.cargo/env:$PATH
    export CC=$(brew --prefix llvm)/bin/clang
    export CXX=$(brew --prefix llvm)/bin/clang++
    export PATH=$PATH:"/Users/richard/texpresso/build"
    export PATH=$PATH:"/Users/richard/kanata"
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH:/Users/richard/mongodb/bin"
    export PATH="/opt/homebrew/bin:$PATH"
    export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
elif [[ "$OSTYPE" == "linux-gnu" ]]; then
    source ~/powerlevel10k/powerlevel10k.zsh-theme
    export DEV="$HOME"/dev
    source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

    # ~/.bashrc: executed by bash(1) for non-login shells.
    # see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
    # for examples
    setopt autocd
    # If not running interactively, don't do anything
    case $- in
        *i*) ;;
          *) return;;
    esac

    # don't put duplicate lines or lines starting with space in the history.
    # See bash(1) for more options
    HISTCONTROL=ignoreboth

    # for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
    HISTSIZE=1000
    HISTFILESIZE=2000

    # If set, the pattern "**" used in a pathname expansion context will
    # match all files and zero or more directories and subdirectories.
    #shopt -s globstar

    # make less more friendly for non-text input files, see lesspipe(1)
    [ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

    # set variable identifying the chroot you work in (used in the prompt below)
    if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
        debian_chroot=$(cat /etc/debian_chroot)
    fi

    # set a fancy prompt (non-color, unless we know we "want" color)
    case "$TERM" in
        xterm-color|*-256color) color_prompt=yes;;
    esac

    # uncomment for a colored prompt, if the terminal has the capability; turned
    # off by default to not distract the user: the focus in a terminal window
    # should be on the output of commands, not on the prompt
    force_color_prompt=yes

    if [ -n "$force_color_prompt" ]; then
        if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        color_prompt=yes
        else
        color_prompt=
        fi
    fi

    if [ "$color_prompt" = yes ]; then
        PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
    else
        PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
    fi
    unset color_prompt force_color_prompt

    # If this is an xterm set the title to user@host:dir
    case "$TERM" in
    xterm*|rxvt*)
        PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
        ;;
    *)
        ;;
    esac

    # enable color support of ls and also add handy aliases
    if [ -x /usr/bin/dircolors ]; then
        test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
        alias ls='ls --color=auto'
        #alias dir='dir --color=auto'
        #alias vdir='vdir --color=auto'

        alias grep='grep --color=auto'
        alias fgrep='fgrep --color=auto'
        alias egrep='egrep --color=auto'
    fi

    # colored GCC warnings and errors
    #export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

    # some more ls aliases
    alias ll='ls -alF'
    alias la='ls -A'
    alias l='ls -CF'

    # Add an "alert" alias for long running commands.  Use like so:
    #   sleep 10; alert
    alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

    # Alias definitions.
    # You may want to put all your additions into a separate file like
    # ~/.bash_aliases, instead of adding them here directly.
    # See /usr/share/doc/bash-doc/examples in the bash-doc package.

    if [ -f ~/.bash_aliases ]; then
        . ~/.bash_aliases
    fi

    # . "$HOME/.cargo/env"

    alias wezterm='flatpak run org.wezfurlong.wezterm'
    export JAVA_HOME=$(readlink -f /usr/bin/javac | sed "s:/bin/javac::")

    export PATH=$PATH:/home/richard/pycharm-2024.3/bin
    export PATH=$PATH:/usr/lib/snap
    export PATH=$PATH:/opt/nvim-linux64/bin
    export PATH=$PATH:/home/richard/.local/bin

    export DEV="$HOME/dev"
    export NOTES="$HOME/notes"
fi

PATH=~/.console-ninja/.bin:$PATH

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
alias ll="ls -laG"
alias cdn='cd ~/.config/nvim'
alias nvim='~/nvim/bin/nvim'
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
alias gbs='git branch --show-current'
alias gl='git log'
alias gd='git diff'
alias gds='git diff --staged'
alias gdw='git diff --word-diff'
alias gdc='git diff --cached'
alias gsw='git switch'
alias gt='git tree'
alias gr='git rebase'
alias grf='git reflog'


nvm use default > /dev/null

export NVIM="$HOME/.config/nvim"

export EDITOR='~/nvim/bin/nvim'
export VISUAL='~/nvim/bin/nvim'

typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

if command -v tmux &> /dev/null && [ -n "$PS1" ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then
  exec tmux
fi
