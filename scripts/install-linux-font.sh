#!/bin/bash

echo "Installing fonts..."

link="https://download.jetbrains.com/fonts/JetBrainsMono-2.304.zip"
font_dir="$HOME/.local/share/fonts/JetBrainsMono"

echo "Downloading JetBrains Mono font..."
wget -O JetBrainsMono.zip $link

echo "Creating font directory..."
mkdir -p $font_dir

echo "Extracting font..."
unzip JetBrainsMono.zip -d $font_dir

echo "Cleaning up..."
rm JetBrainsMono.zip

echo "Updating font cache..."
fc-cache -f -v

echo "Fonts installed successfully!"

