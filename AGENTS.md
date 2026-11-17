# VimShell — AI Agent Guidelines

## Project Overview

VimShell is an Emacs shell-mode plugin for Vim. It runs a single persistent shell process over pipes (no pty) inside a Vim buffer. Prompt lines are editable; output is appended verbatim via callbacks. Interactive programs (vim, htop, less...) run in a real pty tab via `!cmd` prefix.

## Architecture

- **`plugin/vimshell.vim`** — Entry point. Defines `:VimShell`, `:VimShellOpen`, `:VimShellSplit`, `:VimShellVSplit`, `:VimShellShell`.
- **`autoload/vimshell.vim`** — Core logic: job lifecycle, buffer setup, prompt expansion, history, completion, output handling, terminal regions.
- **`syntax/vimshell.vim`** — Syntax highlighting for shell constructs (prompt, strings, variables, flags, errors).
- **`doc/vimshell.txt`** — Vim help documentation (`:help vimshell`).

## Key Functions

| Function | Purpose |
|----------|---------|
| `vimshell#Open()` | Create buffer, start shell job |
| `vimshell#ExecuteLine()` | Send command to shell, handle `cd` sync |
| `vimshell#Complete()` | Tab completion: commands, paths, flags |
| `s:CompletePath()` | Path expansion and directory listing |
| `s:Escape()` | Shell metacharacter escaping for completed paths |
| `s:Unescape()` | Reverse backslash escaping before matching |
| `vimshell#OnOut/OnErr/OnExit()` | Channel callbacks for shell I/O |

## Code Style

- Vimscript 2-style not used; traditional Vimscript with `l:`, `b:`, `g:`, `s:` scoping.
- No KDoc-style comments; brief inline comments explain non-obvious logic.
- Functions use `s:` prefix for script-local, `vimshell#` for public autoload.
- `abort` on every function to fail fast.
- `set cpo&vim` in plugin file for portable behavior.
- No external dependencies beyond Vim's built-in `job`/`channel` support.

## Completion Logic

Tab completion in `vimshell#Complete()` works in three modes:
1. **Commands** — First word (no space in input): matches against `$PATH` cache + builtins.
2. **Flags** — Fragment starts with `-`: parses `--help` output, cached per command.
3. **Paths** — After a space or when fragment contains `/`, `.`, or `~`: expands via `s:CompletePath()`.

Path completion handles `~/` (home), absolute (`/`), and relative paths. Completed names are backslash-escaped via `s:Escape()` so spaces and metacharacters don't break the command. The `~` character at the start of a path is preserved (not escaped) since it's a valid shell shorthand.

## Testing

No test framework. Manual verification in Vim:
```
vim -u NONE -U NONE -N --noplugin -c "set rtp+=." -c "VimShell"
```

## Configuration Variables

- `g:vimshell_shell` — Shell command (default: `$SHELL`)
- `g:vimshell_prompt` — Prompt template with `$VAR` expansion (default: `'vimsh$ '`)
- `g:vimshell_tui_cmds` — List of commands that auto-open a pty tab
