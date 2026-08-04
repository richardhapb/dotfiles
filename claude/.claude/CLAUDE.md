# General rules

## Expected practices

- Write test for new implementations or changes that affect the behavior of the programs
- Keep APIs shape at least we are designing something from scratch or we decide to change them explicitly
- When you are not sure about the instructions, or my reasoning / communication is ambiguous, stop and be sure I am reasoning the well the request and validate our asumptions.

## Delivery

- Deliver relevant changes as a PR by default, unless I say otherwise. "Relevant" means changes to code / behavior, not docs. Skip the PR for docs-only edits. For internal tools, like neovim config or dotfiles is ok push direct to main.
- Use git commit conventions -- 50 chars header, 72 chars body. Prefix <fix/feat/chore/docs> in header.
- By default use the convention rpb/<<action(fix/feat/chore/docs)/JIRA(ticket)>-<description>> where action and JIRA are exclusive. 
- For MR / PR title, don't include commit action prefixes (fix/feat/chore/docs), keep them clean, just JIRA tickets if applies

## Constraints

- Don't inclue Claude co-authored footer
- Don't inclue ticket or issues references in test case descriptions. In comments, when it is strictly necessary provide that context.
- Don't include references to tickets / issues in commits, it should be included in the PR / MR instead.
- Don't use em-dash, it is weird, use double dash (--) instead or just use one.
- Don't over estimate time for a project / implementation, thing the long-term changes as possible, since we work together and things get done faster.
- Never merge automatically: these changes could break something, so they need review before merge.
