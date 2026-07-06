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

Only at a checkpoint do you launch (or re-launch) a reviewer. Between checkpoints, you keep coding; the reviewer works on the *previous* snapshot.

**Checkpoint 0 — don't start with an idle reviewer.** At loop start, check whether the working tree already has reviewable changes (`git status`, diff against base):

- **Tree already dirty** (the usual case — the loop is invoked on in-progress work): that state *is* the first checkpoint. Snapshot and launch the first reviewer immediately, then start writing the next batch. The reviewer works from minute zero instead of waiting for your first batch.
- **Tree clean** (starting from scratch): do NOT spawn a reviewer yet — there is nothing to review and it would sit idle or report noise. Write the first batch; the first checkpoint launches the first reviewer.

**At most one reviewer in flight.** If you reach a new checkpoint while a review is still running, don't launch a second one — overlapping snapshots produce duplicate findings and you'd triage the same issue twice. Keep coding; when the in-flight review returns, triage it, then snapshot the (now newer) state for the next reviewer.

## Snapshot

At a checkpoint, freeze the current state so the reviewer reads a stable thing even while you keep editing afterward. Write a snapshot file the reviewer reads, containing:

1. **The full local diff** of tracked changes against the base (the branch's merge-base or whatever the work started from):

   ```bash
   git -C <repo-abspath> --no-pager diff <base>...HEAD > /tmp/wrl-snapshot-<n>.diff   # committed work
   git -C <repo-abspath> --no-pager diff > /tmp/wrl-worktree-<n>.diff                 # unstaged
   git -C <repo-abspath> --no-pager diff --cached >> /tmp/wrl-worktree-<n>.diff       # staged
   ```

2. **Frozen copies of untracked files** — these do NOT show up in `git diff` and are the most-missed part of a review:

   ```bash
   git -C <repo-abspath> --no-pager status --short
   ```

   Pull out the `??` entries and **copy each one into the snapshot directory**, preserving relative paths:

   ```bash
   mkdir -p /tmp/wrl-untracked-<n>
   git -C <repo-abspath> ls-files --others --exclude-standard \
     | rsync -aR --files-from=- <repo-abspath>/ /tmp/wrl-untracked-<n>/
   ```

   The reviewer reads the copies, not the live paths. Handing it live paths reintroduces failure mode #1 — you edit an untracked file three seconds after launch and the reviewer reads the newer state while reviewing the older diff.

A `git stash create` ref or a throwaway WIP commit also work as a frozen reference (a WIP commit after `git add -A` has the advantage of freezing untracked files too). The point is the reviewer reviews **that frozen reference**, so edits you make after the checkpoint can't corrupt the review in flight.

## Launching the reviewer

Use the Agent tool, `run_in_background: true`, `subagent_type: general-purpose` (or `Explore` for a strictly read-only pass). Give it:

- The repo's **absolute path** and the snapshot file path(s).
- The untracked-file **copies** under the snapshot directory (path map: repo-relative path -> copy path) to read in full.
- For a **re-review**, the prior findings and which ones you've addressed — so it *verifies the fixes* instead of re-reporting them — plus the **fresh** snapshot path.

Prefer **one reviewer per checkpoint** over a single long-lived reviewer reading live files. A long-lived reviewer racing the working tree is exactly failure mode #1.

### Reviewer instructions (bake these in verbatim — every one is hard-won)

> You are reviewing a snapshot of a local working tree. Review only what the snapshot and the listed files contain.
>
> - **Never use `cd`** — it triggers permission prompts. Use absolute paths and `git -C <repo-abspath> ...` for any git command.
> - Always `git --no-pager`.
> - If a read-only git or read command is blocked by the sandbox, **retry the same call with `dangerouslyDisableSandbox: true`** (safe for read-only git/reads). If Bash git is denied entirely, fall back to the **Read tool on the pre-written snapshot file** at `<snapshot-path>`.
> - **Untracked new files do not appear in `git diff`.** Read each untracked-file snapshot copy listed below in full (these are frozen copies under `/tmp/wrl-untracked-<n>/`; the repo-relative path is given next to each): `<copy-path -> repo-relative-path>`. Do not read the live repo paths for these — they may have changed since the snapshot.
> - Report findings grouped by severity: **Blocker / High / Medium / Low / Nit**. For each: `file:line`, what's wrong, and a concrete fix.
> - End with a one-line **verdict**: `ship` / `fix-then-ship` / `needs-work`.
> - **Do not ask the author questions** — they're not in the room. Form an opinion from the snapshot.

## The loop

```
loop start:
  tree dirty?  -> that IS checkpoint 0: snapshot + launch reviewer now, start coding
  tree clean?  -> no reviewer yet; code the first batch

checkpoint reached (batch done, tests + lint pass locally)
  -> reviewer still in flight? keep coding; fold this checkpoint into the next review
  -> otherwise: capture snapshot (diff + untracked copies)
     -> launch background reviewer at the snapshot
     -> keep coding the next batch  (or wait, if you're blocked on the review)
  -> reviewer completes -> triage findings:
        fix all High / Medium
        Low / Nit: optional, or defer with a note
  -> next checkpoint
  -> re-review (hand it prior findings + fresh snapshot)
repeat until verdict has no open High/Medium
```

**Stop condition:** all High/Medium findings resolved (verdict `ship`, or `fix-then-ship` with only Low/Nit left). Low/Nit don't block the loop from ending. The verdict must come from a review of the snapshot that *includes* your last fixes — fixing the final High/Medium batch and stopping without a re-review isn't a clean exit.

## Anti-patterns

- **Don't launch a reviewer mid-edit.** Reach a checkpoint first. A review of a half-written file is noise.
- **Don't spawn a reviewer on a clean tree** "to have it ready" — it has nothing to review and just idles. Conversely, if the tree is already dirty at loop start, don't make the reviewer wait for your first batch — that existing state is checkpoint 0.
- **Don't run two reviewers concurrently.** Overlapping snapshots double-report the same findings. One in flight, always.
- **Don't reuse a stale snapshot.** Every re-review gets a fresh snapshot reflecting the latest fixes.
- **Don't let the reviewer read live files.** It races your edits. Hand it a frozen snapshot.
- **Don't forget untracked files.** They're invisible to `git diff` and are where the unreviewed code hides.
- **Don't chase Nits before High/Medium.** Fix the things that matter; defer taste.
- **Don't have the reviewer ask you questions** or wait on you — it reports and exits; you decide.
