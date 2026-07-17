#!/usr/bin/env bash
# PreToolUse (Bash) hook: gate push / PR-create commands by repo ownership.
# - Own repo (origin owner == $OWNER): allow without prompting.
# - Anything else (other owner, no remote, not a repo): ask for permission.
# - Force-push: always deny; Richard runs those himself.
# Non-push commands exit silently (normal permission flow applies).

OWNER="richardhapb"

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0

# Only care about push / PR / MR creation commands
if ! printf '%s' "$cmd" | grep -qE '(^|[[:space:]&;|(])(git[[:space:]]+push|(rtk[[:space:]]+)?gh[[:space:]]+pr[[:space:]]+create|(rtk[[:space:]]+)?glab[[:space:]]+mr[[:space:]]+create)([[:space:]]|$)'; then
  exit 0
fi

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}' "$1" "$2"
}

# Force-push is always denied, own repo or not
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push[^&;|]*([[:space:]]--force(-with-lease)?([[:space:]=]|$)|[[:space:]]-f([[:space:]]|$))'; then
  emit deny "Force-push is reserved for Richard. Finish all prep (commit, rebase, fetch, verify the lease), then STOP and ask him to run the force-push himself; do not run it."
  exit 0
fi

# Resolve the repo owner from origin in the command's cwd
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null
url=$(git remote get-url origin 2>/dev/null || true)

# Extract "<owner>" from git@host:owner/repo.git, ssh://git@host/owner/repo.git,
# or https://host/owner/repo.git
owner=$(printf '%s' "$url" | sed -E 's#^(git@[^:]+:|(ssh|https?)://[^/]+/)([^/]+)/.*#\3#;t;d')

if [ "$owner" = "$OWNER" ]; then
  emit allow "Push to Richard's own repo ($url)"
else
  emit ask "Repo origin is '${url:-none}' (owner '${owner:-unknown}', not $OWNER) -- confirm before pushing."
fi
