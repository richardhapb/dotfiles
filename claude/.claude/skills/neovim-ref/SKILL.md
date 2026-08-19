---
name: neovim-ref
description: Turn a set of code references into a neovim quickfix list in a tmux pane, where each entry carries the explanation of why it matters. Use when the user asks to "show me the code references", "open the references in nvim", "show me that in a pane", or after a message, review, or analysis that cites several files and lines they want to read themselves. Read-only -- the notes live in the quickfix list, never in the repo. Suggest use this when you make many changes or exploration which requires an holistic understanding from different files.
---

# Neovim reference pane

Turns `file:line` citations into a quickfix list they can step through, where **the quickfix message is the explanation**. No index file, no tab per file -- the list is the artifact.

`:copen` gives the whole argument in one screen, `]q` walks it.

## Recipe

**1. Resolve every reference to an exact line.** Never eyeball it. Replace `def` with the keyword for the language used in the project and references.

```bash
grep -n 'def some_method' path/to/file.rb | cut -d: -f1
```

Use `grep -nF` (fixed string) whenever the pattern contains `/` or `:` -- route strings like `get '/things/:id' do` otherwise get read as filenames, and the grep silently returns nothing, example for ruby:

```bash
grep -nF "get '/things/:id' do" path/to/routes.rb | cut -d: -f1
```

use whatever you need to get references of the code using this pattern.

**2. Write the quickfix file to a scratch dir**, never into a repo. One line per reference:

```
<abs path>:<line>: [tag] symbol -- why this one matters
```

```
/repo/app/handler.rb:100: [enforcement] guard_clause? -- the ONLY place the rule is enforced now
/repo/app/service.rb:1566: [hot path] create_record -- "nearly 100% of writes"
/repo/app/service.rb:514: [contrast] update! -- "really isn't used much anymore"
/other-repo/src/thing.jsx:842: [round trip] mapThing passthrough -- posted back verbatim
```

The `[tag]` is what makes the list readable as an argument rather than a pile of locations. Order follows the argument, not the filesystem. Absolute paths, so entries can span repos.

**3. Split and launch.**

```bash
tmux split-window -h -t <session> -c "<repo dir>"
sleep 1
tmux send-keys -t <session> "nvim -c 'set errorformat=%f:%l:%m' \
  -c 'cfile <refs.qf>' -c 'copen 10'" Enter
sleep 3
```

**4. Verify before saying it is ready.**

```bash
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}' | grep nvim
tmux capture-pane -p -t <session>:<win>.<pane> | tail -14
```

The capture must show the entries. `[Quickfix List]` reading `0,0-1` with nothing above it means the list is empty -- see below.

## Jumping: quickfix, not tags

Do not generate a ctags file. It is the wrong tool and needs regenerating. Quickfix is built for exactly this: a list of `file:line` plus a message, working across repos, with `:copen`, `]q`, `[q`, `<CR>`.

**`:cfile` silently loads an empty list when `errorformat` does not match.** Their config's default very likely does not match `path:line: message`, so always set it first:

```vim
:set errorformat=%f:%l:%m
:cfile /path/to/refs.qf
:copen
```

## Conventions

- **Never write into the source files.** A request for "comments so I understand" means the quickfix message, not annotations left in a repo they are mid-review on.
- **The same file twice is a feature.** Two functions as adjacent entries is what makes a "this path carries all the traffic, that one is dead" claim checkable at a glance.
- **Summarise the mapping back in chat** as a small table (entry, location, why), so they can decide what to read without switching windows.
- Tell them the keys once: `:copen`, `]q` / `[q`, `<CR>`.

## Gotchas

- `tmux split-window -t <session>` targets the session's *active* window, and they may move the pane afterwards. Re-locate it with `tmux list-panes -a` before sending more keys rather than assuming the old target.
- Sleep before `send-keys` and after, or the capture races nvim startup.
- Send `Escape` first when driving an nvim that is already open, then each `:` command separately. Chaining with `|` misfires (`:set modifiable | edit! | set nomodifiable` throws `E21`).
- If a referenced file lives in another worktree or repo, check it exists first -- a bad path just drops the entry.
