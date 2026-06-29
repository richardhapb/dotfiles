---
name: heramty
description: "Use when Richard asks to find, read, list, create, or update notes in HeraMty; also use proactively when saving findings, summaries, and references with the `hmt` CLI."
version: 1.0.0
author: Richard / Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [notes, heramty, hmt, markdown, knowledge-management]
    related_skills: [obsidian]
---

# HeraMty

HeraMty is Richard's personal notes app. Hierarchy: **Wall → Board → Note** (markdown). Interact with it via the `hmt` CLI (already auth'd). On this Hermes host, prefer `/home/ubuntu/bin/hmt`, which is a symlink to `/home/ubuntu/.hermes/bin/hmt`. Older notes may mention `/home/ubuntu/.hermes/hermes-agent/bin/hmt`, but that path may not exist in the active checkout. When fixing jobs or scripts, either call `/home/ubuntu/bin/hmt` explicitly or resolve `command -v hmt` / the active Hermes binary path before retrying. This skill captures Richard's conventions for using HeraMty from Hermes.

## When to suggest saving

Proactively offer to save into HeraMty when:

- Richard finishes a research/learning session ("now I get how X works") — propose a Sapere aude note.
- A debugging session produces a non-obvious answer worth keeping — propose a Sapere aude or Checkr note.
- An MR review, ticket triage, or Slack thread produces a short reusable summary — propose `Checkr/random` (transient) or `Checkr/<existing board>` (durable).
- Richard pastes a long external doc or article we just discussed — propose saving a TL;DR with a link back, not the whole thing.

Do **not** offer:
- After trivial one-shot commands or boilerplate work.
- When the answer is already documented somewhere we just read.
- More than once per conversation unless Richard signals interest.

Phrase it as a single short line: *"Want this saved to HeraMty? I'd put it in `Sapere aude / Postgres` as 'B-tree vs. GiST for jsonb'."* — naming the wall, board, and title up front so it's one decision, not three.

## Walls

Walls change rarely. The table below is the working set as of skill creation — treat it as a hint, not the truth. Run `hmt walls list` at the start of any HeraMty session to refresh, especially before suggesting a wall by name.

| Wall          | Purpose                                                         | Default? |
|---------------|-----------------------------------------------------------------|----------|
| General       | System wall. Unclassified / Inbox catch-all.                    | fallback |
| Sapere aude   | Learning / research. Permanent reference material.              | learning |
| Checkr        | Work. Projects, tickets, people, scrum, ad-hoc.                 | work     |
| Projects      | Personal projects (non-work).                                   |          |
| Business      | Business / financial / admin stuff.                             |          |
| Books         | Book notes / reading.                                           |          |
| Log           | Journal-like running log.                                       |          |
| Random        | Personal random / scratch.                                      | scratch  |

**Wall picker (decision order):**
1. Work / Checkr-related → `Checkr`
2. Learning, technical reference, "how does X work" → `Sapere aude`
3. Doesn't fit anywhere else → `General` (lands in `Inbox`)
4. Truly transient / scratch → `Random` (or `Checkr/random` if work-flavored)

**Important distinction:** when Richard says "write this down" after a conceptual explanation, design guidance, study plan, or reusable technical lesson, treat it as durable knowledge and save it under `Sapere aude`, even if the topic came from today's work. Use `Log` only for journal-like daily discoveries or explicit "log this" requests. If the content is both work-related and broadly reusable (e.g. Temporal design rules learned through a Checkr task), prefer `Sapere aude` over `Checkr`/`Log`.

Creating a new wall is rare — only when a whole new life-area appears. Ask first.

## Boards — always discover live

Boards change often. **Never assume a board exists** — always run `hmt boards list --wall <wall-id>` first and pick from the live result. Do not hardcode board names in this skill or in conversation memory; the list above the wall picker is the only stable thing.

Heuristics for picking among the boards you find:

