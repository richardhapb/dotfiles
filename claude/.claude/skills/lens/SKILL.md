---
name: lens
description: Explain how a change or a piece of code works as one short, self-contained HTML page built around diagrams (component map, logic flow, sequence, lifecycle) with every claim linked to the code. Static by default (nothing is run); optionally enriched with real captured payloads. Use when the user says "lens", "explain how X works", "explain this MR/PR/branch", "what does this change do", "how do these services talk", "draw me how this flow works", or wants to understand a system quickly. Not for finding bugs (use a review skill) and not for changing code.
---

# lens

One cheap pass that builds a mental model: what the thing is for, which pieces take part, how the logic flows, in what order they talk, which states something moves through, where each step lives in the code, what was traded off, what to watch. The diagrams carry the explanation; text only annotates them.

A script does discovery, you interpret it in one inline pass (no subagents), a second script renders. The page is local and is never uploaded or posted.

Output: `${LENS_ROOT:-~/lens}/<change|flow>/<slug>--<ref>/` with `index.html`, `data.json`, `scan.json`, `hunks.txt`, optional `payloads/`. `<root>/INDEX.html` lists every page and is rebuilt automatically.

## Targets

| Question | Command (run inside the repo) |
|---|---|
| What does my branch change? | `python3 $S/scan.py` (branch vs the default branch, commits only) |
| What does this MR or PR do? | `python3 $S/scan.py --review <url\|number> [--project group/proj]` (`--mr` and `--pr` are aliases) |
| How does this code work? | `python3 $S/scan.py --paths <path> [<path> ...] --name "short name"` (reads files at HEAD) |

`S=<this skill dir>/scripts`. A review is read with `glab` for a GitLab MR URL and `gh` for a GitHub PR URL; a bare number uses the `origin` remote to pick one. Flags: `--budget N` (lines of source you will read, default 1500), `--max-hits N` (default 120), `--no-fetch`, `--base REF`, `--out DIR`, `--repo DIR`, `--services FILE`.

For "how does X work" pick the smallest paths that cover the flow (a service directory, a handler plus its job). A huge tree gives a thin page; the digest warns when it hits a cap.

## Steps

1. **Scan** (about 1s). The digest lists files, channels (HTTP, gRPC, Kafka, Temporal, SQL, queues, flags, env URLs, each as `id | target -> service | file:line`), signals (metrics, logs, errors, timeouts), callers outside the scanned files, test names, and the MR description. It writes `scan.json` and `hunks.txt` into the page directory (first line of the digest).
   Service names come from an optional map (`--services`, `$LENS_SERVICES`, or `<repo>/.lens/services.json`):
   ```json
   {"services": {"Orders API": {"hosts": ["orders"], "env": ["ORDERS_URL"], "ports": [8080]}}}
   ```
   A target the map does not resolve is "unresolved". Never guess a service name.
2. **Read** `hunks.txt` only (already budgeted: files with channel hits first, then the largest). Open another file only for one line of context a channel row or a caller needs. An MR/PR description is `reported`, not verified. For your own branch, still base the page on `hunks.txt`, not memory, so it matches the commit it pins.
3. **Choose the diagrams** (omit a key when the diagram would say nothing):
   - `flow`: always. The logic of the change or flow, 5 to 9 nodes, not the file layout.
   - `participants` + `edges` (the map): when more than one service, store or queue is involved.
   - `sequence`: when calls happen in a meaningful order between 3 or more actors.
   - `states`: when something has a lifecycle (a status column, an enum, a state machine).
4. **Write `<dir>/data.json`** (schema below). Reference code by scan id (`"at": "H3"`); the build fills file, line, text, service and link. Spend words on judgment: why a step exists, what breaks, what the diff does not show.
5. **Build and open**:
   ```bash
   python3 $S/build.py <dir> --open
   ```
   It prints warnings (unknown ids, dangling edges, labels it would cut, leftover `TODO`). Fix them and rebuild. Rebuilding after a push upgrades `file:line` text to permalinks. Print the page path.

## data.json

Everything is optional except `meta` and `tldr`; a section renders only when its key is present. Text fields accept `` `code` ``, `**bold**` and `[label](https://...)`, nothing else.

