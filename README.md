# VimShell v2.0.0

Emacs shell-mode in Vim: a normal, editable buffer with **one persistent
shell underneath** (a job over pipes, no pty).

Vim only carries prompt lines to the shell and pastes back the output;
the shell handles everything: `cd`, aliases, variables, functions,
pipes, `&&`... they persist on their own because the process is always
the same. `exit` kills the shell and `RET` restarts it.

## Requirements

Vim with `+job` and `+channel` (`:echo has('job')` must show `1`).

## Installation

### Pathogen
```bash
cd ~/.vim/bundle
git clone <url> vimshell
```

### vim-plug
```vim
Plug 'patrick-nonedev/vimshell'
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

## Keys (Emacs-like)

| Key | Action |
|-----|--------|
| `<CR>` | Execute the line (`RET`) |
| `<CR>` on old line | Copy it to the prompt without executing |
| `<C-p>` / `<Up>`, `<C-n>` / `<Down>` | History (`M-p` / `M-n`) |
| `<Tab>` | Complete: commands, paths or flags (`-x`, `--long`) |
| `<C-c>` | Real SIGINT to the job |
| `<C-d>` | EOF (with empty input; closes the shell) |
| `<C-l>` | Clear the buffer |

One `<Tab>` candidate replaces the fragment (commands and flags with a
trailing space, directories with `/`); several extend the common prefix
or get listed **right in the buffer**, above the prompt, without touching
what you typed (keep typing to narrow it down, or `RET` on an old line
copies it). Flags come from `--help` (cached per command). Works
mid-line: it completes the whole token under the cursor. Anything else
is Vim's native completion on an editable buffer (`CTRL-X CTRL-F`,
`CTRL-N`...).

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
| `g:vimshell_prompt` | `'vimsh$ '` | Prompt template, with variables (expanded when printed) |

### Prompt variables

| Variable | Value |
|----------|-------|
| `$PWD` | Vim cwd (plain `cd <dir>` in the shell `:cd`s along) |
| `$HOME`, `$USER`, `$HOSTNAME` | The usual ones |
| `$SHELL` | The configured shell |
| `${VAR}` | Braced form |
| `$$` | Literal `$` |

Unknown names (`$?`, `$FOO`...) are left alone.

## Honest limitations (no pty, no magic)

- **No interactive programs**: `vim`, `less`, `htop`, `fzf`... need a
  terminal. Use `:terminal` for those. `clear` works (handled by the
  buffer).
- **fish doesn't work** as the inferior shell: with piped stdin it reads
  to EOF before executing anything. If your `$SHELL` is fish, VimShell
  warns and falls back to `sh` (override with `g:vimshell_shell`).
- **The prompt is static**: it expands when printed; `$PWD` is Vim's cwd
  (a plain `cd` in the shell syncs it via `:cd`, but a `cd` with
  vars/globs or inside a script does not).
- **`cd` only moves Vim for plain paths**: shell and Vim have different
  cwds unless the command is `cd <dir>` or bare `cd`.
- If your rc prints a prompt unconditionally you'll see extra lines:
  guard it with `[ -t 1 ] && PS1=...`.

## License

MIT
