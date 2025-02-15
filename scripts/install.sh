#!/bin/bash

# Create stow for all files in the current directory

cd ..

for dir in $(ls) do
    stow $dir --adopt
done

