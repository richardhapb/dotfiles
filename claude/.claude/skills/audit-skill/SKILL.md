---
name: audit-skill
description: Audit one skill from ~/.claude/skills and score it 0-10 on frictionless, does-what-it-should, correct tooling, safety, efficiency and single responsibility, plus an average. Works retrospectively from past session transcripts, or by simulating scenarios against local mocks when there is no history. Use when the user says "audit skill X", "how did that skill do", "improve this skill", "review my skills", or right after using a skill and wanting it evaluated. Report and proposals only; never edits the skill without confirmation.
---

# Audit a skill

Goal: make each skill a small, trustworthy tool that does one thing well, so the user can orchestrate them as a manager and rely on the result. This skill measures how far a skill is from that and proposes the smallest changes that close the gap.

Scope: `~/.claude/skills` only. Read-only. Fixing is a separate step the user approves.

Helpers (stdlib Python 3.9+, run with `-I`; paths relative to this skill dir):

```bash
python3 -I scripts/audit_facts.py list                    # skills + provenance
python3 -I scripts/audit_facts.py static <skill>          # lint facts (JSON)
python3 -I scripts/audit_facts.py runs <skill> [--since 60] [--project SUB] [--session ID] [--limit 5] [--user-turns 2]
scripts/sandbox.sh [-f FIXTURES] [-l LOG] -- <cmd...>     # remote CLIs shimmed/blocked
```

Scoring anchors and caps live in [rubric.md](rubric.md). Read it before scoring.

## 1. Pick the target

If the user named a skill, use it. If not, run `list`, show the names with a one-line purpose, and ask which one. Do not guess. If it was used earlier in this very session, say so: that is the freshest evidence.

Check provenance from `list`: `symlink:tracked` skills live in the dotfiles repo (public: no workplace specifics in any proposed change), `local-only` ones are not in git (say so when proposing edits, a clean `git status` will not show them).

## 2. Choose the evidence mode

1. **Retrospective** -- `runs <skill>` digests every invocation (forked sessions are merged by invocation id): tool use per segment, errors, harness denials, retries, user messages. A run's window ends at the next invocation, after `--user-turns` typed prompts, or at `--max-events`; `window_ended_by` says which. Tool counts after the first user reply may belong to unrelated work, so use `segments` and judge where the skill's task ended before scoring Efficient. If the user points at a session or "the one we just did", pass `--session`. Prefer this: it is what really happened.
2. **Simulated** -- no usable history, or the history does not cover a risky branch. Build scenarios from the skill's own steps (happy path, missing input, tool failure, hostile input, re-run). Execute only what is local: run bundled scripts against temp dirs, wrap anything that touches a remote CLI in `sandbox.sh`, feed canned output through `-f` (files `<cmd>.out`, or `<cmd>.<arg1>_<arg2>.out` per subcommand, e.g. `glab.repo_view.out`; `.rc` sets the exit code).
3. **Static only** -- when neither is possible. Say it plainly and lower confidence.

State the mode up front. Mark what could not be exercised (MCP tools, absolute-path binaries, in-process HTTP, anything needing a live system) as not simulable; do not pretend coverage. Hard line: never write to clouds, remotes, shared systems or prod to test a skill. No `git push`, no posting, no ticket writes, no prod consoles. Mocks and temp dirs only.

## 3. Gather facts, then judge

Run `static` first: it gives deterministic facts (size, missing files, risky commands, secrets, confirmation language, systems touched). Then read `SKILL.md` and its bundled files yourself; the script finds patterns, you judge intent.

Look for, per run or scenario:

- **Friction**: user corrections, repeated identical commands, errors that were retried, permission denials (a command the skill tells you to run that the harness refuses), questions the skill makes you ask that context already answers, steps that depend on state nobody set up.
- **Commands**: wrong flags, shell quoting traps, zsh globbing, relative paths that break after a `cd`, no timeout on long calls, output that floods context.
- **Tooling**: hand-rolled parsing where a purpose-built CLI/MCP/skill exists, a skill re-implementing another skill, missing use of a hook, permission rule or script that would make a repeated manual step deterministic.
- **Safety, in code terms**: irreversible or outward-facing actions without a confirmation gate, broad permissions, secrets or personal data in the skill text or in what it writes, data leaving the machine, no undo path, writes to shared state during "read" flows.
- **Efficiency**: tool calls that add nothing, whole-file reads for one fact, serial calls that could run together, a large `SKILL.md` loaded for a small job.
- **Responsibility**: does it do one thing? Flag skills that mix gathering, deciding and publishing, or that bake in voice, formatting or review logic that belongs to a sibling. Name the sibling.

Context: the user wants decisions already made to carry forward. Check whether the skill reads what it should (CLAUDE.md rules, memory, handoffs, sibling skills) instead of re-asking, and whether it leaves an artifact the next skill can consume.

Never invent numbers. Counts and durations come from script output or from what you read; say which. Scores are judgments, so each one cites its evidence.

## 4. Report

Lead with the manager view; give detail below it. Keep the manager view readable in one screen.

```
Skill: <name>   mode: retrospective | simulated | static   confidence: low|med|high
Evidence: <N runs / scenarios / files> -- <what was and was not exercised>

| Dimension            | Score | Why (one line) |
| Frictionless         |  x/10 |  |
| Does what it should  |  x/10 |  |
| Correct tooling      |  x/10 |  |
| Safe                 |  x/10 |  |
| Efficient            |  x/10 |  |
| Single responsibility|  x/10 |  |
| Average              | x.x/10  (weakest: <dimension>) |

Verdict: trust as-is | trust with the listed fixes | do not run unattended
Top 3 changes (highest leverage first)
```

Average is the plain mean of scored dimensions. A dimension with no evidence is `n/a` and is excluded; say so. Always show the weakest dimension, because a low safety score must not be averaged away.

Then the detail section: findings with evidence (`file:line`, session id plus the short quoted symptom, redacted), proposed diffs, and a **system view**: which skills it hands off to or receives from, what artifact it should emit, overlaps or gaps with siblings, and tooling worth building (script, hook, permission rule, mock, or splitting the skill). Suggest tooling only when the evidence shows a repeated manual step or a missing guardrail.

## 5. Proposals and applying

Proposals are minimal diffs, each tied to a finding. Apply nothing until the user confirms which ones. When applying: edit through the real path (check `ls -la ~/.claude/skills/<name>` for a symlink), add or update a test when behavior changes, and leave committing to the user. For tracked skills run the hygiene grep from the user's memory notes before they commit. Re-run `static` after the edit and report the delta.

## Guardrails for the audit itself

- Transcripts hold real data. Quote the minimum, use the script's redacted output, never paste tokens, personal data or customer records into the report, a note, or a tracked file.
- Reports go to chat. Save to a file only when asked, and never inside a tracked repo if it quotes transcript content.
- Do not audit by running the skill for real. Retrospective reads history; simulation uses mocks.
- Be candid about weak spots in your own evidence. A confident score on thin evidence is worse than `n/a`.

## Gotchas

| Symptom | Cause / fix |
|---|---|
| `runs` finds nothing | Skill never invoked in the window. Widen `--since 0`, drop `--project`, or fall back to simulation. |
| A hit is only in a skill catalogue echo | The script matches real `Skill` tool calls and `/name` commands, not mentions. |
| `denials` is empty but a command failed | `denials` holds only harness refusals (permission, classifier, hook) on errored results. Auth or network failures land in `errors`. |
| Sandbox did not block a call | It only shims PATH lookups. Absolute paths and MCP tools are out of reach; mark not simulable. |
| zsh `no matches found` | Quote globs and `--include='*.jsonl'`. |
