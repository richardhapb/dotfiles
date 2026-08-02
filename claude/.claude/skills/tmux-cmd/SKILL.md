---
name: tmux-cmd
description: Run commands in a real TTY pane opened next to the Claude CLI, so Richard watches them live. Use when he says "use tmux", "open a pane", "run it in the pane", "let me see the commands", or when a command needs a real terminal -- TUIs, REPLs, pagers, colour output, progress bars, prompts for input. Once switched on, keep using the pane for every command until he says stop.
---

# tmux-cmd

Open a tmux pane beside the Claude CLI and drive it. The pane is a **real TTY**, so
programs behave exactly as they do for a human: colours, progress bars, `isatty()`
checks, curses UIs, and interactive prompts all work. Richard sees every command and
its output as it happens.

All of it goes through one helper:

```
claude/.claude/skills/tmux-cmd/tmux-cmd.sh
```

Refer to it as `$SKILL/tmux-cmd.sh` below. Resolve `$SKILL` to this skill's own
directory (the symlink under `~/.claude/skills/tmux-cmd` works too).

## Scope: how long to keep using the pane

Richard turns this on in one of two ways. Work out which and stick to it.

- **Blanket ("use tmux from now on", "run everything in the pane")** -- this is the
  default reading. Route **every** shell command through `tmux-cmd.sh run` for the
  rest of the session, including small ones like `ls` or `git status`. Do not drift
  back to the plain Bash tool because a command seems trivial. Keep going until he
  explicitly says to stop.
- **Targeted ("run the tests in the pane", "use tmux for the flash step")** -- use
  the pane only for the commands he named, and keep everything else on the normal
  Bash tool.

If it is genuinely unclear which he meant, ask once, then commit.

Two things stay on the normal Bash tool either way: your own private bookkeeping
(reading a file to answer a question, checking a path) and anything whose output is
so large it would flood the pane. Those are not the commands he wants to watch.

## Prerequisite

The Claude CLI must itself be running inside tmux. If `$TMUX` is unset the helper
says so -- tell Richard, and fall back to the normal Bash tool rather than trying to
start a tmux server yourself.

## Running commands

```bash
$SKILL/tmux-cmd.sh run 'pnpm test'
```

`run` creates the pane on first use, types the command so Richard sees it, waits for
it to finish, then prints just that command's output followed by `--- exit N ---`.
The helper's own exit status is the command's exit status, so you can branch on it
normally.

- `run -t SECS` sets how long to wait (default 120). On timeout you get the recent
  pane contents and exit 124; **the command keeps running** -- it is not killed.
  Either poll with `capture`, or stop it with `key C-c`.
- Multi-line commands are staged to a temp script and run with `bash`. Env vars carry
  over; shell functions and aliases from the pane's shell do not.
- Quoting is preserved exactly -- the command is typed literally, not re-parsed.

Long-running things you do not want to block on: append `&`, or send it with `send`
and check back with `capture`.

## Interactive programs

Once a REPL, TUI, or prompt owns the pane, `run` refuses (it would type into that
program instead of a shell). Drive it directly:

```bash
$SKILL/tmux-cmd.sh send 'python3 -q'      # type a line + Enter, do not wait
$SKILL/tmux-cmd.sh send '2 ** 32'
$SKILL/tmux-cmd.sh capture -n 20          # read the last 20 lines
$SKILL/tmux-cmd.sh key C-c                # tmux key names: C-c, C-d, Up, Enter, q
```

`send` and `key` return immediately -- the program is not done just because the call
returned. Sleep a beat, then `capture` to see where things landed. This is the loop
for anything that asks a question mid-run: `capture`, read the prompt, `send` the
answer.

`key` is also how you answer a pager (`q`), escape a stuck program (`C-c`), or reuse
history (`Up`, `Enter`).

## Other subcommands

```bash
$SKILL/tmux-cmd.sh open -d /path/to/repo   # explicit create; -l 50% width, -v splits below
$SKILL/tmux-cmd.sh status                  # pane id, what is running, cwd
$SKILL/tmux-cmd.sh id                      # pane id alone, empty if none
$SKILL/tmux-cmd.sh capture -a              # entire scrollback
$SKILL/tmux-cmd.sh close                   # kill the pane
```

`open` is idempotent -- calling it again returns the existing pane. Pass `-d` with
the project directory the first time so the pane starts in the right place.

Leave the pane open when the task ends. Richard uses it too, and `close` throws away
scrollback he may still want.

## How it works, and what can bite you

The pane is tagged with the id of the Claude pane that created it, so parallel Claude
sessions on the same tmux server never steal each other's pane.

`run` wraps each command as `__ccb <id>; <command>; __cce <id>` -- two helper
functions defined in the pane's shell at open time that print dimmed begin/end
markers, the end one carrying `$?`. Output is sliced from the scrollback between
those markers, so the exit code is read, never guessed. If something wipes the
helpers (`exec bash`, a fresh shell), `run` detects it and re-injects them once.

Watch out for:

- **Output beyond the scrollback limit** gets truncated -- only what tmux still holds
  can be recovered. For genuinely huge output, redirect to a file in the pane and read
  the file with the normal tools.
- **Before typing, `run` clears the prompt line** (`C-e C-u`). Anything Richard had
  half-typed and not submitted is discarded.
- **Whatever the pane displays is what you get** -- progress bars and spinners land as
  the many redraw lines they are.
- **The pane keeps state** between commands: cwd, exported vars, activated venvs. That
  is usually the point, but it means a `cd` in one command persists into the next.