- An existing board with a name that matches the topic → use it.
- Nothing matches and the content is reference-grade → suggest creating a new board with a short name (one or two words, lowercase for scratch / Title Case for areas).
- Nothing matches and the content is transient → drop in `random` if the wall has one, otherwise propose creating `random`.
- The default landing for unclassified stuff inside any wall is the system `Inbox` (only present in `General`); for non-system walls, prefer `random` over creating a new board for one-off items.

`random` (when it exists in a wall) is the home for: Slack message prototypes, MR review summaries, tool outputs to triage, anything that doesn't need to become a durable reference. Inside `Checkr` this is the most common destination for work-flavored ephemera.

**Naming new boards:** short, 1–4 words, ~40–90 chars max. One concern per board (a support-ticket queue, a project, a technology). Ask before creating.

## Notes — content style

- **Atomic.** One note = one topic. If you find yourself writing "and also…", that's a second note.
- **TL;DR up top** when the body is longer than ~10 lines. One or two sentences capturing the takeaway.
- **Markdown.** Headings, fenced code blocks, lists, links — all supported. Embedded images work but you usually won't have one in a CLI flow.
- **Reference other notes by title** in prose. Don't fabricate IDs.
- **Title is the index.** Make it searchable: "B-tree vs. GiST on jsonb" beats "indexing".
- **Source links.** If the content came from an MR, ticket, Slack thread, or external doc — paste the URL near the top.

Don't:
- Paste massive untrimmed transcripts. Summarize.
- Save half-formed thoughts unless explicitly asked.
- Repeat what Richard can re-derive from `git log` / a ticket / public docs.

## Richard-specific recurring notes

- TODOs belong in HeraMty. Treat `General / Lists / TODO` as the canonical task list unless Richard explicitly names another target. When Richard sends `TODO: ...`, append unchecked markdown tasks there by default. Richard has authorized Hermes to manage this list and remove already completed `- [x]` lines to keep it clean. Fetch the live note first, preserve active `- [ ]` tasks, avoid duplicates, update via `hmt notes update ... --file <path>`, then read it back to verify.
- When Richard asks to manage or clean his lists, inspect all notes under `General / Lists`, not just `TODO`. Resolve conflicts actively: delete stale conflict notes containing only completed tasks, delete list notes where every checklist item is completed, merge duplicate actionable items across `TODO` and topical lists (keep the action in `TODO`, preserve useful specificity), then `hmt sync pull --dir /home/ubuntu/hmt-vault --board <lists-board-id>` so the local vault mirrors the live state. See `references/todo-list-hygiene.md`.
- When Richard asks why HeraMty desktop has stale notes, conflict copies, or "realtime" inconsistencies, inspect the desktop/offline sync path before guessing. In the inspected architecture the desktop app used a local SQLite replica behind a loopback API and a 30s sync loop, so remote writes from CLI/Hermes/web can race stale desktop edits and produce `(<title> conflict <date>)` copies via optimistic-lock rejection. See `references/desktop-sync-conflicts.md` for evidence and fix directions.
- Active subscriptions belong in HeraMty, not Finitum, unless Richard explicitly asks for database-backed finance work. Current note: `Business / General` → `Active subscriptions` (`5d576862-8c26-418c-954c-a3495713deff`). When updating it, fetch the existing note first, preserve manual/TBD entries, enrich with evidence from finance data if needed, then use `hmt notes update ... --file <path>`.
- If subscription evidence comes from Finitum or another database, read-only queries are fine for investigation, but **never** create/update/delete DB records for subscription tracking without Richard's explicit confirmation. For the active subscription list, HeraMty is the source of truth.
- English learning corrections belong in `Sapere aude / english idiomatic`. Use this board for Richard's English mistakes, idiomatic phrasing, pattern summaries, and micro-drills. For scheduled correction reviews, combine two fresh sources: (1) the RPi corrections API (`http://rpi:9000/corrections`) incrementally by timestamp and (2) HeraMty note excerpts changed since the last run from `~/hmt-vault/.hmt/index.json`. The corrections API comes from Richard's clipboard app, neospeller, and may contain Slack messages, note text, or random daily writing; keep unrelated contexts separate and avoid overfitting when context is missing. Do not re-read the whole notes vault; cap changed-note excerpts.
- If an English review reports `Clipboard corrections: 0` but Richard says he used the correction endpoint/app, verify the corrections API directly before trusting the cron output. Probe both a bounded cron window (`from`/`to`) and an unbounded/latest query (`/corrections?limit=5`). If unbounded data exists but the latest `created_at` is old, the cron is probably fine and the write path/backing store is stale or divergent; inspect neospeller/write-side config next. If the local rsynced `localserver-go` tree lacks the deployed `/corrections` route, do not assume the mirror is authoritative — request temporary `rpi`/`mac` access and inspect the deployed service/binary/logs/read-write source on the hosts.

