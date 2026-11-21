#!/usr/bin/env bash
# Freeze the local state of a repo so a background reviewer reads a stable copy.
#
#   snapshot.sh [-o PARENT_DIR] <repo> [base]
#
# Creates a private (700) directory under PARENT_DIR (default $TMPDIR or /tmp):
#   committed.diff  merge-base(base, HEAD)..HEAD
#   worktree.diff   staged + unstaged changes against HEAD
#   untracked/      frozen copies of untracked, non-ignored text files
#   manifest.txt    "<copy path> -> <repo-relative path>" per copied file
#   skipped.txt     untracked files not copied, with the reason
# and prints the directory path as the last line of stdout.
#
# base defaults to the first existing of origin/main, origin/master, main, master.
set -euo pipefail

PARENT="${TMPDIR:-/tmp}"
while getopts "o:" opt; do
  case "$opt" in
    o) PARENT="$OPTARG" ;;
    *) echo "usage: snapshot.sh [-o PARENT_DIR] <repo> [base]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { echo "usage: snapshot.sh [-o PARENT_DIR] <repo> [base]" >&2; exit 2; }

REPO="$(cd "$1" && pwd -P)"
BASE="${2:-}"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "snapshot.sh: not a git repo: $REPO" >&2; exit 2; }

if [ -z "$BASE" ]; then
  for cand in origin/main origin/master main master; do
    if git -C "$REPO" rev-parse --verify -q "$cand^{commit}" >/dev/null; then BASE="$cand"; break; fi
  done
fi

mkdir -p "$PARENT"
DEST="$(mktemp -d "${PARENT%/}/wrl.XXXXXX")"
chmod 700 "$DEST"
mkdir "$DEST/untracked"
: > "$DEST/manifest.txt"
: > "$DEST/skipped.txt"

if [ -n "$BASE" ] && MB="$(git -C "$REPO" merge-base "$BASE" HEAD 2>/dev/null)"; then
  git -C "$REPO" --no-pager diff "$MB" HEAD > "$DEST/committed.diff"
else
  : > "$DEST/committed.diff"
  echo "no base found; committed.diff is empty" >> "$DEST/skipped.txt"
fi
git -C "$REPO" --no-pager diff HEAD > "$DEST/worktree.diff" 2>/dev/null || : > "$DEST/worktree.diff"

is_secret() {
  case "$(basename "$1" | tr '[:upper:]' '[:lower:]')" in
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|id_rsa*|id_ed25519*|*credential*|*secret*|.netrc|.npmrc) return 0 ;;
  esac
  return 1
}

while IFS= read -r -d '' rel; do
  src="$REPO/$rel"
  if [ -L "$src" ]; then echo "$rel: symlink" >> "$DEST/skipped.txt"; continue; fi
  if is_secret "$rel"; then echo "$rel: possible secret" >> "$DEST/skipped.txt"; continue; fi
  if [ -s "$src" ] && ! LC_ALL=C grep -Iq . "$src"; then echo "$rel: binary" >> "$DEST/skipped.txt"; continue; fi
  mkdir -p "$DEST/untracked/$(dirname "$rel")"
  cp -p "$src" "$DEST/untracked/$rel"
  echo "$DEST/untracked/$rel -> $rel" >> "$DEST/manifest.txt"
done < <(git -C "$REPO" ls-files -z --others --exclude-standard)

echo "base: ${BASE:-none}"
echo "copied: $(wc -l < "$DEST/manifest.txt" | tr -d ' ') untracked, skipped: $(wc -l < "$DEST/skipped.txt" | tr -d ' ')"
echo "$DEST"
