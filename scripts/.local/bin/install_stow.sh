#!/bin/bash

# Create stow for all files in the current directory

cd $DOTFILES

for dir in $(ls -d */ .*/ | sed 's/\///' | grep -Ev '^\.*$'); do
    if [ "$dir" == ".git" ]; then
        continue
    fi
    echo "stow $dir"
    stow -D $dir
    stow $dir
done
