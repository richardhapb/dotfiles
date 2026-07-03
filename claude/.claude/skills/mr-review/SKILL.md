---
name: mr-review
description: Review a 3rd-party GitLab merge request — fetch the MR via glab, read the diff, surface bugs/regressions/scope issues, and report findings grouped by severity. Use when the user asks to "review this MR", pastes a GitLab MR URL, or asks for a code review on someone else's branch. Does NOT ask the author clarifying questions — validates against the diff and repo conventions only.
---

# MR Review (3rd-party)

Review someone else's GitLab MR. The author isn't in the room — don't ask them questions. Verify against the diff, the repo, and stated intent in the MR description.

`glab` is the interface (`/opt/homebrew/bin/glab`). Don't hit the GitLab REST API directly unless `glab` can't do the job.

## Process

### 1. Fetch the MR

```bash
glab mr view <ID> -R <project>          # title, description, comments, state
glab mr diff <ID> -R <project>          # full diff
```

If the diff is large, save to a file and `Read` it — don't try to scan it inline.

Also fetch the branch locally so you can read full files at the MR's HEAD:

```bash
git fetch origin "merge-requests/<ID>/head:mr-<ID>"
git show mr-<ID>:<path>                  # read any file at MR HEAD
```

Reading full files matters when a hunk's correctness depends on context the diff doesn't show (lifecycle methods, sibling functions, what an identifier resolves to).

### 2. Read for *intent vs. behavior*

The MR description tells you what the author thinks they're doing. The diff tells you what they actually did. Most real review value is in the gap.

For each non-trivial hunk, ask yourself:

- **Does this match the stated scope?** Title says "X for CZ" — are there changes that aren't about X or CZ? Flag scope creep; bundled refactors raise blast radius and complicate revert.
- **Does it actually do what it claims?** Read the code, not the commit message. Trace identifiers — does that prop name match what the consumer expects? Does that ternary actually evaluate to what the author thinks?
- **What does it break?** A change to a shared component (e.g. an Input wrapper, a base button, a shared validation helper) affects every caller. Grep for callers if uncertain.
- **What was deleted?** Deletions are easy to skim past. A deleted `triggerProps={{ type: 'button' }}` or a deleted test guarding a past bug is often the real story.

### 3. Verify, don't assume

Before flagging something as a bug, confirm. Cheap checks that prevent false positives:

- **Function returns truthy/falsy?** — open the function and check. `constructMediaQuery(...)` returns a `MediaQueryList`, not a boolean. `someHelper()` may already handle the nullish case. Don't guess.
- **Identifier still exists?** — `grep` for renamed/removed exports.
- **Test actually asserts behavior?** — read the assertions, not just the `describe` strings. A test named "renders tooltip" that only checks `getByTestId('tooltip')` against a mock that always renders it is a vacuous test.
- **Translation keys present in all locales?** — if `en.json` got a new key, every other locale file should too.

### 4. Apply a DDD lens to domain-touching changes

If the diff touches domain logic — entities, value objects, business rules, naming of domain concepts, cross-module/context boundaries — invoke Claude's `ddd` skill via the Skill tool:

```
Skill(skill: "ddd")
```

Apply that lens to the review:

- **Ubiquitous language consistency.** Does the new code use the same domain terms the rest of the codebase uses? A diff that introduces `customer` where the surrounding module says `candidate`, or `validation` where the rest says `screening`, is creating drift. Flag it.
- **Bounded context boundaries.** Does the change reach across what looks like a context boundary (e.g. `international/` reaching into `lib/validations/messages` for a domain rule, or a UI component encoding a backend invariant)? Note the leak; suggest where the responsibility belongs.
- **Aggregate / invariant placement.** When a rule like "field X is required for country Y" is enforced, is it enforced at the right boundary, or scattered across UI + helpers + schema? Diffs that re-enforce an existing invariant in a new place are a smell.
- **Anemic vs. behavior-rich models.** A new "type" that's just a bag of strings used by a sibling component is fine; one that owns business rules but exposes only getters/setters is worth flagging.

Skip this lens for purely cosmetic, infra, or test-only diffs.

Test-quality observations are still in scope (mocks that make assertions tautological, whole test files rewritten alongside a feature, `describe` not matching the assertions) — flag them, but as test concerns, not DDD ones.

### 5. Repo conventions

Quickly check what the project's reviewers care about:

- `.gitlab/merge_request_templates/default.md` — what checklist items the author was asked to fill in. If they marked something N/A that clearly applies, flag it.
- Recent merged MRs (`glab mr list -P5 --state merged -R <project>`) — voice, level of detail, whether reviewers typically request screenshots, etc.
- `CLAUDE.md` / `AGENTS.md` / `README.md` if present at repo root or in the touched directories.

Don't lecture about conventions the author already followed.

### 6. Report

Group findings by severity. Be concrete — quote line numbers, file paths, and the offending snippet. A review the author can act on > a review that reads well.

Suggested structure:

```
## MR Review: <title>

<one-line overall take — direction looks right / needs changes / blocked on X>

### 🔴 Bugs
<things that are wrong — quote code, explain why, suggest fix>

### 🟡 Scope / design
<scope creep, API shape, things that aren't bugs but worth pushing back on>

### 🟢 Looks good
<what to keep — calibrates the review and signals you actually read it>

### Tests
<test-specific notes>

### Recommendation
<approve / request changes / blocked — one sentence>
```

Skip empty sections. If there are no bugs, don't write "🔴 Bugs: none" — just omit.

## Anti-patterns

- **Don't ask the author questions.** They're not in the room. Form an opinion from the diff. If something is genuinely ambiguous and load-bearing, note it as "worth confirming with author" rather than blocking.
- **Don't restate the MR description back as a summary.** The author wrote it; the reader read it. Add value or stay silent.
- **Don't flag style nits** the project's linter/formatter would catch. Trust CI.
- **Don't grade every file.** Files where there's nothing to say should not appear in the review.
- **Don't claim a regression without verifying.** "This might break X" without a check is noise. Either verify (grep, read the caller, run the test) or don't raise it.
- **Don't request changes for taste.** "I would have done this differently" isn't a blocker. Reserve 🔴 for actual defects.