## Workflow

### 1. Confirm with a one-line draft

Before any write, show:

```
HeraMty draft → Sapere aude / Postgres
Title: B-tree vs. GiST for jsonb containment queries
Body (preview):
  TL;DR: use GIN with jsonb_path_ops for @> ...
```

Then create on a "yes". If Richard suggests edits, redraft once before creating.

**Exception:** when Richard explicitly asks to create/save/update a note in a specific HeraMty location (for example "create this under Projects / Swarm"), treat that as authorization. Do the duplicate search and target lookup, write the note, then read it back to verify. Do not add a redundant confirmation gate unless the target/content is ambiguous or the operation is destructive.

### 2. Search before creating

Run `hmt notes search "<key phrase>"` for a likely duplicate. If a near-match exists, propose **updating** that note instead of creating a new one. Show the match in the draft.

### 3. Find target IDs

Walls: `hmt walls list` then `jq '.[] | select(.name=="Sapere aude") | .id'`.
Boards: `hmt boards list --wall <wall-id>`.

Cache them in the conversation; don't relist every command.

### 4. Write

Note content is supplied via the `--file <PATH>` flag (or `--file -` for stdin, which is the default if `--file` is omitted). **There is no positional content argument** — passing the file path positionally will fail with `unexpected argument`.

Correct forms:

```bash
# from an existing file on disk
hmt notes create --board <board-id> --title "<title>" --file ~/path/to/note.md

# from stdin (heredoc keeps markdown readable in chat history)
hmt notes create --board <board-id> --title "<title>" <<'EOF'
TL;DR: ...

## Detail
...
EOF

# from stdin via pipe — explicit `--file -` is optional, it's the default
printf '%s\n' "TL;DR: ..." "" "## Detail" "..." \
  | hmt notes create --board <board-id> --title "<title>"
```

For multi-paragraph notes, prefer a heredoc or an existing file (e.g. `~/.claude/skills/<name>/SKILL.md`) over `printf` chains — the markdown stays legible.

Update follows the same `--file` convention:

```bash
hmt notes update <note-id> --title "<title>" --file ~/path/to/note.md
```

`hmt notes update` re-reads the note to handle optimistic locking automatically — you don't manage `updated_at` by hand.

If you ever get `unexpected argument 'X' found` from `notes create`/`update`, you almost certainly passed the body positionally — re-run with `--file <path>`.

### 5. Echo the result

After creating, print the resulting note's title + the wall/board path. Don't dump the full JSON unless asked.

## Reading / searching

- `hmt notes search "<query>"` — full-text, top 20, ranked. Use this first.
- `hmt notes list --board <board-id>` — when Richard wants to browse a board.
- `hmt notes get <id>` — full content; pipe to `glow`/`bat` if Richard wants it rendered.

## Quick reference

```bash
hmt walls list
hmt walls create "<name>"
hmt boards list --wall <wall-id>
hmt boards create --wall <wall-id> "<name>"

hmt notes search "<q>"
hmt notes list --board <board-id>
hmt notes get <id>

# Notes — content comes from --file <path> (default `-` = stdin). Never positional.
hmt notes create --board <board-id> --title "<title>" --file <path>
hmt notes update <note-id>          --title "<title>" --file <path>
hmt notes create --board <board-id> --title "<title>"  # body on stdin (heredoc or pipe)
hmt notes move <id> --board <other-board-id>
hmt notes delete <id>
```

