# VimShell v3.0.0

Emacs shell-mode in Vim: a normal buffer with **one persistent shell
underneath** (a job over pipes, no pty).

Output flows through plain callbacks that append it verbatim — no
shell logic is reimplemented anywhere (Vim's native buffer-append was
observed dropping data, so bytes travel the explicit path). You type
on the prompt lines, which are editable like any Vim text; everything
else is read-only. What you send is exactly what you typed — no magic.

## Requirements

Vim with `+job` and `+channel` (`:echo has('job')` must show `1`).

## Installation

### vim-plug
```vim
Plug 'your-user/vimshell'
```

### Manual
Copy the `vimshell` directory to `~/.vim/pack/vimshell/start/` (or
`~/.vim/plugged/vimshell/` if you use vim-plug).

## Usage

```vim
:VimShell          " Open in current window
:VimShellOpen      " Open in a new window
:VimShellSplit     " Open in a horizontal split
:VimShellVSplit    " Open in a vertical split
```

Type on a prompt line, `RET` sends it. `RET` on an old line copies it to
a fresh prompt instead of executing (like Emacs). `RET` on empty input
sends a newline. `exit` kills the shell; `RET` restarts it.

## Interactive programs (real tty)

Prefix with `!` (or use a known name like `vim`, `htop`, `less`...) to
run on a real pty in a new full-size tab — a region the app owns, with
colors and fullscreen support. Focus lands there ready to type.

It closes itself on clean exit; otherwise come back with `:q` (from
normal mode — `CTRL-W N` first if you're typing into the app). `!` is
for long-lived interactive programs; instant output belongs in the
shell buffer.

## Keys (Emacs-like)

| Key | Action |
|-----|--------|
| `<CR>` | Send the current prompt line (`RET`) |
| `<CR>` on old line | Copy it to a fresh prompt |
| `<C-p>` / `<Up>`, `<C-n>` / `<Down>` | History (`M-p` / `M-n`) |
| `<Tab>` | Complete: commands, paths or flags (`-x`, `--long`) |
| `<C-c>` | Real SIGINT to the job |
| `<C-d>` | EOF (with empty input; closes the shell) |
| `<C-l>` | Clear the buffer |

One `<Tab>` candidate replaces the fragment (commands and flags with a
trailing space, directories with `/`); several extend the common prefix
or get listed **right in the buffer** without touching what you typed.
Flags come from `--help` (cached per command). Works mid-line: it
completes the whole token under the cursor. Completed paths come back
escaped (`my\ dir/a\ file.txt`), so they run as typed, and `<Tab>`
keeps descending inside them. Anything else is Vim's
native completion on editable text (`CTRL-X CTRL-F`, `CTRL-N`...).

The buffer has shell highlighting (prompt, strings, `$variables`,
comments, numbers, operators, flags, and anything that smells like an
error).

## Configuration

```vim
let g:vimshell_shell = 'bash'
let g:vimshell_prompt = '❮$PWD❯ ~> '
```

| Variable | Default | Description |
|----------|---------|-------------|
| `g:vimshell_shell` | `$SHELL` (or `sh`) | Shell to run with `-i` so it loads your rc (`:VimShellShell` changes it at runtime for new buffers) |
| `g:vimshell_prompt` | `'vimsh$ '` | Prompt template, expanded at shell start and on every plain `cd` so `$PWD` follows you |
| `g:vimshell_tui_cmds` | (editors, pagers, monitors...) | First words that auto-open a terminal (prefix anything else with `!`) |

### Prompt variables

| Variable | Value |
|----------|-------|
| `$PWD` | Vim cwd at shell start |
| `$HOME`, `$USER`, `$HOSTNAME` | The usual ones |
| `$SHELL` | The configured shell |
| `$NAME` | Any environment variable, expanded once (missing is removed) |
| `${VAR}` | Braced form |
| `$$` | Literal `$` |

A lone `$` is literal. Anything else (`$?`, `$#`...) is removed: the
prompt must stay static so it can be recognized. Single-line prompts
only.

## Honest limitations (no pty, no magic)

- **No interactive programs on the pipe**: `vim`, `less`, `htop`,
  `fzf`... need a terminal — use `!cmd` (real pty in a split below).
  `clear` works (handled by the buffer).
- **fish doesn't work** as the inferior shell: with piped stdin it reads
  to EOF before executing anything. If your `$SHELL` is fish, VimShell
  warns and falls back to `sh` (override with `g:vimshell_shell`).
- **The prompt follows plain `cd`**: Vim `:cd`s along (keeps
  completion honest) and the shell reprints with fresh variables; old
  prompts stay recognized as history. Fancier `cd` (vars, globs,
  quotes) or a direct `:cd` moves only one side — plain `cd` (or a new
  buffer) re-syncs.
- If your rc prints a prompt unconditionally you'll see extra lines:
  guard it with `[ -t 1 ] && PS1=...`.

## License

MIT
