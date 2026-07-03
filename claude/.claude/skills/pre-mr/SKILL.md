---
name: pre-mr
description: Pre-MR self-review of Richard's current branch — diff against master, surface what reviewers will catch, and ask Richard up to 3 targeted questions about intent and assumptions before reporting. Use when Richard says "review my branch", "pre-mr", "self-review", or otherwise asks for a review of his own in-progress work before opening the MR. Asks bounded clarifying questions — does NOT ask on 3rd-party MR reviews (use `mr-review` for those).
---

# Pre-MR self-review

Review Richard's current branch the way a thoughtful reviewer would, but *before* the MR is opened — so issues get fixed in his editor, not in MR comments.

The author *is* in the room. Ask targeted questions about intent and assumptions. Then verify against the diff and report.

## Process

### 1. Inspect the branch

**First, make sure master is up to date.** A diff against a stale local master will produce false positives ("you're missing X" when X already merged). Fetch before diffing:

```bash
git fetch origin master              # update remote-tracking ref
```

Then diff against `origin/master` (not local `master`, which may lag):

```bash
git status
git log origin/master..HEAD --oneline
git diff origin/master...HEAD --stat
git diff origin/master...HEAD        # full diff — save to file if large
```

If local `master` is behind `origin/master`, mention it once in the report so Richard knows to rebase before opening the MR — but don't run `git pull` or `git rebase` on his behalf.

Also note:
- Branch name (often encodes the ticket — e.g. `ESCR-1584`)
- Whether there's an open MR already (`glab mr list --source-branch $(git branch --show-current)`) — if so, this is "review before requesting review", not "review before opening".

Read the full diff. For non-trivial files, also read the full file at HEAD — context outside the hunk is where bugs hide.

### 2. Read repo design conventions

"Follow repo conventions" means align the review with how *this* repo organizes code. Don't import opinions from other repos.

Read, in order of priority:

- `CLAUDE.md` / `AGENTS.md` / `README.md` at repo root — explicit conventions if present.
- The same files inside the touched directories — local conventions for that module.
- **Adjacent code in the same directory** — naming, file layout, how similar features are wired in. The strongest signal is "how do existing features in this same folder do it?"
- Recent merged MRs touching the same area (`glab mr list --state merged -P10`) for voice and density of past reviews.

When the diff diverges from the local pattern, that's worth flagging — even if the new pattern is arguably better. Consistency is a property reviewers care about.

### 3. Form an initial read *before* asking questions

Don't ask questions cold. Read the diff first, form a hypothesis about what the change does and why, then surface the parts that are genuinely ambiguous or load-bearing. Questions cost Richard's attention — spend them on things you can't infer.

What you can usually infer without asking:
- What the change does (the diff)
- The ticket scope (branch name → Jira / sibling MRs → conventions)
- Whether tests cover the change

What's worth asking:
- **Intent gaps** — when the same code could plausibly serve two different goals, and the right review depends on which.
- **Load-bearing assumptions** — when correctness depends on a fact you can't verify from the repo alone (e.g. "this API returns null when X" — does it actually?).
- **Scope intent** — when there's a refactor bundled with a feature, did Richard mean to bundle it, or did it sneak in?

### 4. Ask up to 3 questions

Use `AskUserQuestion`. Hard cap at 3. If you have more than 3 candidates, pick the ones whose answers most change the review.

Phrase questions so Richard can answer in one click — give concrete options pulled from the diff, not open-ended prompts.

Good question shapes:
- "I see the MR adds X *and* refactors Y. Was the Y refactor intentional, or did it sneak in?" — options: intentional / split it out / hadn't noticed.
- "This depends on `<helper>` returning null when not found. I didn't verify — is that the contract, or should I check?" — options: yes that's the contract / please verify / I'll check.
- "Test coverage hits the happy path but not error case Z. Skip on purpose, or want me to flag it?" — options: skip / flag / add it now.

