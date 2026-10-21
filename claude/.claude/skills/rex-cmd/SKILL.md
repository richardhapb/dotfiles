---
name: rex-cmd
description: Run commands in a real TTY pane opened next to the Claude CLI, so Richard watches them live. Use when he says "use rex", "open a pane", "run it in the pane", "let me see the commands", or when a command needs a real terminal -- TUIs, REPLs, pagers, colour output, progress bars, prompts for input. Once switched on, keep using the pane for every command until he says stop.
---

# rex-cmd

Open a Rex pane beside the Claude CLI and drive it. The pane is a **real TTY**, so
programs behave exactly as they do for a human: colours, progress bars, `isatty()`
checks, curses UIs, and interactive prompts all work. Richard sees every command and
its output as it happens.

All of it goes through one helper:

```
claude/.claude/skills/rex-cmd/rex-cmd.sh
```

Refer to it as `$SKILL/rex-cmd.sh` below. Resolve `$SKILL` to this skill's own
directory (the symlink under `~/.claude/skills/rex-cmd` works too).

## Scope: how long to keep using the pane

Richard turns this on in one of two ways. Work out which and stick to it.

- **Blanket ("use rex from now on", "run everything in the pane")** -- this is the
  default reading. Route **every** shell command through `rex-cmd.sh run` for the
  rest of the session, including small ones like `ls` or `git status`. Do not drift
  back to the plain Bash tool because a command seems trivial. Keep going until he
  explicitly says to stop.
- **Targeted ("run the tests in the pane", "use rex for the flash step")** -- use
  the pane only for the commands he named, and keep everything else on the normal
  Bash tool.

If it is genuinely unclear which he meant, ask once, then commit.

Two things stay on the normal Bash tool either way: your own private bookkeeping
(reading a file to answer a question, checking a path) and anything whose output is
so large it would flood the pane. Those are not the commands he wants to watch.

## Prerequisite

The Claude CLI must itself be running inside a Rex pane. If `$REX_SESSION` or
`$REX_BLOCK` is unset the helper says so -- tell Richard, and fall back to the normal
Bash tool rather than trying to start anything yourself.

## Running commands

```bash
$SKILL/rex-cmd.sh run 'pnpm test'
```

`run` creates the pane on first use, types the command so Richard sees it, waits for
it to finish, then prints just that command's output followed by `--- exit N ---`.
The helper's own exit status is the command's exit status, so you can branch on it
normally.

- `run -t SECS` sets how long to wait (default 120). On timeout you get the recent
  pane contents and exit 124; **the command keeps running** -- it is not killed.
  Either poll with `capture`, or stop it with `key ctrl+c`.
- Multi-line commands are staged to a temp script and run with `bash`. Env vars carry
  over; shell functions and aliases from the pane's shell do not.
- Quoting is preserved exactly -- the command is typed literally, not re-parsed.

Long-running things you do not want to block on: append `&`, or send it with `send`
and check back with `capture`.

## Interactive programs

Once a REPL, TUI, or prompt owns the pane, `run` refuses (it would type into that
program instead of a shell). Drive it directly:

```bash
$SKILL/rex-cmd.sh send 'python3 -q'      # type a line + Enter, do not wait
$SKILL/rex-cmd.sh send '2 ** 32'
$SKILL/rex-cmd.sh capture -n 20          # read the last 20 lines
$SKILL/rex-cmd.sh key ctrl+c             # Rex key names: ctrl+c, ctrl+d, up, enter, q
```

`send` and `key` return immediately -- the program is not done just because the call
returned. Sleep a beat, then `capture` to see where things landed. This is the loop
for anything that asks a question mid-run: `capture`, read the prompt, `send` the
answer.

`key` is also how you answer a pager (`q`), escape a stuck program (`ctrl+c`), or
reuse history (`up`, `enter`).

## Other subcommands

```bash
$SKILL/rex-cmd.sh open -d /path/to/repo   # explicit create; -l 50 width %, -v splits below
$SKILL/rex-cmd.sh status                  # pane id, what is running, cwd
$SKILL/rex-cmd.sh id                      # pane id alone, empty if none
$SKILL/rex-cmd.sh capture -a              # entire scrollback
$SKILL/rex-cmd.sh close                   # close the pane
```

`open` is idempotent -- calling it again returns the existing pane. Pass `-d` with
the project directory the first time so the pane starts in the right place. The pane
opens without taking focus, so Richard's cursor stays where it was.

Leave the pane open when the task ends. Richard uses it too, and `close` throws away
scrollback he may still want.

## How it works, and what can bite you

The pane carries the label `claude-cmd-<id>` where `<id>` is the tail of the Claude
pane's `$REX_BLOCK`, so parallel Claude sessions in the same Rex session never steal
each other's pane. Renaming that label orphans the pane.

`run` wraps each command as `__ccb <id>; <command>; __cce <id>` -- two helper
functions defined in the pane's shell at open time that print dimmed begin/end
markers, the end one carrying `$?`. Output is sliced from the pane's text between
those markers, so the exit code is read, never guessed. If something wipes the
helpers (`exec bash`, a fresh shell), `run` detects it and re-injects them once.

Watch out for:

- **Output beyond the scrollback limit** gets truncated -- only what Rex still holds
  can be recovered. For genuinely huge output, redirect to a file in the pane and read
  the file with the normal tools.
- **Before typing, `run` clears the prompt line** (`ctrl+e ctrl+u`). Anything Richard
  had half-typed and not submitted is discarded.
- **Whatever the pane displays is what you get** -- progress bars and spinners land as
  the many redraw lines they are.
- **The pane keeps state** between commands: cwd, exported vars, activated venvs. That
  is usually the point, but it means a `cd` in one command persists into the next.
- **A fresh pane reports `login` as its process** for a moment; `open` waits for the
  shell before typing.
