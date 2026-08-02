#!/usr/bin/env bash
# tmux-cmd -- drive a sibling tmux pane next to the Claude CLI.
#
# The pane is a real TTY: interactive programs, colours, REPLs and pagers all
# behave normally, and the user watches every command as it runs.
#
# Usage:
#   tmux-cmd.sh open   [-d DIR] [-l SIZE] [-v]   create/reuse the pane, print its id
#   tmux-cmd.sh id                               print the pane id ("" if none)
#   tmux-cmd.sh status                           pane id + what is running in it
#   tmux-cmd.sh run    [-t SECS] <command...>    run, wait, print output + exit code
#   tmux-cmd.sh send   <text...>                 type text + Enter, do not wait
#   tmux-cmd.sh key    <key>...                  send key names (C-c, Up, Enter, q)
#   tmux-cmd.sh capture [-n LINES] [-a]          dump what the pane shows
#   tmux-cmd.sh close                            kill the pane
#
# `run` is for shell commands you need the result of.
# `send`/`key`/`capture` are for interactive programs already running in the pane.

set -uo pipefail

TAG=@claude_cmd_pane

die() { printf 'tmux-cmd: %s\n' "$*" >&2; exit 1; }

[ -n "${TMUX:-}" ] || die "not inside tmux (\$TMUX is unset). Start Claude inside a tmux session."
command -v tmux >/dev/null || die "tmux not found on PATH"

# The pane Claude itself lives in. Panes are tagged with it so several Claude
# sessions in the same server never steal each other's command pane.
parent_pane() {
  if [ -n "${TMUX_PANE:-}" ]; then printf '%s' "$TMUX_PANE"
  else tmux display-message -p '#{pane_id}'
  fi
}
PARENT=$(parent_pane)

# An explicit separator matters: untagged panes emit an empty first field, and
# awk's default splitting would collapse it and shift pane_id into $1.
find_pane() {
  tmux list-panes -a -F '#{'"$TAG"'}|#{pane_id}' 2>/dev/null \
    | awk -F'|' -v p="$PARENT" '$1 == p { print $2; exit }'
}

pane_alive() {
  [ -n "${1:-}" ] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx -- "$1"
}

require_pane() {
  local p; p=$(find_pane)
  pane_alive "$p" || die "no command pane yet -- run 'tmux-cmd.sh open' first"
  printf '%s' "$p"
}

# Programs we treat as "a shell sitting at a prompt". Anything else means an
# interactive program owns the pane and `run` would type into it instead.
is_shell() {
  case "$1" in zsh|bash|sh|fish|dash|ksh|-zsh|-bash) return 0;; *) return 1;; esac
}

# capture-pane's -S only moves the start line; the end stays at the bottom of
# the screen, so a bare -S -N returns N + pane_height lines. Drop the blank
# padding a partly-filled pane leaves behind, then take the real tail.
pane_tail() {
  local pane="$1" n="${2:-}"
  local out
  out=$(tmux capture-pane -p -J -S - -t "$pane" \
    | awk '{ L[NR]=$0 } END { last=0; for (i=1;i<=NR;i++) if (L[i] ~ /[^ \t]/) last=i; for (i=1;i<=last;i++) print L[i] }')
  if [ -n "$n" ]; then printf '%s\n' "$out" | tail -n "$n"; else printf '%s\n' "$out"; fi
}

tmpdir() {
  local d="${TMPDIR:-/tmp}/tmux-cmd.$$"
  mkdir -p "$d" && printf '%s' "$d"
}

# ---------------------------------------------------------------- open --------
cmd_open() {
  local dir="" size="40%" split="-h"
  while [ $# -gt 0 ]; do
    case "$1" in
      -d) dir="$2"; shift 2;;
      -l) size="$2"; shift 2;;
      -v) split="-v"; shift;;
      *) die "open: unknown option $1";;
    esac
  done

  local p; p=$(find_pane)
  if pane_alive "$p"; then printf '%s\n' "$p"; return 0; fi

  local args=(split-window "$split" -d -l "$size" -P -F '#{pane_id}' -t "$PARENT")
  [ -n "$dir" ] && args+=(-c "$dir")
  p=$(tmux "${args[@]}") || die "could not split the window (is it too small?)"

  tmux set-option -p -t "$p" "$TAG" "$PARENT"
  tmux select-pane -t "$p" -T "claude-cmd"
  inject_fns "$p"
  printf '%s\n' "$p"
}

# Marker helpers live in the pane's shell so the visible command line stays
# readable: `__ccb id; <command>; __cce id` instead of two inline printfs.
# In __cce, $? is still the command's status because argument expansion happens
# before printf runs. `clear` hides the definition itself.
inject_fns() {
  local pane="$1"
  tmux send-keys -t "$pane" C-e C-u
  # Markers print dimmed so they stay unobtrusive on screen. capture-pane
  # without -e drops the escape codes, so matching still sees a bare marker.
  tmux send-keys -t "$pane" -l -- '__ccb(){ printf "\n\033[2m@@B:%s@@\033[0m\n" "$1"; }; __cce(){ printf "\033[2m@@E:%s:%s@@\033[0m\n" "$1" "$?"; }; clear'
  tmux send-keys -t "$pane" Enter
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
  pane_alive "$pane" || pane=$(cmd_open)   # "use the pane for everything" should not need a separate open
  local running; running=$(tmux display-message -p -t "$pane" '#{pane_current_command}')
  is_shell "$running" || die "pane is running '$running', not a shell. Use 'send'/'key' to talk to it, or 'key C-c' first."

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
  tmux send-keys -t "$pane" C-e C-u
  tmux send-keys -t "$pane" -l -- "__ccb ${id}; ${cmd}; __cce ${id}"
  tmux send-keys -t "$pane" Enter

  local snap="$dir/$id.txt"
  local deadline=$(( $(date +%s) + timeout )) done=0
  while :; do
    tmux capture-pane -p -J -S - -t "$pane" > "$snap" 2>/dev/null || die "pane disappeared while the command was running"
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
    printf -- '--- it keeps running; interrupt with: tmux-cmd.sh key C-c ---\n'
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
  tmux send-keys -t "$pane" -l -- "$*"
  tmux send-keys -t "$pane" Enter
}

cmd_key() {
  [ $# -gt 0 ] || die "key: no key given"
  local pane; pane=$(require_pane)
  tmux send-keys -t "$pane" "$@"
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
  if ! pane_alive "$p"; then echo "no command pane"; return 1; fi
  tmux display-message -p -t "$p" 'pane=#{pane_id} running=#{pane_current_command} size=#{pane_width}x#{pane_height} cwd=#{pane_current_path}'
}

cmd_close() {
  local p; p=$(find_pane)
  pane_alive "$p" || { echo "no command pane"; return 0; }
  tmux kill-pane -t "$p" && echo "closed $p"
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
  *) die "usage: tmux-cmd.sh {open|id|status|run|send|key|capture|close} [args]";;
esac
