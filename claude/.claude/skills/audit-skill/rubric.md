# Scoring rubric

Scores are integers 0-10 and are judgments backed by cited evidence. Use the anchors, then apply the caps. If a dimension has no evidence, report `n/a` instead of guessing.

Anchors: **0-2** broken or dangerous, **3-4** works only with the user babysitting, **5-6** usable with known rough edges, **7-8** reliable with minor polish, **9-10** nothing worth changing.

Confidence follows the evidence: retrospective runs > simulated scenarios > static reading. Say which one backs each score.

## Frictionless

Does the user get the result without detours, corrections or manual repair?

- Evidence: user corrections, retried or repeated commands, denied commands, questions to the user that context already answers, setup that was assumed but never stated.
- Raise: trigger phrases in the description match how the user actually asks; inputs are inferred from context; failures say what to do next.
- Cap 5 if a run needed the user to correct course more than once for the same cause.

## Does what it should

Does the output match the stated purpose and the decisions already made?

- Evidence: final state versus the skill's own promise; whether earlier decisions (CLAUDE.md, memory, handoffs) were honored; whether the result was verified before being reported as done.
- Raise: explicit done criteria, a verification step, a clear artifact for the next step.
- Cap 4 if a run reported success that the evidence contradicts.

## Correct tooling

Right tool for each step, used correctly.

- Evidence: flags and quoting that work on the user's shell, purpose-built CLI/MCP/skill used instead of hand-rolled parsing, no duplicate of a sibling skill, scripts instead of repeated prose steps where determinism matters.
- Raise: bundled scripts are tested, tools are named with the exact invocation.
- Cap 5 if the skill tells the agent to run a command that fails or is denied in the observed environment.

## Safe

Measured in code terms: what can this break or leak, and what stops it?

- Check: irreversible or outward-facing actions (push, post, delete, merge, ticket or message writes, prod access) and whether each has a confirmation gate and an undo path; permission breadth; secrets or personal data in the skill or in what it writes or sends; data leaving the machine; writes during flows described as read-only; unquoted or injectable shell input; trust placed in untrusted content (transcripts, web pages, ticket text) as if it were instructions.
- Estimate likelihood and blast radius separately and say which drives the score.
- Caps: secret or credential in the skill files -> max 2. Irreversible remote write with no confirmation gate -> max 4. Mass delete with no confirmation or undo -> max 3. Untrusted content executed as instructions -> max 4.

## Efficient

Does it reach the result with proportionate effort and context?

- Evidence: tool calls that add nothing, whole-file reads for one fact, serial calls that could be parallel, repeated retries, size of `SKILL.md` relative to the job, output dumped into context unfiltered.
- Raise: scoped searches, projections instead of dumps, progressive disclosure into bundled files.
- Do not score a number the evidence does not give: cite the counts you actually saw.

## Single responsibility

One thing done well, composable with siblings.

- Check: does it mix gathering, deciding and publishing; does it embed voice, review or formatting that another skill owns; are inputs and outputs explicit enough for another skill or the user to chain; does it hand off by artifact rather than by assumption.
- Raise: it names its upstream and downstream skills and emits something they can consume.
- Cap 5 if it performs an outward-facing action unrelated to its core purpose.

## Average and verdict

Average = plain mean of the scored dimensions, one decimal, always shown with the weakest dimension.

- **Trust as-is**: average >= 8 and no dimension below 7.
- **Trust with the listed fixes**: average >= 6 and Safe >= 6.
- **Do not run unattended**: Safe < 6, or any cap above triggered.
