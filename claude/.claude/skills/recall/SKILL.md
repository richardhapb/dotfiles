---
name: recall
description: Recover a fact, name, or decision from an earlier Claude Code session by searching the local transcripts under ~/.claude/projects/**/*.jsonl, then verifying the answer against the live source before reporting it. Use when the user says "where did we talk about X", "what was the name of that flag/table/method we discussed", "we agreed on something about X, find it", or otherwise references prior work this session has no context for. Skip when the answer is plainly in the current repo -- grep the code directly.
---

# Recall from prior sessions

Every Claude Code session is written to disk as JSONL. That archive is a searchable record of what was discussed, decided, and looked at. Use it to answer "what did we say about X" -- but never ship a transcript quote as the final answer. Transcripts record what was true *then*; the repo records what is true *now*.

## The two-phase rule

1. **Locate** -- find the term in transcripts. Cheap, fuzzy, high recall.
2. **Verify** -- confirm it in the source of truth (repo, Jira, GitLab, Omni). Report the verified value and cite `file:line`.

If phase 2 contradicts phase 1, the source of truth wins and you say the earlier discussion is stale. If phase 1 finds nothing, say so -- do not reconstruct a plausible-looking name from memory.

## Layout

```
~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl        # main session
~/.claude/projects/<encoded-cwd>/<session-uuid>/subagents/*.jsonl  # subagent transcripts
```

`<encoded-cwd>` is the working directory with `/` replaced by `-`, e.g. `-Users-richard-dev-server`. Worktrees and branch-named checkouts get their own dirs -- `...-dev-server-rpb-TICKET-307-operator-settings-table` -- so the directory listing alone is a useful index of what was worked on and when.

Each line is one JSON object. The ones that matter: `type` (`user` / `assistant`), `message.content` (string or content-block array), `timestamp`, `cwd`, `gitBranch`, `sessionId`. Tool results live under `toolUseResult` / `tool_result` blocks -- that's where file contents and command output got captured, and often where the answer actually is.

Related stores worth checking when transcripts come up dry: the session memory dir (`~/.claude/projects/<encoded-cwd>/memory/MEMORY.md`), handoffs (`~/handoffs/<hash>/`), and notes (`sapere` / `heramty` skills).

## Phase 1 -- locate

**Step 1. Scope.** Pick the project dirs by name before grepping. A recursive grep over all of `~/.claude/projects` takes minutes and will time out.

```bash
ls -d ~/.claude/projects/*/ | grep -i checkr
```

**Step 2. Vocabulary mining.** You usually don't know the exact identifier -- that's the whole reason for the search. Mine it instead of guessing: pull every token matching a shape and rank by frequency.

```bash
cd ~/.claude/projects
grep -rhoiE "[a-z0-9_.-]{0,30}(screening_settings|screening_config)[a-z0-9_.-]{0,40}" \
  --include='*.jsonl' ./-Users-<user>-<dirs-separated-by-hyphen> \
  | tr 'A-Z' 'a-z' | sort | uniq -c | sort -rn | head -40
```

The frequency ranking is the signal: real identifiers appear hundreds of times, one-off prose appears once. This is how you go from "something about screening configs" to `operator_screening_settings`, `ScreeningSettingsFactory.operator_only_options`, `packages_operator_screening_settings_spec.rb`.

**Step 3. Which sessions.** Once you have a concrete token, list the files that carry it:

```bash
grep -rl --include='*.jsonl' 'EXTERNAL_EDITABLE_PACKAGES' ~/.claude/projects
```

**Step 4. Which of those sessions.** Print a header per candidate -- date, branch, first real prompt -- to pick the right one:

```bash
for f in $(grep -rl --include='*.jsonl' 'EXTERNAL_EDITABLE_PACKAGES' . ); do
  jq -rR --arg f "$f" 'fromjson? // empty
    | select(.type=="user" and (.isMeta|not))
    | select(.message.content | type=="string" and (test("^<")|not))
    | "\($f)  \(.timestamp[0:10])  \(.gitBranch // "-")  \(.message.content[0:80]|gsub("\n";" "))"' "$f" | head -1
done
```

**Step 5. Read the surrounding text.** Fixed-width windows around the match beat reading whole 20MB transcripts:

```bash
grep -roh --include='*.jsonl' ".\{200\}external_editable_packages.\{250\}" <session>.jsonl | sort -u | head -10
```

Prose written *by you or the user* is the highest-value hit -- it carries the reasoning, not just the code. Tool-result hits carry the code.

To read a session as a conversation instead of raw JSON:

```bash
jq -rR 'fromjson? // empty | select(.type=="user" or .type=="assistant")
  | "\(.type): \(.message.content | if type=="string" then . else map(select(.type=="text").text) | join("") end)"' \
  <session>.jsonl | head -200
```

## Phase 2 -- verify

Take the identifier back to the live source and confirm it still exists with the same value:

```bash
grep -rn "EXTERNAL_EDITABLE_PACKAGES_FLAG_ID *=" --include='*.rb' ~/dev/checkr
```

Then read the call sites, not just the definition -- an answer like "flag 609 gates it" is incomplete if the guard is `flag AND account.add_ons.enabled`. The user asked for the flag; they need the condition that actually governs.

For non-code claims, verify against the system of record: Jira (`Atlassian` MCP), GitLab (`glab`), data questions (Omni MCP -- never invent numbers), other repos (`sourcegraph` skill).

## Report

- Lead with the answer -- the name, the value -- in the first line.
- Cite `file:line` from the **verified** source, not from the transcript.
- Add the caveats the earlier discussion surfaced that the code alone doesn't show (the AND-gate, the sibling internal flag, a decision that was reversed later).
- If the transcript and the repo disagree, say which is stale.
- If nothing was found: say that plainly and offer the next place to look. Never fabricate an identifier.

## Gotchas

| Symptom | Cause / fix |
|---|---|
| `no matches found: --include=*.jsonl` | zsh globs the flag. Quote it: `--include='*.jsonl'`. |
| `grep: maximum repetition exceeds 255` | `.\{300\}` is over BSD grep's cap. Use `.\{250\}` or less. |
| Command times out at 120s | Recursive grep over all of `~/.claude/projects`. Scope to specific project dirs first. |
| `jq: parse error: Invalid numeric literal` | Not every line is well-formed JSON. Always use `jq -rR 'fromjson? // empty'`. |
| Huge blob dumped into context | A transcript line can be megabytes. Never `cat` one; use `grep -o` windows or `jq` projections. |
| Match found only in an `<system-reminder>` or skill description | That's the skill catalogue echoing, not a real discussion. Ignore it. |
| Hit is in the *current* session's transcript | Your own live session is on disk too. Harmless, but don't cite yourself as evidence. |
