#!/bin/bash

# Create stow for all files in the DOTFILES directory

if [ -z "$DOTFILES" ]; then
    echo "DOTFILES should be defined"
    exit 1
fi

cd $DOTFILES

for dir in $(ls -d */ .*/ | sed 's/\///' | grep -Ev '^\.*$'); do
    if [ "$dir" == ".git" ]; then
        continue
    fi
    echo "stow $dir"
    stow -D $dir
    stow $dir
done
