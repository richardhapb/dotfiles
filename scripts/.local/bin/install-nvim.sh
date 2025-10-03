#!/usr/bin/env bash

set -Eeuo pipefail

: "${DEV:?Define the DEV environment variable first}"
INSTALL_PREFIX="${HOME}/nvim"
REPO_DIR="${DEV}/cont/neovim"
BRANCH="master"

command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; }
command -v cmake >/dev/null 2>&1 || { echo "cmake not found"; exit 1; }

# Prefer Ninja if available (much faster)
GEN_ARGS=()
if command -v ninja >/dev/null 2>&1; then
  GEN_ARGS+=(-G Ninja)
fi

mkdir -p "&DEV/cont"

if [ ! -d "$REPO_DIR" ]; then
  git clone --single-branch --branch "$BRANCH" --depth 1 \
    git@github.com:neovim/neovim "$REPO_DIR"
fi

cd "${REPO_DIR}"

# Keep shallow clone fresh & consistent
# Try to use 'upstream' if it exists; otherwise use 'origin'
DEFAULT_REMOTE="origin"
if git remote get-url upstream >/dev/null 2>&1; then
  DEFAULT_REMOTE="upstream"
fi

# Ensure we’re on the right branch; tolerate shallow clone
git fetch "$DEFAULT_REMOTE" --depth 1 "$BRANCH"
git checkout -B "$BRANCH" "refs/remotes/$DEFAULT_REMOTE/$BRANCH"
git reset --hard "refs/remotes/$DEFAULT_REMOTE/$BRANCH"

# ccache for faster rebuilds if available
CCACHE_ARGS=()
if command -v ccache >/dev/null 2>&1; then
  CCACHE_ARGS+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi

sudo cmake -B build -S . \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX=$HOME/nvim
sudo cmake --build build
sudo cmake --install build

