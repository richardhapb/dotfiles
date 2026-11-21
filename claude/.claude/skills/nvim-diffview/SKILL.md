---
name: nvim-diffview
description: Open the current branch's diff in neovim in a new Rex tab. If the branch has an open MR (GitLab) or PR (GitHub) it opens the review plugin (gitlab.nvim / octo.nvim); otherwise it opens Diffview against a freshly fetched origin/master (or origin/main). Use when Richard asks to "open the diff", "show me the diff in nvim", "diffview this branch", "review this MR/PR in nvim", or when the gitlab-mr skill asks whether he wants to look at the diff before creating the MR. Read-only -- it never comments, approves, submits, commits or pushes.
---

# Neovim diff tab

One new Rex tab, three possible views, chosen by what exists for the current branch:

| Branch state                  | View                                      |
|-------------------------------|-------------------------------------------|
| Open MR on a GitLab remote    | gitlab.nvim review of that MR             |
| Open PR on a GitHub remote    | octo.nvim review of that PR               |
| No open MR/PR                 | Diffview, `origin/<base>...HEAD`          |

## Recipe

**1. Detect the host and any open MR/PR.**

```bash
branch=$(git branch --show-current)
origin=$(git remote get-url origin)
case "$origin" in
  *github.com*) host=github; pr=$(gh pr list --head "$branch" --state open --json number -q '.[0].number') ;;
  *)            host=gitlab; mr=$(glab mr list --source-branch "$branch" -F json | jq -r '.[0].iid // empty') ;;
esac
```

Empty `pr` / `mr` means no open one: go to the Diffview path (step 2c). A detached HEAD has no branch, so it also goes to Diffview. Tell Richard which view you picked and why, in one line.

**2a. GitLab MR -> gitlab.nvim.** It reviews the MR of the current branch, so the checkout must be that branch.

```bash
rex window new -s "$REX_SESSION" mr-review --focus=false -c "$(git rev-parse --show-toplevel)" --json -- \
  nvim -c 'lua require("gitlab").review()'
```

**2b. GitHub PR -> octo.nvim.** Open the PR, then start the review once its buffer has loaded (octo is async, so defer instead of chaining the two commands).

```bash
rex window new -s "$REX_SESSION" pr-review --focus=false -c "$(git rev-parse --show-toplevel)" --json -- \
  nvim -c "Octo pr edit $pr" -c 'lua vim.defer_fn(function() vim.cmd("Octo review start") end, 3000)'
```

**2c. No MR/PR -> Diffview against a fresh base.** Never diff against a stale local `master`.

```bash
base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/origin/||')
[ -z "$base" ] && for b in master main; do git show-ref --verify -q "refs/remotes/origin/$b" && base=$b && break; done
git fetch --no-tags origin "$base"
rex window new -s "$REX_SESSION" diffview --focus=false -c "$(git rev-parse --show-toplevel)" --json -- \
  nvim -c "DiffviewOpen refs/remotes/origin/$base...HEAD"
```

When more than one diff is open (two repos, two branches), give each tab its own name, for example `diffview-<repo>`, so they can be told apart in the tab bar.

If `base` is empty, stop and tell Richard; do not guess. Three dots, so the base side is the merge-base and only the branch's own changes show. Use the fully qualified `refs/remotes/origin/<base>`: a stray `.git/origin/<base>` file makes the short `origin/<base>` ambiguous (git warns and resolves to the wrong commit). The range covers committed changes only; if `git status --short` is not empty, mention it once.

Drop `--focus=false` when Richard should land in the tab right away.

**3. Verify before saying it is ready.** Sleep ~5s (gitlab.nvim starts its server, octo waits on the network), then:

```bash
rex capture -s "$REX_SESSION" -b <.block_ids[0] from the --json output> --trim | grep -v '^~' | grep -v '^$' | head -20
```

- Diffview: the file panel must be visible with a non-zero `Changes (N)`. `E492` or `Failed to parse rev` means the ref is wrong -- fix it, don't report success.
- gitlab.nvim / octo: the capture must show the review's file panel. If octo shows the PR buffer but no review, send `:Octo review start` (escape first, then `rex send` + `rex send-key enter`). If gitlab.nvim shows an auth or server error, report it verbatim instead of retrying blindly.

## Keys to tell Richard (once)

- Diffview: `<Tab>`/`<S-Tab>` next/prev file, `]c`/`[c` hunks, `g<C-x>` cycle layout, `:DiffviewClose`.
- gitlab.nvim: `<leader>gln` comment, `<leader>gld` discussions panel, `<leader>gla` approve.
- octo: `<leader>ghn` comment, `<leader>ghd` changed files, `<leader>ghs` submit review.

These are his to press. The skill never comments, approves or submits on his behalf.

## Notes

- Layout comes from `functions/diffview_mode.lua`: gitlab.nvim's reviewer is pinned to a two-window layout, plain Diffview adapts to terminal width.
- The tab name is the window label, set by `rex window new <label>`. `rex run --label` only names the pane (block) inside the tab and leaves the tab as "Window xxxxxxxx", so do not use it for this. Re-locate the tab by `rex window ls -s "$REX_SESSION" --json` (`.label`), or rename it with `rex window rename -s "$REX_SESSION" <window_id> <label>`.
- Don't focus-steal from a pending question: when called from another skill's flow, keep `--focus=false`.
- gitlab.nvim derives the GitLab host from `origin` and reads the token from `glab`; it may print a notice about an unset host env var in the pane, which is harmless.
