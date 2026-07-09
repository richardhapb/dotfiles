---
name: heramty
description: "Use when Richard asks to find, read, list, create, or update notes in HeraMty; also use proactively when saving findings, summaries, and references via the HeraMty MCP tools."
version: 2.0.0
author: Richard
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [notes, heramty, mcp, hmt, markdown, knowledge-management]
    related_skills: [obsidian]
---

# HeraMty

HeraMty is Richard's personal notes app. Hierarchy: **Wall → Board → Note** (markdown).

**Interact with it via the HeraMty MCP tools** (`mcp__heramty__*` — `list_walls`, `search_notes`, `get_note`, `create_note`, `edit_note`, `move_board`, …). They are the primary interface from any agent session. Under the hood the MCP server shells out to the `hmt` CLI, so it inherits `hmt`'s auth and idempotency; you almost never need to call `hmt` yourself. The CLI remains the right tool in exactly two places: **host-side cron/collector scripts** (cron can't call MCP) and **`hmt sync`** vault work (no MCP equivalent). Both are covered in their own sections below.

If the `mcp__heramty__*` tools aren't in the tool catalog, the MCP server isn't registered in this session — register it (`claude mcp add heramty -- <path-to>/heramty-mcp`) and start a fresh session, or fall back to the `hmt` CLI for the immediate task. Do not assume a specific Hermes-host binary path; resolve `command -v hmt` or honor `HMT_BIN` when you do need the CLI.

This skill captures Richard's conventions for using HeraMty.

## Writes go through a background agent

**Reads** (`search_notes`, `get_note`, `list_*`, `grep_notes`, …) run inline — Richard is usually waiting on the answer.

**Writes** (`create_note`, `append_note`, `edit_note`, `move_note`, `create_board`, …) are fire-and-forget: they never block Richard's main workflow. When Richard asks to "write this down", "save this to HeraMty", or otherwise create/update a note, **spawn a background agent to do the write** instead of calling the MCP tools inline, then keep working / hand the turn back immediately.

Spawn it like this (background is the default — do not pass `run_in_background: false`):

```
Agent(
  subagent_type: "general-purpose",
  description: "Save HeraMty note",
  prompt: "<self-contained instructions: exact wall + board, note title, and the full markdown body to write. Include the target IDs if you already resolved them, otherwise tell the agent to resolve wall→board via list_walls/list_boards. Tell it to search_notes first and edit_note the near-match instead of duplicating. Have it read the note back and report the final Wall/Board/Title path.>"
)
```

Because the agent runs in the background, you'll be notified when it finishes — relay the resulting `Wall/Board/Title` path to Richard then. Do the draft/confirmation step (below) *before* spawning if the target or content is ambiguous; once Richard has approved (or gave an explicit target up front), delegate the actual write and move on.

The rest of this skill — wall/board conventions, note style, target resolution — is the playbook the spawned agent follows.

## When to suggest saving

Proactively offer to save into HeraMty when:

- Richard finishes a research/learning session ("now I get how X works") — propose a Sapere aude note.
- A debugging session produces a non-obvious answer worth keeping — propose a Sapere aude or Checkr note. If it is in Checkr domain, Checkr it is.
- An MR review, ticket triage, or Slack thread produces a short reusable summary — propose `Checkr/random` (transient) or `Checkr/<existing board>` (durable).
- Richard pastes a long external doc or article we just discussed — propose saving a TL;DR with a link back, not the whole thing.

Do **not** offer:
- After trivial one-shot commands or boilerplate work.
- When the answer is already documented somewhere we just read.
- More than once per conversation unless Richard signals interest.

Phrase it as a single short line: *"Want this saved to HeraMty? I'd put it in `Sapere aude / Postgres` as 'B-tree vs. GiST for jsonb'."* — naming the wall, board, and title up front so it's one decision, not three.

## Walls

Walls change rarely. The table below is the working set as of skill creation — treat it as a hint, not the truth. Call `list_walls` at the start of any HeraMty session to refresh, especially before suggesting a wall by name.

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

