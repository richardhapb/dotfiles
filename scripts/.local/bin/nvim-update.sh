#!/bin/bash
name=nvim.tar.gz

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if ! dpkg -l | grep glibc ; then
                sudo apt install glibc-source -y
        fi
    folder_name=nvim-linux-x86_64
    wget https://github.com/neovim/neovim/releases/download/nightly/$folder_name.tar.gz -O $HOME/$name
elif [[ "$OSTYPE" == "darwin"* ]]; then
    folder_name=nvim-macos-arm64
    wget https://github.com/neovim/neovim/releases/download/nightly/$folder_name.tar.gz -O $HOME/$name
fi

xattr -c $HOME/$name
rm -rf $HOME/nvim
tar -xvf $HOME/$name -C $HOME
mv $HOME/$folder_name $HOME/nvim
rm $HOME/$name
ln -sf $HOME/nvim/bin/nvim $HOME/.local/bin/nvim
source $HOME/.zshrc
