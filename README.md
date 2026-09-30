# VimShell v3.0.0

Emacs shell-mode in Vim: a normal buffer with **one persistent shell
underneath** (a job over pipes, no pty).

The shell writes straight into the buffer (Vim routes its stdout there;
nothing is captured or reimplemented). You type on the prompt lines,
which are editable like any Vim text; everything else is read-only.
What you send is exactly what you typed — no magic.

## Requirements

Vim with `+job` and `+channel` (`:echo has('job')` must show `1`).

## Installation

### vim-plug
```vim
Plug 'your-user/vimshell'
```

### Manual
Copy the `vimshell` directory to `~/.vim/pack/vimshell/start/`

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
run on a real pty in a split below — a region the app owns, with colors
and full-screen support:

```vim
:!vim file.txt
:!htop
```

It closes itself on clean exit (`:q` anytime to come back). `!` is for
long-lived interactive programs; instant output belongs in the shell
buffer (an instantly-finishing `!cmd` may leave an empty split behind —
just `:q` it).

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
completes the whole token under the cursor. Anything else is Vim's
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
| `g:vimshell_prompt` | `'vimsh$ '` | Prompt template, expanded once when the shell starts |
| `g:vimshell_tui_cmds` | (editors, pagers, monitors...) | First words that auto-open a terminal (prefix anything else with `!`) |
| `g:vimshell_term_height` | `15` | Height of the terminal split |

### Prompt variables

| Variable | Value |
|----------|-------|
| `$PWD` | Vim cwd at shell start |
| `$HOME`, `$USER`, `$HOSTNAME` | The usual ones |
| `$SHELL` | The configured shell |
| `${VAR}` | Braced form |
| `$$` | Literal `$` |

Anything else (`$?`, `$FOO`...) is removed: the prompt must stay static
so it can be recognized. Single-line prompts only.

## Honest limitations (no pty, no magic)

- **No interactive programs on the pipe**: `vim`, `less`, `htop`,
  `fzf`... need a terminal — use `!cmd` (real pty in a split below).
  `clear` works (handled by the buffer).
- **fish doesn't work** as the inferior shell: with piped stdin it reads
  to EOF before executing anything. If your `$SHELL` is fish, VimShell
  warns and falls back to `sh` (override with `g:vimshell_shell`).
- **The prompt is static**: expanded once at shell start. `cd` still
  moves Vim too (plain paths), which keeps completion honest, but the
  printed prompt won't follow.
- If your rc prints a prompt unconditionally you'll see extra lines:
  guard it with `[ -t 1 ] && PS1=...`.

## License

MIT