**Important distinction:** when Richard says "write this down" after a conceptual explanation, design guidance, study plan, or reusable technical lesson, treat it as durable knowledge and save it under `Sapere aude`, even if the topic came from today's work. Use `Log` only for journal-like daily discoveries or explicit "log this" requests. If the content is both work-related and broadly reusable (e.g. Temporal design rules learned through a Checkr task), prefer `Sapere aude` over `Checkr`/`Log`. But if that is directly related to `Checkr`, use `Checkr`.

Creating a new wall is rare — only when a whole new life-area appears. Ask first.

## Boards — always discover live

Boards change often. **Never assume a board exists** — always call `list_boards` (with the `wall_id`) or `search_boards` first and pick from the live result. Do not hardcode board names in this skill or in conversation memory; the list above the wall picker is the only stable thing.

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
- **Markdown.** Headings, fenced code blocks, lists, links — all supported. Embedded images work but you usually won't have one in this flow.
- **Reference other notes by title** in prose; use `[[Wall/Board/Title]]` wiki-links when you want a real link (resolved by `related_notes` / `link_notes`). Don't fabricate IDs.
- **Title is the index.** Make it searchable: "B-tree vs. GiST on jsonb" beats "indexing".
- **Source links.** If the content came from an MR, ticket, Slack thread, or external doc — paste the URL near the top.

Don't:
- Paste massive untrimmed transcripts. Summarize.
- Save half-formed thoughts unless explicitly asked.
- Repeat what Richard can re-derive from `git log` / a ticket / public docs.

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

Call `search_notes` with a key phrase to find a likely duplicate. If a near-match exists, propose **updating** that note (`edit_note`) instead of creating a new one. Show the match in the draft.

### 3. Find target IDs

- Walls: `list_walls` (or `search_walls "Sapere aude"`) → grab the `id`.
- Boards: `list_boards` with that `wall_id` (or `search_boards`).

Cache the IDs in the conversation; don't relist on every call.

### 4. Write

Content is passed directly as a string argument — no `--file` plumbing, no positional-argument gotchas:

- **Create:** `create_note(board_id, title, content)`.
- **Append:** `append_note(id, content, section?)` — add markdown to an existing note *without* resending the whole body. Preserves the title and everything already there; with `section` it appends under a `## <section>` heading (created at the end if absent). **Prefer this over `edit_note` whenever you're only adding to a note** (a new dated section, another bullet, a summary at the bottom): it skips the read-everything-then-resend step and removes the risk of clobbering existing content on a bad round-trip.
- **Update:** `edit_note(id, title, content)` — replaces title + full content; optimistic locking is handled for you. Use when you must rewrite the title or restructure/replace existing content — not for a plain add (use `append_note`).
- **Rename only:** `rename_note(id, title)` (content unchanged).
- **Move:** `move_note(id, board_id)`; `move_board(id, wall_id)`.
- **Delete:** `delete_note(id)` (soft delete); `delete_board(id)` (cascades to its notes — confirm first).

For long markdown bodies, just pass the full string in `content`; build it however is legible in the turn.

### 5. Echo the result

After creating, print the resulting note's title + the wall/board path. Don't dump the full tool JSON unless asked.

## Reading / searching

- `search_notes(query, limit?)` — fuzzy title search (+content bonus), ranked. Use this first.
- `grep_notes(pattern, ignore_case?, fixed_string?, wall_id?, board_id?)` — regex/literal search across note *content*, line by line. Use when the hit is in the body, not the title.
- `list_notes(board_id?, filter?, sort_by?, descending?, limit?)` — browse a board (or all). Defaults to `updated` + `descending` (newest activity first).
- `get_note(id)` — full content + `Wall/Board/Title` path.
- `related_notes(id)` — `[[…]]` wiki-links: `forward` (links out) + `backlinks` (links in).
- `get_wall(id)` / `get_board(id)` — one wall/board plus a summary of what's inside.

## MCP tool reference

The HeraMty MCP server (`mcp__heramty__*`) exposes the full surface:

| Tool | Args | Purpose |
|---|---|---|
| `list_walls`    | `filter?`, `sort_by?`, `descending?`, `limit?` | list walls |
| `list_boards`   | `wall_id?`, `filter?`, `sort_by?`, `descending?`, `limit?` | list boards (all walls or one) |
| `list_notes`    | `board_id?`, `filter?`, `sort_by?`, `descending?`, `limit?` | list note summaries |
| `search_walls`  | `query`, `limit?` | fuzzy search wall names |
| `search_boards` | `query`, `wall_id?`, `limit?` | fuzzy search board names |
| `search_notes`  | `query`, `limit?` | fuzzy search note titles (+content bonus) |
| `grep_notes`    | `pattern`, `ignore_case?`, `fixed_string?`, `wall_id?`, `board_id?` | regex/literal search across note content |
| `get_wall`      | `id` | one wall + its boards |
| `get_board`     | `id` | one board + a summary of its notes |
| `get_note`      | `id` | full note content + `Wall/Board/Title` path |
| `related_notes` | `id` | `[[…]]` forward links + backlinks |
| `link_notes`    | `source_id`, `target_id`, `section?` | append a `[[Wall/Board/Title]]` link under `## Related` |
| `create_wall`   | `name` | create a wall |
| `create_board`  | `wall_id`, `name` | create a board |
| `create_note`   | `board_id`, `title`, `content` | create a note |
| `append_note`   | `id`, `content`, `section?` | append markdown to a note (optionally under a `## section`) without resending the body |
| `edit_note`     | `id`, `title`, `content` | replace a note's title + full content |
| `rename_note`   | `id`, `title` | rename a note (content unchanged) |
| `move_note`     | `id`, `board_id` | move a note to another board |
| `delete_note`   | `id` | soft-delete a note |
| `rename_wall`   | `id`, `name` | rename a wall |
| `rename_board`  | `id`, `name` | rename a board (system boards reject) |
| `move_board`    | `id`, `wall_id` | move a board to another wall |
| `delete_board`  | `id` | delete a board (cascades to its notes) |

`list_*` take `sort_by` = `alpha` | `created` | `updated`, a `descending` flag, and a `limit`; `filter` fuzzily narrows by name/title. `search_*` use a local fuzzy matcher (walls/boards have no server-side search). All writes inject an `Idempotency-Key` automatically; safe to retry.

The binary lives at `~/proj/heramty/mcp` (`cargo build --release` → `target/release/heramty-mcp`). Register with `claude mcp add heramty -- <abs-path>/heramty-mcp`. Smoke-test independently with `initialize` → `notifications/initialized` → `tools/list` and confirm the tools above are present. If the binary was just rebuilt, start a fresh session before expecting updated tools in the catalog.

## `hmt` CLI — fallback and script-only paths

The CLI is what the MCP shells out to, and it's still the correct tool in two situations:

1. **The MCP server isn't available** in the current session — use the CLI for the immediate task, then register the MCP.
2. **Deterministic host-side scripts** (cron collectors, the vault sync below) — these run where no agent/MCP exists.

```bash
hmt walls list
hmt boards list --wall <wall-id>
hmt notes search "<q>"
hmt notes list --board <board-id>
hmt notes get <id>

# Notes — content comes from --file <path> (default `-` = stdin). Never positional.
hmt notes create --board <board-id> --title "<title>" --file <path>
hmt notes update <note-id>          --title "<title>" --file <path>
hmt notes move <id> --board <other-board-id>
hmt boards move <board-id> --wall <other-wall-id>
hmt notes delete <id>
```

Resolve the binary via `command -v hmt` or `HMT_BIN`; don't hardcode a Hermes-host path.

## Wall semantics for Richard

For review/synthesis jobs, treat the major walls as distinct signal sources:

## Errors

These apply to the underlying API whether you reach it via MCP or CLI:

- `429` → wait `Retry-After` seconds, then retry once.
- `409` → Idempotency-Key collision with a different body. Retry (a fresh key is minted per call).
- `404` on update → note was deleted or never existed; re-search.
- `5xx` → request did **not** persist. Safe to retry.