```json
{
  "meta": {"title": "plain words", "subtitle": "one line", "kind": "change|flow", "date": "YYYY-MM-DD", "tags": [], "refs": [{"label": "", "url": ""}]},
  "model": "one sentence the reader can repeat",
  "tldr": ["what it does", "what changed or how it works, where", "what you could not tell from the code"],
  "problem": {"lead": "", "keyPoints": ["3 to 5"], "before": "", "after": ""},
  "participants": [{"id": "x", "name": "Full name", "kind": "service|store|queue|external|test", "role": "", "owns": ""}],
  "edges": [{"from": "x", "to": "y", "label": "what", "proto": "HTTP|gRPC|Kafka|SQL|Temporal|webhook", "dashed": true}],
  "flow": {"title": "", "lead": "", "nodes": [{"id": "a", "label": "short", "kind": "start|step|decision|store|end", "changed": true, "note": "", "at": "H3"}],
           "edges": [{"from": "a", "to": "b", "label": "yes", "dashed": false}]},
  "sequence": {"lead": "", "actors": ["x", "y"], "phases": [{"name": "", "from": 0, "to": 3}],
               "steps": [{"from": "x", "to": "y", "label": "short", "kind": "call|return|async|signal|note", "note": "", "at": "H3", "payload": "id", "t": "HH:MM:SS"}]},
  "states": {"title": "", "lead": "", "nodes": [{"id": "s", "label": "pending", "kind": "start|state|end", "note": "", "at": "H4"}],
             "edges": [{"from": "s", "to": "t", "label": "trigger"}]},
  "touchpoints": [{"id": "H3", "note": "what this call does here", "service": "optional override"}],
  "state": {"title": "What gets stored", "rows": [{"col": "status", "value": "done", "meaning": ""}]},
  "decisions": [{"title": "", "where": "`file`", "chose": "", "because": "", "cost": "", "alternative": ""}],
  "ladder": [{"symptom": "", "cause": "", "fix": ""}],
  "takeaways": [{"title": "", "body": ""}],
  "after": {"lead": "", "watch": [{"signal": "", "why": ""}]},
  "payloads": [{"id": "", "title": "", "file": "payloads/01-x.json", "proto": "HTTP", "summary": "", "annotations": [{"path": "request.a.b[0]", "note": ""}]}],
  "evidence": [{"claim": "", "status": "observed|code|reported|inferred|unverified", "source": ""}]
}
```

No x/y anywhere: the renderer lays out every diagram from its edges, left to right up to 4 steps and top to bottom for longer chains.

- **Labels are short**: edge labels at most 24 characters, node labels at most 40. Detail goes in `note`, never in a label.
- **Walkthrough**: write nodes and steps in execution order. Any node or step with a `note` or an `at` gets a number badge in the diagram and a row in the table below it (what happens, linked code). This is where the "how it works" lives, so give the nodes that matter a note and an anchor.
- **Flow**: mark nodes the change touches `changed`. Decision nodes carry a question, outgoing edges carry the answers. Loops are fine.
- **Map**: only things the scan or the code shows, with full names, never acronyms. Draw an edge only for an interaction a touchpoint or the code supports; anything inferred is `dashed`. One edge per direction.
- **Touchpoints**: pick the 3 to 8 that carry the story; the other scan hits appear collapsed by themselves.
- **Decisions**: 2 to 4, each with its cost and the alternative. If the code does not reveal one, write `unknown from the code`.
- **Evidence**: the build adds what was scanned and not read. You add `inferred` and `unverified` claims (for example "caller behaviour outside this repo").

## After the scan: what to watch

Always fill `after.watch` from the signals and channels (changed metrics, logs, errors, flags, timeouts, new call paths): what to look at and why. If the user has observability tooling already connected and asks for it, look up monitors for the touched services; otherwise do not authenticate anything. Going deeper (queries, dashboards, thresholds) happens only on request.

## Observed mode (optional)

Use only when the user can run the system and wants real messages on the page. You run it with whatever the project uses; lens does not start services. Read-only commands only, local or test data only, never production or staging data.

1. Pipe each captured request and response through the masker, which writes `payloads/NN-id.json` and prints the `payloads[]` entry:
   ```bash
   python3 $S/redact.py --out <dir> --id create-order --service orders --method POST --route /orders --request req.json --response res.json
   ```
   It masks secrets by key name, file contents, SSN-like values, emails, bearer tokens and JWTs, and cuts long strings. Never edit a captured body to make it prettier.
2. Add the entry to `payloads`, fill `summary` and a few `annotations` on the fields that matter, link steps with `"payload": "<id>"`, and use real `t` times in the sequence.
3. Mark what you saw as `observed` in the evidence table, and what you did not run as `unverified`. Say plainly whether a run is before or after the change.

## Rules

- No invented numbers, endpoints, topics, services, bodies or timings. Everything comes from the code, the scan, the MR/PR description or a capture, or is marked `inferred`.
- Code links are pinned to a commit sha (never a branch), and the page says which commit. Not pushed means no links yet; that is expected, rebuild after the push. Build never pushes.
- Uncommitted work is not scanned (the digest warns). Commit first if it matters.
- Mask secrets and personal data from anything you copy onto the page, and mark masked fields as masked.
- Keep it short: if a section has nothing real to say, omit its key. No glossary.
- Never post, upload or link the page anywhere.

## Files

`scripts/scan.py` (discovery), `scripts/build.py` (expand ids, lint, render, index), `scripts/redact.py` (payload masker), `template.html` (the renderer), `tests/test_lens.py` (`python3 -m unittest discover -s tests`). Pure Python 3 stdlib; the page needs no network.
