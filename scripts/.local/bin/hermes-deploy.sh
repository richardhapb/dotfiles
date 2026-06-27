#!/usr/bin/env bash
#
# hermes-deploy.sh — overlay the curated ~/.hermes snapshot from dotfiles onto
# an existing ~/.hermes installation.
#
# Only the "wished" items below are copied. Everything else in the destination
# (the hermes-agent app, venv/node_modules, caches, logs, locks, runtime state)
# is left untouched. Matching files ARE overwritten (no --delete, so nothing in
# the destination is removed).
#
# Usage:
#   hermes-deploy.sh [-n] [-s SRC] [-d DST]
#     -n   dry run (show what would change, transfer nothing)
#     -s   source dir   (default: <dotfiles>/.hermes)
#     -d   dest dir     (default: ~/.hermes)

set -euo pipefail

# Resolve dotfiles root from this script's location: scripts/.local/bin/<this>
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

SRC="$DOTFILES_ROOT/.hermes"
DST="$HOME/.hermes"
DRY=""

while getopts "ns:d:h" opt; do
  case "$opt" in
    n) DRY="--dry-run" ;;
    s) SRC="$OPTARG" ;;
    d) DST="$OPTARG" ;;
    h) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "see: $0 -h" >&2; exit 2 ;;
  esac
done

# Items to deploy (config, identity, durable data + procedures). Edit to taste.
ITEMS=(
  config.yaml
  .env
  auth.json
  SOUL.md
  honcho.json
  channel_directory.json
  .install_method
  state.db
  kanban.db
  memories
  sessions
  pastes
  skills
  cron
  scripts
  profiles
  hooks
  state
  state-snapshots
)

[[ -d "$SRC" ]] || { echo "source not found: $SRC" >&2; exit 1; }

echo "src: $SRC"
echo "dst: $DST"
[[ -n "$DRY" ]] && echo "(dry run)"
mkdir -p "$DST"

for item in "${ITEMS[@]}"; do
  if [[ ! -e "$SRC/$item" ]]; then
    echo "skip (absent in src): $item"
    continue
  fi
  # Trailing slash on dirs so contents land inside the dest dir.
  if [[ -d "$SRC/$item" ]]; then
    rsync -a $DRY --human-readable "$SRC/$item/" "$DST/$item/"
  else
    rsync -a $DRY --human-readable "$SRC/$item" "$DST/$item"
  fi
  echo "  deployed: $item"
done

echo "done."