The HeraMty MCP server also exposes create tools when the active Hermes session has loaded a recent `heramty-mcp` binary:

```text
mcp_heramty_create_wall(name)
mcp_heramty_create_board(wall_id, name)
mcp_heramty_create_note(board_id, title, content)
```

If the installed MCP binary was just updated, restart Hermes/gateway or start a new session before expecting new MCP tools to appear in the tool catalog. The MCP stdio server can be smoke-tested independently with `initialize` → `notifications/initialized` → `tools/list`; verify `create_wall`, `create_board`, and `create_note` are present before claiming the session can call them.

All writes inject `Idempotency-Key` automatically; safe to retry.

## Curl / REST fallback

If Richard explicitly says to use `curl`, treat that as a workflow correction and use the REST API directly instead of insisting on the CLI. Keep tokens out of chat/logs and do not bypass agent security guardrails if authenticated curl is blocked. See `references/curl-api.md` for the compact API/curl playbook.

## Wall semantics for Richard

For review/synthesis jobs, treat the major walls as distinct signal sources:

### Project-specific agent/profile bootstrapping

When Richard asks to create or tune a specialized agent for a project, use HeraMty as the project context source before writing the profile/persona. For Massbee-like project agents: read the relevant `Projects / <board>` notes, identify the durable big-picture, bottlenecks, operating loop, and source-of-truth constraints, then encode those into the profile/SOUL as actionable behavior. Do not just create a vibe/personality; make the agent inspect HeraMty/repo state, synthesize one concrete next action, and define “done” with evidence.


- `Sapere aude` = Richard's durable knowledge base. Mine it for connections, suggestions, learning gaps, reusable concepts, and reference-grade synthesis. It is not merely an output bucket.
- `Log` = daily discoveries / things Richard found each day. This is the primary fresh-signal feed for daily reviews.
- `Checkr` = work-related material. This is the primary work feed for programmer-growth, workplace-pattern, and opportunity signals.
- `General / Inbox` = Richard's quick-note drafts. Scheduled daily reviews must include this board as a triage source: suggest where drafts should move, but treat them as drafts until Richard confirms.

When building scheduled or recurring HeraMty analysis, prioritize fresh changes from `Log`, `Checkr`, and `General / Inbox`, then connect them against `Sapere aude` to suggest what to summarize, build, write, move, or improve. Only write summaries into `Sapere aude` when the item is genuinely durable knowledge; do not pollute it with daily-log debris.

**Recurring review pitfall:** do not trust local vault/index diffs as the primary freshness signal for `Log` / `Checkr` reviews. Richard may have live notes that a local sync/index misses, and a false "nothing changed" report is worse than no report. For scheduled reviews, use a fast deterministic collector that calls live `hmt walls list`, `hmt boards list --wall`, `hmt notes list --board`, and `hmt notes get`, then pass that JSON into a normal agent cron job for reasoning. Keep script-only cron jobs deterministic; do not nest a full `hermes chat` inside them for general daily HeraMty synthesis. See `references/recurring-review-jobs.md`.

**Review-window rule:** Richard wants the daily HeraMty review to inspect the last **24 hours**, not 36; 36 creates overlapping daily reports. When changing this window, update both the collector constant (for example `LOOKBACK_HOURS`) and the cron job prompt/documentation so the agent explanation matches the actual payload. Verify the active cron job references the current collector script, not any legacy nested-Hermes wrapper left in `~/.hermes/scripts/`.

**Cron `hmt` path pitfall:** HeraMty cron jobs may run with a sparse PATH. If a job fails because it cannot find `hmt`, do not paper over it with PATH guessing. Use the project-local Hermes binary path (`/home/ubuntu/.hermes/hermes-agent/bin/hmt` in the default profile) or derive it from the active Hermes checkout, patch the script/job, then retry the job to verify the fix.

