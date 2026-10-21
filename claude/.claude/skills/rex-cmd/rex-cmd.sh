#!/usr/bin/env bash
# rex-cmd -- drive a sibling Rex pane next to the Claude CLI.
#
# The pane is a real TTY: interactive programs, colours, REPLs and pagers all
# behave normally, and the user watches every command as it runs.
#
# Usage:
#   rex-cmd.sh open   [-d DIR] [-l PCT] [-v]     create/reuse the pane, print its id
#   rex-cmd.sh id                                print the pane id ("" if none)
#   rex-cmd.sh status                            pane id + what is running in it
#   rex-cmd.sh run    [-t SECS] <command...>     run, wait, print output + exit code
#   rex-cmd.sh send   <text...>                  type text + Enter, do not wait
#   rex-cmd.sh key    <key>...                   send key names (ctrl+c, up, enter, q)
#   rex-cmd.sh capture [-n LINES] [-a]           dump what the pane shows
#   rex-cmd.sh close                             close the pane
#
# `run` is for shell commands you need the result of.
# `send`/`key`/`capture` are for interactive programs already running in the pane.

set -uo pipefail

die() { printf 'rex-cmd: %s\n' "$*" >&2; exit 1; }

command -v rex >/dev/null || die "rex not found on PATH"
command -v jq >/dev/null || die "jq not found on PATH"
[ -n "${REX_SESSION:-}" ] && [ -n "${REX_BLOCK:-}" ] \
  || die "not inside Rex (\$REX_SESSION / \$REX_BLOCK unset). Start Claude inside a Rex pane."

SESSION=$REX_SESSION
PARENT=$REX_BLOCK
# The pane is found by label, which embeds the Claude pane that created it, so
# several Claude sessions never steal each other's command pane.
LABEL="claude-cmd-${PARENT##*-}"

find_pane() {
  rex block ls -s "$SESSION" --json 2>/dev/null \
    | jq -r --arg l "$LABEL" '[.blocks[] | select(.label == $l)][0].block_id // empty'
}

# Programs we treat as "a shell sitting at a prompt". Anything else means an
# interactive program owns the pane and `run` would type into it instead.
is_shell() {
  case "$1" in zsh|bash|sh|fish|dash|ksh|-zsh|-bash) return 0;; *) return 1;; esac
}

pane_cmd() {
  rex block call -s "$SESSION" -b "$1" process 2>/dev/null | jq -r '.foreground.name // empty'
}

# Screen + scrollback as text, soft-wrapped lines joined, trailing blanks dropped.
pane_text() {
  rex block call -s "$SESSION" -b "$1" format '{"format":"text","trim":true,"unwrap":true}' 2>/dev/null \
    | jq -r '.content // empty'
}

pane_tail() {
  local pane="$1" n="${2:-}"
  if [ -n "$n" ]; then pane_text "$pane" | tail -n "$n"; else pane_text "$pane"; fi
}

keys() { rex send-key -s "$SESSION" -b "$1" "${@:2}"; }

tmpdir() {
  local d="${TMPDIR:-/tmp}/rex-cmd.$$"
  mkdir -p "$d" && printf '%s' "$d"
}

require_pane() {
  local p; p=$(find_pane)
  [ -n "$p" ] || die "no command pane yet -- run 'rex-cmd.sh open' first"
  printf '%s' "$p"
}

# ---------------------------------------------------------------- open --------
cmd_open() {
  local dir="" size=40 dirn=right
  while [ $# -gt 0 ]; do
    case "$1" in
      -d) dir="$2"; shift 2;;
      -l) size="${2%\%}"; shift 2;;
      -v) dirn=below; shift;;
      *) die "open: unknown option $1";;
    esac
  done

  local p; p=$(find_pane)
  if [ -n "$p" ]; then printf '%s\n' "$p"; return 0; fi

  local args=(split -s "$SESSION" -b "$PARENT" --split="$dirn" --ratio "$size" --focus=false --label "$LABEL" --json)
  [ -n "$dir" ] && args+=(-c "$dir")
  p=$(rex "${args[@]}" | jq -r '.block_ids[0] // empty')
  [ -n "$p" ] || die "could not split the pane (is it too small?)"

  wait_for_shell "$p"
  inject_fns "$p"
  printf '%s\n' "$p"
}

# A fresh pane reports `login` until the shell has exec'd; typing before then
# loses the keystrokes.
wait_for_shell() {
  local i
  for i in $(seq 1 40); do
    is_shell "$(pane_cmd "$1")" && return 0
    sleep 0.25
  done
  die "pane never reached a shell prompt"
}

# Marker helpers live in the pane's shell so the visible command line stays
# readable: `__ccb <id>; <command>; __cce <id>` instead of two inline printfs.
# In __cce, $? is still the command's status because argument expansion happens
# before printf runs. `clear` hides the definition itself.
inject_fns() {
  local pane="$1"
  keys "$pane" ctrl+e ctrl+u
  # Markers print dimmed so they stay unobtrusive on screen; the escape codes
  # are not part of the text capture, so matching sees a bare marker.
  rex send -s "$SESSION" -b "$pane" -- '__ccb(){ printf "\n\033[2m@@B:%s@@\033[0m\n" "$1"; }; __cce(){ printf "\033[2m@@E:%s:%s@@\033[0m\n" "$1" "$?"; }; clear'
  keys "$pane" enter
}

