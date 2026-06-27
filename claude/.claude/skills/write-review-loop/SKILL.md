---
name: write-review-loop
description: Run a "writer + background reviewer" loop — you keep coding while a background reviewer agent continuously reviews COMPLETE, current snapshots of the local working tree, reporting findings by severity until High/Medium are clean. Use when the user asks to "review as I go", "keep a reviewer running in the background", "write-review loop", or wants continuous local self-review of in-progress work without touching the remote.
---

# Write + Background Reviewer Loop

You are the **writer**. You make code changes. In parallel, a **background reviewer** agent reviews your work, reports findings by severity, and you fix the High/Medium ones. Repeat until the reviewer's verdict is clean.

Reviews are **local working tree only** — no remote, no `glab`, no fetching MR branches. The reviewer reads what's on disk (and untracked files), not what's pushed.

## The one rule that makes this work: review a complete, current snapshot

A background reviewer is useless — worse, actively misleading — if it reads files mid-write or reads a state you've already moved past. Two failure modes to design against:

1. **Mid-write race.** A reviewer launched while you're still editing reads some files edited and others not, or reads a file you change three seconds later. It reports a "bug" that's just an inconsistent intermediate state.
2. **Stale launch.** The reviewer was launched *before* your latest batch of fixes, so it re-reports issues you already fixed.

Both are prevented by the same discipline: **reach a checkpoint, capture a snapshot, hand the reviewer the snapshot — not the live tree.**

## Checkpoint

Don't review every keystroke. A checkpoint is a **logical batch of work that is done and self-consistent**:

- The change you set out to make in this batch compiles / is syntactically complete (no half-written function, no dangling import).
- All edits for the batch are saved to disk.
- Tests and lint pass locally for what you just touched (run them — a reviewer shouldn't be spending findings on a failing test you already know about).

Only at a checkpoint do you launch (or re-launch) a reviewer. Between checkpoints, you keep coding; the reviewer is either idle or working on the *previous* snapshot.

## Snapshot

At a checkpoint, freeze the current state so the reviewer reads a stable thing even while you keep editing afterward. Write a snapshot file the reviewer reads, containing:

1. **The full local diff** of tracked changes against the base (the branch's merge-base or whatever the work started from):

   ```bash
   git -C <repo-abspath> --no-pager diff <base>...HEAD > /tmp/wrl-snapshot-<n>.diff   # committed work
   git -C <repo-abspath> --no-pager diff > /tmp/wrl-worktree-<n>.diff                 # unstaged
   git -C <repo-abspath> --no-pager diff --cached >> /tmp/wrl-worktree-<n>.diff       # staged
   ```

2. **An explicit list of untracked files** — these do NOT show up in `git diff` and are the most-missed part of a review:

   ```bash
   git -C <repo-abspath> --no-pager status --short
   ```

   Pull out the `??` entries and list their absolute paths in the snapshot so the reviewer reads each one in full.

A `git stash create` ref or a throwaway WIP commit also work as a frozen reference. The point is the reviewer reviews **that frozen reference**, so edits you make after the checkpoint can't corrupt the review in flight.

## Launching the reviewer

Use the Agent tool, `run_in_background: true`, `subagent_type: general-purpose` (or `Explore` for a strictly read-only pass). Give it:

- The repo's **absolute path** and the snapshot file path(s).
- The list of untracked-file absolute paths to read in full.
- For a **re-review**, the prior findings and which ones you've addressed — so it *verifies the fixes* instead of re-reporting them — plus the **fresh** snapshot path.

Prefer **one reviewer per checkpoint** over a single long-lived reviewer reading live files. A long-lived reviewer racing the working tree is exactly failure mode #1.

### Reviewer instructions (bake these in verbatim — every one is hard-won)

> You are reviewing a snapshot of a local working tree. Review only what the snapshot and the listed files contain.
>
> - **Never use `cd`** — it triggers permission prompts. Use absolute paths and `git -C <repo-abspath> ...` for any git command.
> - Always `git --no-pager`.
> - If a read-only git or read command is blocked by the sandbox, **retry the same call with `dangerouslyDisableSandbox: true`** (safe for read-only git/reads). If Bash git is denied entirely, fall back to the **Read tool on the pre-written snapshot file** at `<snapshot-path>`.
> - **Untracked new files do not appear in `git diff`.** Read each untracked file listed below in full: `<absolute paths>`.
> - Report findings grouped by severity: **Blocker / High / Medium / Low / Nit**. For each: `file:line`, what's wrong, and a concrete fix.
> - End with a one-line **verdict**: `ship` / `fix-then-ship` / `needs-work`.
> - **Do not ask the author questions** — they're not in the room. Form an opinion from the snapshot.

## The loop

```
checkpoint reached (batch done, tests + lint pass locally)
  -> capture snapshot (diff + untracked list)
  -> launch background reviewer at the snapshot
  -> keep coding the next batch  (or wait, if you're blocked on the review)
  -> reviewer completes -> triage findings:
        fix all High / Medium
        Low / Nit: optional, or defer with a note
  -> next checkpoint
  -> re-review (hand it prior findings + fresh snapshot)
repeat until verdict has no open High/Medium
```

**Stop condition:** all High/Medium findings resolved (verdict `ship`, or `fix-then-ship` with only Low/Nit left). Low/Nit don't block the loop from ending.

## Anti-patterns

- **Don't launch a reviewer mid-edit.** Reach a checkpoint first. A review of a half-written file is noise.
- **Don't reuse a stale snapshot.** Every re-review gets a fresh snapshot reflecting the latest fixes.
- **Don't let the reviewer read live files.** It races your edits. Hand it a frozen snapshot.
- **Don't forget untracked files.** They're invisible to `git diff` and are where the unreviewed code hides.
- **Don't chase Nits before High/Medium.** Fix the things that matter; defer taste.
- **Don't have the reviewer ask you questions** or wait on you — it reports and exits; you decide.
