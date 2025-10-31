#!/bin/bash

set -euo pipefail

if [ -z "${DEV-}" ]; then
    echo "Error: DEV environment variable is not set"
    exit 1
fi

nvim_dir="$DEV/cont/neovim"
dest_dir="$HOME/nvim"

if [ ! -d "$nvim_dir" ]; then
    mkdir -p "$nvim_dir"
    git clone git@github.com:richardhapb/neovim "$nvim_dir"
fi

cd "$nvim_dir" || exit 1

if ! git remote -v | grep -q upstream; then
    git remote add upstream git@github.com:neovim/neovim
fi

if [ ! -d "$dest_dir" ]; then
    mkdir -p "$dest_dir"
fi

git pull upstream master

sudo rm -rf "$nvim_dir/{.deps,build}"
sudo make CMAKE_INSTALL_PREFIX="$dest_dir" CMAKE_BUILD_TYPE=RelWithDebInfo install

