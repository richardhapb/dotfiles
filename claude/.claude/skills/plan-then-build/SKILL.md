---
name: plan-then-build
description: Plan with one model and implement with another (e.g. Opus plans, Sonnet builds) without paying to reprocess the whole planning conversation under the new model. Writes the finished plan to a self-contained file, then hands it to a fresh session/task on the implementation model. Use when the user wants to split planning and implementation across models, or asks how to switch models mid-task cheaply.
argument-hint: "(optional) topic/slug for the plan file"
---

# Plan with one model, build with another

Models don't share prompt cache. Switching `/model` mid-conversation doesn't make the switch itself expensive -- it makes the *next* turn expensive, because the new model has to reprocess the entire existing transcript from scratch to rebuild its own cache. The fix isn't to avoid switching models; it's to avoid carrying a long planning transcript across the switch. Do the switch at a clean boundary, with a short, self-contained file as the only thing that crosses it.

## Process

### 1. Plan (current model, e.g. Opus)

Research and design as normal -- plan mode is fine for this. Do not start implementing. Keep the planning conversation focused; the longer it runs, the more expensive it is if the handoff ever stays in-session (step 3).

### 2. Write the plan to a file

Before handing off, write the finished plan to disk. Treat it like briefing a fresh subagent with zero context (see the `Agent` tool's guidance) -- no "as discussed above," no implicit references to the planning conversation. Include:

- Exact file paths and the specific change at each one.
- Decisions made and why, including alternatives that were considered and rejected (so the implementer doesn't re-litigate them).
- Anything the plan deliberately leaves out of scope.

Pick a durable location:
- If the project already has a place for plans/design docs (check `CLAUDE.md`, an `orch_docs/`-style dir, or ask), use that.
- Otherwise default to `plans/<slug>.md` in the repo, or ask the user where they want it if the repo has no convention.

Don't use the session scratchpad for this -- it's ephemeral and won't survive into a new session.

### 3. Hand off to the implementation model

Two ways to do this; pick based on how long the planning discussion was:

- **Same session, `/model` switch.** Simplest. Fine for short planning conversations. The implementation model still reprocesses the whole prior transcript once (unavoidable cost of staying in one session), but if that transcript is short this is cheap enough not to bother with the alternative.
- **Fresh session or subagent task (recommended for anything non-trivial).** Start a new session, or hand the plan file to a Task/subagent, with the plan file as the only input. This is the only way to actually avoid the reprocessing cost -- the implementation model never sees the planning conversation, only the short plan file.

Either way, tell the implementation model explicitly: "the plan file at `<path>` is the source of truth -- implement it directly, don't re-derive the design."

### 4. Implement

The implementation model should treat the file as authoritative and re-read it if it changes, rather than relying on a memory of its contents formed earlier in the conversation.
