#!/bin/sh

languages=$(echo "lua python js bash css html" | tr ' ' '\n')
commands=$(echo "curl git find sed awk grep fd fzf tr tar less tmux nvim vim" | tr ' ' '\n')

selected=$(echo "$languages\n$commands" | fzf)

read -p "Enter query: " query

if echo "$languages" | grep -q "$selected"; then
    tmux split-window -h bash -c "curl -s cht.sh/$selected/$(echo $query | tr ' ' '+') | less -r"
else
    tmux split-window -h bash -c "curl -s cht.sh/$selected~$query | less -r"
fi