# ----------------------------------------------------------------- run --------
# Wraps the command in unique begin/end markers printed by the pane's own shell,
# then polls the pane's scrollback until the end marker lands. The end marker
# carries the exit code, so nothing is inferred from output text.
cmd_run() {
  local timeout=120
  while [ $# -gt 0 ]; do
    case "$1" in
      -t) timeout="$2"; shift 2;;
      --) shift; break;;
      -*) die "run: unknown option $1";;
      *) break;;
    esac
  done
  [ $# -gt 0 ] || die "run: no command given"

  local pane; pane=$(find_pane)
  [ -n "$pane" ] || pane=$(cmd_open)   # "use the pane for everything" should not need a separate open
  local running; running=$(pane_cmd "$pane")
  is_shell "$running" || die "pane is running '$running', not a shell. Use 'send'/'key' to talk to it, or 'key ctrl+c' first."

  _exec_once "$pane" "$timeout" "$*"
  local st=$?
  # 125 means the pane lost the marker helpers (e.g. someone ran `exec bash`).
  # Re-inject and retry once -- safe, because a missing helper means the
  # command never ran.
  if [ "$st" -eq 125 ]; then
    inject_fns "$pane"
    _exec_once "$pane" "$timeout" "$*"
    st=$?
  fi
  return "$st"
}

_exec_once() {
  local pane="$1" timeout="$2" cmd="$3"
  local id="cc${RANDOM}${RANDOM}"
  local dir; dir=$(tmpdir)

  # Multi-line input cannot be typed safely line-by-line, so stage it as a
  # script. Env is inherited; shell functions and aliases are not.
  if [ "${cmd#*$'\n'}" != "$cmd" ]; then
    local script="$dir/$id.sh"
    printf '%s\n' "$cmd" > "$script"
    cmd="bash $script"
  fi

  # Clear whatever the user may have half-typed at the prompt.
  keys "$pane" ctrl+e ctrl+u
  rex send -s "$SESSION" -b "$pane" -- "__ccb ${id}; ${cmd}; __cce ${id}"
  keys "$pane" enter

  local snap="$dir/$id.txt"
  local deadline=$(( $(date +%s) + timeout )) done=0
  while :; do
    pane_text "$pane" > "$snap"
    [ -s "$snap" ] || die "pane disappeared while the command was running"
    if grep -qE "^@@E:${id}:[0-9]+@@$" "$snap"; then done=1; break; fi
    # Scoped to lines after this run's own typed line: a "command not found"
    # left in the scrollback by an earlier run must not trigger a false retry.
    if awk -v id="$id" '
         index($0, id) { seen = 1; next }
         seen && /__cc[be]/ && /not found/ { bad = 1 }
         END { exit(bad ? 0 : 1) }' "$snap"; then rm -f "$snap"; return 125; fi
    [ "$(date +%s)" -ge "$deadline" ] && break
    sleep 0.25
  done

  if [ "$done" -eq 0 ]; then
    printf -- '--- still running after %ss (pane %s) ---\n' "$timeout" "$pane"
    pane_tail "$pane" 40
    printf -- '--- it keeps running; interrupt with: rex-cmd.sh key ctrl+c ---\n'
    rm -f "$snap"
    return 124
  fi

  awk -v id="$id" '
    { L[NR] = $0 }
    END {
      for (i = NR; i >= 1; i--) if (L[i] ~ "^@@E:" id ":[0-9]+@@$") { e = i; break }
      for (i = e - 1; i >= 1; i--) if (L[i] == "@@B:" id "@@") { b = i; break }
      for (i = b + 1; i < e; i++) print L[i]
    }' "$snap"

  local rc; rc=$(grep -oE "^@@E:${id}:[0-9]+@@$" "$snap" | tail -1 | sed -E "s/^@@E:${id}:([0-9]+)@@$/\1/")
  printf -- '--- exit %s ---\n' "$rc"
  rm -f "$snap" "$dir/$id.sh"
  return "$rc"
}

# ------------------------------------------------------- send / key -----------
cmd_send() {
  [ $# -gt 0 ] || die "send: no text given"
  local pane; pane=$(require_pane)
  rex send -s "$SESSION" -b "$pane" -- "$*"
  keys "$pane" enter
}

cmd_key() {
  [ $# -gt 0 ] || die "key: no key given"
  local pane; pane=$(require_pane)
  keys "$pane" "$@"
}

# -------------------------------------------------------------- capture ------
cmd_capture() {
  local lines=60 all=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -n) lines="$2"; shift 2;;
      -a) all=1; shift;;
      *) die "capture: unknown option $1";;
    esac
  done
  local pane; pane=$(require_pane)
  if [ "$all" -eq 1 ]; then pane_tail "$pane"
  else pane_tail "$pane" "$lines"
  fi
}

# --------------------------------------------------------------- status ------
cmd_status() {
  local p; p=$(find_pane)
  if [ -z "$p" ]; then echo "no command pane"; return 1; fi
  local size proc
  size=$(rex block call -s "$SESSION" -b "$p" size 2>/dev/null | jq -r '"\(.columns)x\(.rows)"')
  proc=$(rex block call -s "$SESSION" -b "$p" process 2>/dev/null)
  printf 'pane=%s running=%s size=%s cwd=%s\n' "$p" \
    "$(jq -r '.foreground.name // empty' <<<"$proc")" "$size" "$(jq -r '.foreground.cwd // empty' <<<"$proc")"
}

cmd_close() {
  local p; p=$(find_pane)
  [ -n "$p" ] || { echo "no command pane"; return 0; }
  rex block close -s "$SESSION" "$p" && echo "closed $p"
}

# ------------------------------------------------------------------ main -----
sub="${1:-}"; [ $# -gt 0 ] && shift
case "$sub" in
  open)    cmd_open "$@";;
  id)      find_pane; echo;;
  status)  cmd_status;;
  run)     cmd_run "$@";;
  send)    cmd_send "$@";;
  key)     cmd_key "$@";;
  capture) cmd_capture "$@";;
  close)   cmd_close;;
  *) die "usage: rex-cmd.sh {open|id|status|run|send|key|capture|close} [args]";;
esac