**Stateful review verification:** cron `last_status: ok` is not enough. For jobs that advance a timestamp state file or update a HeraMty note, verify the whole chain: read the cron output, inspect the script/config, run a narrow dry verification of the data sources, and fetch the live destination note/board to prove the write landed. If a manual run can advance state or update today's note, snapshot/understand the state first and repair/advance it deliberately afterward so the next scheduled run does not replay the same window. See `references/recurring-review-jobs.md`.

**Cursor-stealing safeguard:** for recurring jobs that invoke a nested agent to write/update a HeraMty note and then advance a timestamp cursor, do not trust nested stdout as proof of success. Snapshot the intended destination note before the nested run, fetch it again after, and advance state only if the note was created or its `version`/`updated_at` changed. If the destination did not change, emit an explicit safeguard failure and leave the cursor untouched so the window can be retried. See `references/recurring-review-safeguards.md`.

## Local vault sync (`hmt sync`)

Use this when Richard wants to work on a wall/board as plain markdown files (read in an editor, grep across notes, batch-edit, hand to another tool, etc.) instead of one-shot CLI writes.

Layout produced by sync: `<vault>/<wall>/<board>/<note>.md`, with IDs / last-known content hashes / `updated_at` tracked in `<vault>/.hmt/index.json`.

```bash
# Clone or refresh
hmt sync pull --dir ./vault                       # everything Richard owns
hmt sync pull --dir ./vault --wall  <wall-id>     # one wall
hmt sync pull --dir ./vault --board <board-id>    # one board
hmt sync pull --dir ./vault --force               # overwrite local edits

# Push local changes back
hmt sync push --dir ./vault --dry-run             # preview (no server calls for writes)
hmt sync push --dir ./vault                       # update/create/rename/delete
hmt sync push --dir ./vault --board <board-id>    # scope to one board
hmt sync push --dir ./vault --force               # ignore updated_at conflicts
```

Push semantics:

- **update** — file's SHA changed vs. the index → `PUT /notes/{id}`. Title is left at the indexed value (filenames don't round-trip perfectly through sanitization).
- **create** — new `.md` in an existing `<wall>/<board>/` dir → `POST /notes`. Filename (minus `.md`) becomes the title. Files in directories the index doesn't recognize are reported and skipped — push never creates walls or boards.
- **rename** — when a tracked file disappears and another `.md` with the same content hash appears in the same board, push treats it as a title change (`PUT` with new title). Renaming AND editing in the same step looks like delete + create.
- **delete** — tracked file removed locally → `DELETE /notes/{id}`.
- Before every write push fetches the current `updated_at`; if the server advanced since the last sync the change is skipped and reported. Pull first or pass `--force`.

When to suggest it:

- Richard asks to "edit a board in vim", "grep across notes", or work on many notes at once.
- A long writing session is easier in a real editor than via heredocs.
- He wants a local backup of a wall before some risky reshuffle.

Don't suggest sync for one-off single-note edits — the regular `hmt notes update` flow is lighter.

## Errors

- `429` → wait `Retry-After` seconds, then retry once.
- `409` → Idempotency-Key collision with a different body. Regenerate by rerunning the command (CLI mints a fresh UUID each call).
- `404` on update → note was deleted or never existed; re-search.
- `5xx` → request did **not** persist. Safe to retry.

## Improvements worth flagging to Richard (occasional, not nagging)

If you hit one of these while using the skill, mention it once — don't pile on:

- No "rename board" CLI? Confirm. AGENT.md lists `PUT /boards/{id}` but worth checking the CLI surface.
- No board reorder / wall reorder endpoint. Cosmetic, low priority.
- `hmt notes search` only returns 20 results with no paging — fine for now, would matter later.
- `Inbox` is system-protected on the General wall but `hmt notes create` without `--board` auto-routes there; that's a nice ergonomics win, keep it.

