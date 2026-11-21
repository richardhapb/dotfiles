#!/usr/bin/env bash
# Run: bash tests/test_snapshot.sh   (from the skill dir)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

R="$T/repo"; mkdir -p "$R/sub"; cd "$R"
git init -q -b main; git config user.email t@t; git config user.name t
echo a > a.txt; git add .; git commit -qm init
git checkout -qb feat
echo b >> a.txt; git commit -qam c1
echo c >> a.txt
echo staged > s.txt; git add s.txt
echo new > "new file.txt"; echo x > sub/u.txt
echo SECRET=1 > .env; printf 'bin\0' > b.bin; ln -s a.txt link
echo ignored > i.log; echo '*.log' > .gitignore; git add .gitignore

OUT="$("$HERE/scripts/snapshot.sh" -o "$T/out" "$R")"
D="$(echo "$OUT" | tail -1)"

[ -d "$D" ] || fail "no snapshot dir"
[ "$(stat -f %Lp "$D" 2>/dev/null || stat -c %a "$D")" = "700" ] || fail "dir not 700"
grep -q '^+b$' "$D/committed.diff" || fail "committed diff missing"
grep -q '^+c$' "$D/worktree.diff" || fail "unstaged diff missing"
grep -q 's.txt' "$D/worktree.diff" || fail "staged diff missing"
[ -f "$D/untracked/new file.txt" ] || fail "name with space not copied"
[ -f "$D/untracked/sub/u.txt" ] || fail "nested untracked not copied"
[ ! -e "$D/untracked/.env" ] || fail ".env was copied"
[ ! -e "$D/untracked/b.bin" ] || fail "binary was copied"
[ ! -e "$D/untracked/i.log" ] || fail "ignored file was copied"
grep -q '^.env: possible secret' "$D/skipped.txt" || fail ".env not listed"
grep -q '^b.bin: binary' "$D/skipped.txt" || fail "binary not listed"
grep -q '^link: symlink' "$D/skipped.txt" || fail "symlink not listed"
grep -q -- '-> new file.txt$' "$D/manifest.txt" || fail "manifest missing entry"

# explicit base, and a repo with no base branch
"$HERE/scripts/snapshot.sh" -o "$T/out" "$R" main >/dev/null
git -C "$R" branch -m main trunk
NB="$("$HERE/scripts/snapshot.sh" -o "$T/out" "$R")"
echo "$NB" | grep -q 'base: none' || fail "no-base case"
echo "ok"
