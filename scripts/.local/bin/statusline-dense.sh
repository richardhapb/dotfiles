#!/bin/sh
# Claude Code status line — single dense line for AI engineering.
# Layout: <dir> · <branch*> · ctx NN% · +A/-R · $cost · Model(effort)
# Color discipline: whole line is dim gray; color appears ONLY as a context
# alert (yellow >=80% used, red >=90%). Color = signal, not decoration.
input=$(cat)

DIM='\033[90m'      # dim gray for everything non-alert
RST='\033[0m'
sep="${DIM} · ${RST}"

# --- Directory: basename only (shell prompt usually already shows full cwd) ---
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "$cwd" 2>/dev/null)

# --- Git: branch (prefer worktree JSON) + '*' when working tree is dirty ------
branch=$(echo "$input" | jq -r '.worktree.branch // empty')
[ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
git_seg=""
if [ -n "$branch" ]; then
  dirty=""
  if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
    dirty="*"
  fi
  git_seg="${branch}${dirty}"
fi

# --- Context window: USED %, the only segment that can light up --------------
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
ctx_seg=""
if [ -n "$used" ] || [ -n "$remaining" ]; then
  ctx_seg=$(awk -v u="$used" -v r="$remaining" -v dim="$DIM" -v rst="$RST" 'BEGIN{
    if(u=="" && r=="") exit;
    if(u=="") u=100-r;
    ui=int(u+0.5);
    if(ui>=90)      col="\033[31m";  # red:    critical
    else if(ui>=80) col="\033[33m";  # yellow: getting full
    else            col=dim;         # gray:   plenty of runway
    printf "%sctx %d%%%s", col, ui, rst;
  }')
fi

# --- Lines changed this session (only when nonzero) --------------------------
added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
lines_seg=""
if [ "$added" != "0" ] || [ "$removed" != "0" ]; then
  lines_seg="+${added}/-${removed}"
fi

# --- Session cost (only when nonzero) ----------------------------------------
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
cost_seg=""
if [ -n "$cost" ]; then
  cost_seg=$(awk -v c="$cost" 'BEGIN{ if(c+0>0) printf "$%.2f", c }')
fi

# --- Model + effort, spaces stripped: "Opus4.8(high)" ------------------------
model=$(echo "$input" | jq -r '.model.display_name // empty' | tr -d ' ')
effort=$(echo "$input" | jq -r '.effort.level // empty')
model_seg=""
[ -n "$model" ]  && model_seg="$model"
[ -n "$effort" ] && model_seg="${model_seg}(${effort})"

# --- Assemble: join non-empty segments with the dim separator ----------------
line=""
for seg in "$dir" "$git_seg" "$ctx_seg" "$lines_seg" "$cost_seg" "$model_seg"; do
  [ -z "$seg" ] && continue
  if [ -z "$line" ]; then
    line="$seg"
  else
    line="${line}${sep}${seg}"
  fi
done

# Wrap the whole line in dim gray so non-alert text recedes; the ctx segment
# carries its own color reset, so its alert color survives.
printf "${DIM}%b${RST}" "$line"
