#!/usr/bin/env bash
# Run a command with remote-touching CLIs replaced by recording shims.
#
#   sandbox.sh [-f FIXTURES_DIR] [-l LOG] [-x extra_cmd]... -- <command> [args...]
#
# Every shimmed CLI logs its argv as a JSON line to LOG and then either
#   - prints FIXTURES_DIR/<cmd>[.<arg1>[_<arg2>]].out, most specific first
#     (exit code from the matching .rc file, default 0), or
#   - refuses with exit 126 and a message on stderr.
# Nothing shimmed ever reaches the network. `git` passes through to the real
# binary except for network subcommands.
#
# Limits: only PATH lookups are intercepted. Absolute paths, MCP tools and
# in-process HTTP clients are NOT covered; treat those as "not simulable".
set -euo pipefail

FIXTURES=""
LOG=""
EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    -f) FIXTURES="$2"; shift 2 ;;
    -l) LOG="$2"; shift 2 ;;
    -x) EXTRA+=("$2"); shift 2 ;;
    --) shift; break ;;
    *) echo "sandbox.sh: unexpected arg '$1' (use -- before the command)" >&2; exit 2 ;;
  esac
done
[ $# -gt 0 ] || { echo "sandbox.sh: no command given" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/audit-sandbox.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SHIMS="$WORK/bin"
mkdir -p "$SHIMS"
: "${LOG:=$WORK/calls.jsonl}"
export SANDBOX_LOG="$LOG" SANDBOX_FIXTURES="$FIXTURES" SANDBOX_REAL_PATH="$PATH"
: >> "$LOG"

CMDS=(gh glab kubectl tsh aws gcloud az docker curl wget ssh scp rsync mysql psql redis-cli mongosh rex tmux git terraform helm "${EXTRA[@]+"${EXTRA[@]}"}")

for c in "${CMDS[@]}"; do
  cat > "$SHIMS/$c" <<'SHIM'
#!/usr/bin/env bash
name="$(basename "$0")"
args=""
for a in "$@"; do
  esc="${a//\\/\\\\}"; esc="${esc//\"/\\\"}"
  args="$args\"$esc\","
done
printf '{"cmd":"%s","argv":[%s]}\n' "$name" "${args%,}" >> "$SANDBOX_LOG"

if [ "$name" = git ]; then
  case "${1:-}" in
    push|fetch|pull|clone|remote|ls-remote|submodule)
      echo "sandbox: git $1 blocked" >&2; exit 126 ;;
    *)
      PATH="$SANDBOX_REAL_PATH" exec git "$@" ;;
  esac
fi

if [ -n "$SANDBOX_FIXTURES" ]; then
  # most specific first: <cmd>.<arg1>_<arg2>, <cmd>.<arg1>, <cmd>
  k1="$(printf '%s' "${1:-}" | tr -c 'A-Za-z0-9\n' _)"
  k2="$(printf '%s' "${2:-}" | tr -c 'A-Za-z0-9\n' _)"
  for key in "$name.${k1}_${k2}" "$name.${k1}" "$name"; do
    if [ -f "$SANDBOX_FIXTURES/$key.out" ]; then
      cat "$SANDBOX_FIXTURES/$key.out"
      rc=0
      [ -f "$SANDBOX_FIXTURES/$key.rc" ] && rc="$(cat "$SANDBOX_FIXTURES/$key.rc")"
      exit "$rc"
    fi
  done
fi
echo "sandbox: $name blocked (no fixture)" >&2
exit 126
SHIM
  chmod +x "$SHIMS/$c"
done

set +e
PATH="$SHIMS:$PATH" "$@"
rc=$?
set -e
echo "sandbox: log at $LOG" >&2
[ "$LOG" = "$WORK/calls.jsonl" ] && cat "$LOG" >&2
exit "$rc"
