#!/bin/bash

echo "Migrating repository..."

echo "Removing unnecessary files..."
rm .config/nvim/.git

echo "Moving files to nvim folder..."
mkdir .config/nvim/.git
mv .git/modules/.config/nvim/* .config/nvim/.git/
rm -rf .git/modules
rm .gitmodules

echo "Verifying if configs folder exists, if not, create it..."
# Verify if configs exists, if not, create it
if [ ! -d configs ]; then
    echo "Creating configs folder..."
  mkdir configs
fi

echo "Moving files to configs folder..."
mv .zhsrc .tmux.conf .tmux_mac.conf .tmux_linux.conf .wezterm.lua .gitconfig .gitignore create-symlinks.sh configs/
mv .git configs/.git

cd configs
./create-symlinks.sh

echo "Migration completed!"

