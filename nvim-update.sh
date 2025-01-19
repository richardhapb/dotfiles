#!/bin/bash
name=nvim.tar.gz

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
		if ! dpkg -l | grep glibc ; then
				sudo apt install glibc-source -y
		fi
    wget https://github.com/neovim/neovim/releases/download/nightly/nvim-linux64.tar.gz -O ~/$name
    folder_name=nvim-linux64
elif [[ "$OSTYPE" == "darwin"* ]]; then
    wget https://github.com/neovim/neovim/releases/download/nightly/nvim-macos-arm64.tar.gz -O ~/$name
    folder_name=nvim-macos-arm64
fi

xattr -c ~/$name
rm -rf ~/nvim
tar -xvf ~/$name -C ~
mv ~/$folder_name ~/nvim
rm ~/$name
