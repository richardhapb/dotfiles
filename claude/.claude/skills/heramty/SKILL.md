---
name: heramty
description: Save findings, summaries, and references into Richard's personal notes system (HeraMty) using the `hmt` CLI. Use proactively when Richard researches a topic, learns something new, debugs a tricky issue, or asks to "save this", "note this", "drop this in heramty/hmt", "log this". Also use when Richard asks to find, read, list, or update notes in HeraMty.
---

# HeraMty

HeraMty is Richard's personal notes app. Hierarchy: **Wall → Board → Note** (markdown). Interact with it via the `hmt` CLI (already auth'd, lives on PATH). The HTTP contract is documented in `/Users/richard.penabonifaz/proj/heramty/AGENT.md`; this skill captures Richard's conventions on top of that.

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

## Walls — discover, then route

**Always start a HeraMty session with `hmt walls list`** and cache the result for the rest of the conversation. Don't re-list per command. The skill deliberately does *not* keep a static table of walls — any hardcoded list will drift, and Richard occasionally adds/renames walls.

Route to a wall by the **role it plays**, matched against names in the live list:

| Role           | Match a wall named (in order) | Use for                                        |
|----------------|-------------------------------|------------------------------------------------|
| work           | `Checkr`                      | tickets, MR work, Slack drafts, scrum, people  |
| learning       | `Sapere aude`                 | research, "how does X work", durable reference |
| fallback       | `General` (system)            | doesn't fit anywhere else — lands in `Inbox`   |
| scratch        | `Random`                      | personal transient / scratch                   |

For other categories (personal projects, books, business, journal/log, …) match by **wall name ≈ topic**: if a wall named `Books` exists and Richard is taking book notes, use it. If the obvious wall doesn't exist, ask before creating — new walls are rare.

**Decision order when content could fit multiple walls:**
1. Work-flavored → the `work` wall.
2. Learning / durable reference → the `learning` wall.
3. Clearly fits a named non-system wall (e.g. `Books`, `Projects`) → that one.
4. Transient / scratch → the `scratch` wall, or `<work-wall>/random` if work-flavored.
5. None of the above → `fallback` wall, default Inbox.

If a role-wall above is missing from the live list (e.g. `Sapere aude` was renamed), ask Richard which wall now plays that role rather than guessing — and offer to update this skill's role names in one edit.

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

### 2. Search before creating

Run `hmt notes search "<key phrase>"` for a likely duplicate. If a near-match exists, propose **updating** that note instead of creating a new one. Show the match in the draft.

### 3. Find target IDs

Run each list at most **once per conversation**, then cache the IDs:

```bash
hmt walls list                         # once per session
hmt boards list --wall <wall-id>       # once per wall you actually touch
```

Pull IDs with `jq -r '.[] | select(.name=="<name>") | .id'`. If the list changes mid-conversation (e.g. you just created a board), reuse the ID from the create response instead of re-listing.

If `hmt walls list` returns a name you don't recognize as one of the role-walls (work / learning / fallback / scratch), don't guess — ask Richard.

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

All writes inject `Idempotency-Key` automatically; safe to retry.

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