Bad question shapes (don't):
- "What were you trying to do?" — read the diff.
- "Should I review this?" — yes, that's what was asked.
- "Are there any concerns?" — that's the reviewer's job to find.
- Long lists of nits dressed up as questions.

If the diff is small and unambiguous, **skip the questions entirely** and go straight to reporting. Over-questioning is worse than under-questioning here.

### 5. Question Richard's assumptions via the `grill-me` skill

When you spot load-bearing assumptions Richard seems to be making, invoke the `grill-me` skill via the Skill tool to interview him on those specific assumptions:

```
Skill(skill: "grill-me", args: "<the assumptions to grill on, in 1–3 bullets>")
```

**Bound the grill.** `grill-me` is designed to be relentless; pre-mr is not. Tell it explicitly in the args:
- Cap at the same 3 questions from step 4 (don't add a second batch on top).
- Scope to load-bearing assumptions only — things where the *review changes* depending on the answer.
- Stop once each branch is answered; don't loop back.

Examples of assumptions worth grilling:
- "You're hardcoding `'CZ'` — are more countries coming? If yes, the abstraction matters now."
- "The test instantiates the class directly. Behavior-level test instead, or overkill here?"
- "New field is `validate: required`. Confirmed required on the backend too?"

Don't:
- Question the same assumption multiple ways.
- Demand justification for every choice.
- Suggest patterns ("you could use a Strategy here") when the existing code is fine.
- Let `grill-me` run unbounded — it will, if you don't constrain it.

### 6. Apply a DDD lens to domain-touching changes

If the diff touches domain concepts — entities, value objects, business rules, naming of domain terms, or cross-module/context boundaries — invoke Claude's `ddd` skill via the Skill tool:

```
Skill(skill: "ddd")
```

Then check the diff against the DDD lens:

- **Ubiquitous language consistency.** Does the new code use the same domain terms the surrounding code uses? A diff that introduces `customer` where the rest of the module says `candidate`, or `validation` where the rest says `screening`, is creating drift. Flag it before reviewers do.
- **Bounded context boundaries.** Is the change reaching across a context boundary (e.g. UI encoding a backend invariant, or one feature module importing internals of another)? Note the leak; the responsibility likely belongs elsewhere.
- **Aggregate / invariant placement.** When a rule like "field X is required for country Y" is enforced, is it enforced at the right boundary, or scattered across UI + helpers + schema? Re-enforcing an existing invariant in a new place is a smell.
- **Anemic vs. behavior-rich models.** A new type that's just a string bag is fine; one that owns business rules but only exposes getters/setters deserves a flag.

Skip this lens for purely cosmetic, infra, or test-only diffs.

Test concerns (vacuous mocks, brittle internal-method tests, missing coverage on the new path) are still in scope — flag them as test issues, not DDD ones.

### 7. Don't optimize early

The point of pre-MR review is to ship a defensible MR, not a perfect one. Hold back on:

- Refactors that aren't required for correctness.
- Abstractions for hypothetical second/third use cases.
- Performance concerns without a measurement.
- Style changes the linter/formatter would catch.
- "While you're in there..." scope expansions.

If you spot something that's worth doing but not now, mention it once as "follow-up" and don't block on it.

### 8. Report

Severity-grouped, concrete, line-numbered:

```
## Pre-MR review: <branch-name>

<one-line take — looks ready to MR / fix these first / blocked on Q>

### 🔴 Must fix before MR
<bugs, regressions, broken tests, missing pieces>

### 🟡 Worth considering
<scope, design, assumptions worth pushing back on>

### 🟢 Looks good
<what to keep — calibrates and signals you read it>

### Tests
<test-specific notes>

### MR-readiness
<short checklist: does the description draft itself? are screenshots needed? is the ticket linked? any open Qs from above?>
```

Skip empty sections. If Richard answered questions in step 4, weave the answers into the report so it's self-contained — don't make him re-derive context.

## Anti-patterns

- **Don't ask more than 3 questions.** If you can't decide which 3 matter most, the review isn't ready.
- **Don't ask cold.** Read the diff first, form a take, then ask. Questions before reading produce generic noise.
- **Don't over-question Richard's assumptions.** Surface once, accept the answer, move on. This is review, not Socratic dialog (use the `grill-me` skill if that's what's wanted).
- **Don't flag every nit.** The MR review pass and CI will catch them. Pre-MR review is for substantive issues.
- **Don't propose refactors** unless they're required for correctness or Richard asked.
- **Don't restate the diff back.** Richard wrote it; he knows what's in it. Tell him what reviewers will catch.
- **Don't recommend approval/changes** — Richard's the author. End with "ready to MR" or "fix these first", not "approve / request changes".
