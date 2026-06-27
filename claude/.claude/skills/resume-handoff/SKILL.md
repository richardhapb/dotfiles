---
name: resume-handoff
description: Resume work from a prior session's handoff document. Locates the handoff(s) for the CURRENT project under ~/handoffs/<hash>/, reads the most recent (or one the user names), and continues the work. Use when the user says "resume", "resume handoff", "pick up the handoff", "continue where the last session left off", or starts a fresh session referencing earlier work. Pairs with the `handoff` skill, which writes these files.
argument-hint: "(optional) topic substring, filename, or 'list'"
---

# Resume from a handoff

Handoffs are stored per-project on disk by the `handoff` skill using this convention:

```
~/handoffs/<hash>/YYYYmmdd-HHMM-<topic>.md
```

- `<hash>` = first **12 hex chars** of `sha256(<absolute resolved project dir>)`.
- The project dir is the current working directory, resolved with `pwd -P` (symlinks resolved).
- Filenames are timestamped `YYYYmmdd-HHMM-<topic>.md`, so **lexicographic sort = chronological**; the highest-sorting filename is the most recent handoff.

## Steps

1. **Compute this project's handoff dir** (run verbatim):
   ```bash
   proj="$(pwd -P)"; hash="$(printf '%s' "$proj" | shasum -a 256 | cut -c1-12)"; dir="$HOME/handoffs/$hash"; echo "$proj -> $dir"; ls -1 "$dir" 2>/dev/null | sort
   ```
   - If the dir doesn't exist or is empty: tell the user there's no handoff for this project, show `$proj`/`$hash`, and ask whether they're in the right directory. Do not guess another project's hash.

2. **Pick the file:**
   - No argument → the **last** entry of the sorted list (most recent).
   - Argument is `list` → show all handoffs (filename + first markdown heading) and ask which one.
   - Argument is a substring/topic/filename → match against the listing; if exactly one matches use it, if several match prefer the most recent and say so.

3. **Read the chosen handoff in full** with the Read tool. It is authoritative for what to do next.

4. **Follow it:**
   - Honor its **"suggested skills"** section — invoke those skills as the work requires.
   - Open the artifacts it references (notebook URLs, Jira keys, repo paths, MRs) before acting; do not re-derive what it already establishes.
   - If it records **wrong turns / corrected conclusions**, respect the correction — do not repeat the disproven path.

5. **Briefly orient the user** (3–5 lines): which handoff you loaded (path), the goal, the current state, and the immediate next step it proposes. Then continue the work or confirm the next action.

## Notes
- Read-only discovery: never delete or overwrite handoffs here. Writing new ones is the `handoff` skill's job.
- These files are durable (home dir), unlike the OS temp dir the base `handoff` skill writes to first. If you create a fresh handoff at the end of this session, also save it under `~/handoffs/<hash>/` with a new `YYYYmmdd-HHMM-<topic>.md` name so the chain continues.
- If `pwd -P` isn't the project root the user means, ask — the hash is path-specific and a wrong dir yields a different (empty) hash dir.
