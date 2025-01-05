#!/bin/bash

# Create symlinks for all files in the current directory
# in the home directory, and skip if the file already exists
# includes hidden files

for file in .*; do
    if [ -f "$file" ]; then
        if [ -e "$HOME/$file" ]; then
        echo "Skipping $file: file already exists in $HOME"
        else
        ln -s "$(pwd)/$file" "$HOME/$file"
        echo "Created symlink to $file in $HOME"
        fi
    fi
done


if [ -f ~/migrate-repo.sh ]; then
    echo "Moving migrate-repo.sh to configs folder..."
    mv ~/migrate-repo.sh ~/configs/
fi

echo "Symlinks created successfully!"

