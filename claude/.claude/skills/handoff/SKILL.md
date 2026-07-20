---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work.

## Where to save it (must match the `resume-handoff` skill)

Handoffs live per-project under `~/handoffs/<hash>/YYYYmmdd-HHMM-<topic>.md`:

- `<hash>` = first **12 hex chars** of `sha256(<absolute resolved project dir>)`, where the project dir is the current working directory resolved with `pwd -P`.
- `<topic>` = short kebab-case slug of the handoff subject.

Compute the destination and write the file (run verbatim, then Write to `$dir/$file`):

```bash
proj="$(pwd -P)"; hash="$(printf '%s' "$proj" | shasum -a 256 | cut -c1-12)"; dir="$HOME/handoffs/$hash"; mkdir -p "$dir"; file="$(date +%Y%m%d-%H%M)-<topic>.md"; echo "$dir/$file"
```

Do NOT save only to the OS temp dir or the session scratchpad -- those are ephemeral and `resume-handoff` will not find them. The `~/handoffs/<hash>/` copy is the canonical one. After writing, echo the full path to the user so they can reference it.

## Content

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
