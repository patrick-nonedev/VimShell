" vimshell: Emacs shell-mode in Vim.
" Editable input over one persistent shell job. Output goes straight
" from the shell to the buffer (out_io=buffer); only the prompt lines
" are editable, everything else is read-only.

let s:prompt_default = 'vimsh$ '
let s:history_max = 1000
let s:ps2 = '> '
let s:noise = 'terminal process group\|grupo de proceso de terminal\|no job control in this shell\|no hay control de trabajos en este shell'

function! vimshell#Open(kind) abort
  if !has('job') || !has('channel')
    echoerr '[vimshell] this Vim needs +job/+channel support'
    return
  endif
  if a:kind ==# 'curwin'
    enew
  elseif a:kind ==# 'new'
    new
  elseif a:kind ==# 'split'
    split
  elseif a:kind ==# 'vsplit'
    vsplit
  else
    echoerr '[vimshell] bad window kind: ' . a:kind
    return
  endif
  call s:SetupBuffer()
  let b:vimshell_ps1 = s:ShellPrompt()
  call s:DefinePromptSyntax()
  call s:StartJob()
  if !get(b:, 'vimshell_dead', 0)
    setlocal modifiable
    silent! startinsert!
  endif
endfunction

function! s:SetupBuffer() abort
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
  setlocal filetype=vimshell
  setlocal nowrap nonumber norelativenumber nocursorline nolist
  setlocal nomodifiable
  let b:vimshell_history = []
  let b:vimshell_history_idx = 0
  let b:vimshell_dead = 0
  let b:vimshell_ps1 = ''
  let b:vimshell_last_list = ''
  nnoremap <buffer> <CR> :call vimshell#ExecuteLine()<CR>
  inoremap <buffer> <CR> <C-o>:call vimshell#ExecuteLine()<CR>
  inoremap <buffer> <C-p> <C-o>:call vimshell#HistoryPrev()<CR>
  inoremap <buffer> <C-n> <C-o>:call vimshell#HistoryNext()<CR>
  inoremap <buffer> <Up> <C-o>:call vimshell#HistoryPrev()<CR>
  inoremap <buffer> <Down> <C-o>:call vimshell#HistoryNext()<CR>
  nnoremap <buffer> <C-p> :call vimshell#HistoryPrev()<CR>
  nnoremap <buffer> <C-n> :call vimshell#HistoryNext()<CR>
  nnoremap <buffer> <Up> :call vimshell#HistoryPrev()<CR>
  nnoremap <buffer> <Down> :call vimshell#HistoryNext()<CR>
  inoremap <buffer> <C-c> <C-o>:call vimshell#Interrupt()<CR>
  inoremap <buffer> <C-d> <C-o>:call vimshell#Eof()<CR>
  nnoremap <buffer> <C-d> :call vimshell#Eof()<CR>
  inoremap <buffer> <C-l> <C-o>:call vimshell#ClearScreen()<CR>
  nnoremap <buffer> <C-l> :call vimshell#ClearScreen()<CR>
  inoremap <expr> <buffer> <Tab> pumvisible() ? "\<C-n>" : "\<C-o>:call vimshell#Complete()<CR>"
  autocmd CursorMoved,CursorMovedI,BufEnter <buffer> call vimshell#SyncModifiable()
endfunction

" Prompt template from config.
function! s:Prompt() abort
  return get(g:, 'vimshell_prompt', s:prompt_default)
endfunction

" Expanded prompt for PS1. Unknown $vars are removed: a dynamic PS1
" would break prefix matching, so only the documented ones survive.
function! s:ExpandPrompt() abort
  let l:p = substitute(s:Prompt(), '\$\$', "\x01", 'g')
  let l:shell = split(get(g:, 'vimshell_shell', $SHELL))
  let l:vars = {'PWD': getcwd(), 'HOME': $HOME, 'USER': $USER,
        \ 'SHELL': empty(l:shell) ? 'sh' : l:shell[0],
        \ 'HOSTNAME': hostname()}
  for [l:k, l:v] in items(l:vars)
    let l:p = substitute(l:p, '\${' . l:k . '}', '\=' . string(l:v), 'g')
    let l:p = substitute(l:p, '\$' . l:k . '\>', '\=' . string(l:v), 'g')
  endfor
  let l:p = substitute(l:p, '\${\w\+}', '', 'g')
  let l:p = substitute(l:p, '\$\w\+', '', 'g')
  return substitute(l:p, "\x01", '$', 'g')
endfunction

" PS1 text as printed by the shell (single expansion per session).
function! s:ShellPrompt() abort
  return s:ExpandPrompt()
endfunction

function! s:DefinePromptSyntax() abort
  silent! syntax clear vimshellPrompt
  silent! syntax clear vimshellCont
  execute 'syntax match vimshellPrompt /^\V' . escape(b:vimshell_ps1, '/\') . '/'
  execute 'syntax match vimshellCont /^\V' . escape(s:ps2, '/\') . '/'
endfunction

function! s:ShellArgv() abort
  let l:shell = get(g:, 'vimshell_shell', $SHELL)
  let l:argv = split(l:shell)
  if empty(l:argv)
    let l:argv = ['sh']
  endif
  if !executable(l:argv[0])
    return []
  endif
  if l:argv[0] =~# 'fish$'
    " fish with piped stdin reads to EOF before executing: unusable
    " as an inferior interactive shell (same as in Emacs shell-mode).
    call s:Note('[vimshell] fish needs a tty, falling back to sh (set g:vimshell_shell to override)')
    let l:argv = ['sh']
  endif
  " -i loads the rc file. bash needs --noediting: it uses readline
  " even on pipes (stderr echo and dangerous TABs). Matched on the
  " resolved binary (sh is often a symlink).
  if resolve(exepath(l:argv[0])) =~# 'bash'
    let l:argv += ['--noediting', '-i']
  else
    let l:argv += ['-i']
  endif
  return l:argv
endfunction

function! s:StartJob() abort
  let l:argv = s:ShellArgv()
  if empty(l:argv)
    call s:Note('[vimshell] shell not found: ' . get(g:, 'vimshell_shell', $SHELL))
    let b:vimshell_dead = 1
    return
  endif
  " PS1 ends with newline so prompts flush as complete lines instead
  " of merging with the next output line.
  let l:ps1 = b:vimshell_ps1 . (b:vimshell_ps1 =~# '\n$' ? '' : "\n")
  call s:Unlock()
  let b:vimshell_job = job_start(l:argv, {
        \ 'in_io': 'pipe',
        \ 'out_io': 'buffer',
        \ 'out_buf': bufnr(''),
        \ 'err_io': 'pipe',
        \ 'err_cb': function('vimshell#OnErr', [bufnr('')]),
        \ 'exit_cb': function('vimshell#OnExit', [bufnr('')]),
        \ 'env': {'TERM': 'dumb', 'PAGER': 'cat', 'MANPAGER': 'cat',
        \         'PS1': l:ps1, 'PS2': s:ps2}})
  if job_status(b:vimshell_job) !=# 'run'
    call s:Note('[vimshell] could not start: ' . join(l:argv))
    let b:vimshell_dead = 1
  else
    let b:vimshell_dead = 0
  endif
endfunction

" Read-only everywhere except empty buffer and prompt lines.
function! vimshell#SyncModifiable() abort
  if getline('.') ==# ''
    setlocal modifiable
    return
  endif
  let l:line = getline('.')
  let l:ps1 = get(b:, 'vimshell_ps1', '')
  if l:ps1 !=# '' && strpart(l:line, 0, len(l:ps1)) ==# l:ps1
    setlocal modifiable
    return
  endif
  if strpart(l:line, 0, len(s:ps2)) ==# s:ps2
    setlocal modifiable
    return
  endif
  setlocal nomodifiable
endfunction

function! s:Unlock() abort
  call setbufvar(bufnr(''), '&modifiable', 1)
endfunction

function! s:FixModifiable(buf) abort
  if bufnr('') == a:buf
    call vimshell#SyncModifiable()
  else
    call setbufvar(a:buf, '&modifiable', 0)
  endif
endfunction

function! s:StripPrompt(line) abort
  let l:ps1 = get(b:, 'vimshell_ps1', '')
  if l:ps1 !=# '' && strpart(a:line, 0, len(l:ps1)) ==# l:ps1
    return strpart(a:line, len(l:ps1))
  endif
  if strpart(a:line, 0, len(s:ps2)) ==# s:ps2
    return strpart(a:line, len(s:ps2))
  endif
  return a:line
endfunction

function! vimshell#ExecuteLine() abort
  if get(b:, 'vimshell_dead', 0)
    call s:StartJob()
    if get(b:, 'vimshell_dead', 0)
      return
    endif
    return
  endif
  let l:cur = getline('.')
  if l:cur ==# ''
    call s:SendRaw("\n")
    call cursor(line('$'), col('$'))
    return
  endif
  let l:prompt = get(b:, 'vimshell_ps1', '')
  if l:prompt ==# '' || strpart(l:cur, 0, len(l:prompt)) !=# l:prompt
    if strpart(l:cur, 0, len(s:ps2)) !=# s:ps2
      call s:CopyToPrompt(l:cur)
      return
    endif
  endif
  let l:cmd = s:StripPrompt(l:cur)
  if l:cmd ==# ''
    call s:SendRaw("\n")
    call cursor(line('$'), col('$'))
    return
  endif
  " !cmd, or a known interactive program, runs on a real pty in a
  " split below (region) instead of the dumb pipe.
  let l:typed = l:cmd
  if l:cmd =~# '^\s*!'
    let l:cmd = substitute(l:cmd, '^\s*!\s*', '', '')
    if l:cmd ==# ''
      return
    endif
  elseif !s:IsTUI(l:cmd)
    let l:typed = ''
  endif
  if l:typed !=# ''
    call add(b:vimshell_history, l:typed)
    if len(b:vimshell_history) > s:history_max
      call remove(b:vimshell_history, 0)
    endif
    let b:vimshell_history_idx = len(b:vimshell_history)
    call s:RunInTerminal(l:cmd)
    return
  endif
  " clear is buffer business (TERM=dumb has no escapes).
  if l:cmd =~# '^\s*clear\s*$'
    call vimshell#ClearScreen()
    return
  endif
  call add(b:vimshell_history, l:cmd)
  if len(b:vimshell_history) > s:history_max
    call remove(b:vimshell_history, 0)
  endif
  let b:vimshell_history_idx = len(b:vimshell_history)
  " Plain `cd <dir>` also :cds so $PWD-based completion stays truthful.
  " Anything fancier (vars, globs, quotes) moves only the shell.
  if l:cmd =~# '^\s*cd\s*$'
    execute 'cd ' . fnameescape($HOME)
  else
    let l:cdarg = matchstr(l:cmd, '^\s*cd\s\+\zs[^ \t;|&]\+')
    if l:cdarg !=# '' && l:cdarg !~# '[$`"''*?{}\\!]'
      let l:cdarg = substitute(l:cdarg, '^\~', $HOME, '')
      if isdirectory(l:cdarg)
        execute 'cd ' . fnameescape(l:cdarg)
      endif
    endif
  endif
  if !exists('b:vimshell_job') || job_status(b:vimshell_job) !=# 'run'
    let b:vimshell_dead = 1
    call s:Note('[vimshell] process is not running')
    return
  endif
  call s:SendRaw(l:cmd . "\n")
  call cursor(line('$'), col('$'))
endfunction

" Copy old text to a fresh prompt line without executing (Emacs).
function! s:CopyToPrompt(text) abort
  call s:Unlock()
  let l:prompt = get(b:, 'vimshell_ps1', '')
  if line('$') > 1 || getline(1) !=# ''
    let l:last = getline('$')
    if l:prompt ==# '' || strpart(l:last, 0, len(l:prompt)) !=# l:prompt
      call append(line('$'), l:prompt . a:text)
      call cursor(line('$'), col('$'))
      call s:FixModifiable(bufnr(''))
      silent! startinsert!
      return
    endif
  endif
  call setline(line('$'), l:prompt . a:text)
  call cursor(line('$'), col('$'))
  call s:FixModifiable(bufnr(''))
  silent! startinsert!
endfunction

function! s:SendRaw(text) abort
  if !exists('b:vimshell_job') || job_status(b:vimshell_job) !=# 'run'
    let b:vimshell_dead = 1
    call s:Note('[vimshell] process is not running')
    return
  endif
  try
    call ch_sendraw(b:vimshell_job, a:text)
  catch
    let b:vimshell_dead = 1
    call s:Note('[vimshell] process is not running')
  endtry
endfunction

function! vimshell#HistoryPrev() abort
  call s:HistoryGo(-1)
endfunction

function! vimshell#HistoryNext() abort
  call s:HistoryGo(1)
endfunction

function! s:HistoryGo(dir) abort
  if empty(get(b:, 'vimshell_history', []))
    return
  endif
  let b:vimshell_history_idx += a:dir
  let b:vimshell_history_idx = max([0, min([b:vimshell_history_idx, len(b:vimshell_history)])])
  let l:cmd = b:vimshell_history_idx < len(b:vimshell_history)
        \ ? b:vimshell_history[b:vimshell_history_idx] : ''
  let l:lnum = s:PromptLine()
  if l:lnum == 0
    call s:Unlock()
    call append(line('$'), get(b:, 'vimshell_ps1', '') . l:cmd)
    let l:lnum = line('$')
  else
    call s:Unlock()
    call setline(l:lnum, get(b:, 'vimshell_ps1', '') . l:cmd)
  endif
  call cursor(l:lnum, col('$'))
  call s:FixModifiable(bufnr(''))
endfunction

function! vimshell#Interrupt() abort
  if exists('b:vimshell_job') && job_status(b:vimshell_job) ==# 'run'
    call job_stop(b:vimshell_job, 'int')
  endif
endfunction

function! vimshell#Eof() abort
  if get(b:, 'vimshell_dead', 0)
    return
  endif
  let l:cur = getline('.')
  if s:StripPrompt(l:cur) ==# '' && exists('b:vimshell_job')
    silent! call ch_close_in(b:vimshell_job)
  endif
endfunction

function! vimshell#ClearScreen() abort
  call s:Unlock()
  silent! %delete _
  call cursor(1, 1)
  call s:FixModifiable(bufnr(''))
  silent! startinsert!
  " Summon a fresh prompt like a real clear does.
  if !get(b:, 'vimshell_dead', 0) && exists('b:vimshell_job') && job_status(b:vimshell_job) ==# 'run'
    call s:SendRaw("\n")
  endif
endfunction

let s:tui_default = ['vim', 'nvim', 'vi', 'ex', 'view', 'emacs', 'nano', 'pico', 'micro', 'helix', 'hx', 'kak', 'less', 'more', 'most', 'man', 'htop', 'top', 'btop', 'atop', 'tmux', 'screen', 'zellij', 'tig', 'fzf', 'ranger', 'mc', 'vifm', 'nnn', 'ssh', 'mosh']

" First word against the interactive list (or force with !cmd).
function! s:IsTUI(cmd) abort
  let l:first = matchstr(a:cmd, '^\s*\zs\S\+')
  return index(get(g:, 'vimshell_tui_cmds', s:tui_default), l:first) >= 0
endfunction

function! vimshell#IsTUI(cmd) abort
  return s:IsTUI(a:cmd)
endfunction

" Run on a real pty for interactive programs. Spawned hidden (a
" visible spawn stalls while a buffered job runs) and shown at once;
" long-lived TUIs are alive by then. Closes itself on clean exit, and
" instantly-finished commands close right away (:q returns to shell).
function! s:RunInTerminal(cmd) abort
  let l:shell = split(get(g:, 'vimshell_shell', $SHELL))
  if empty(l:shell)
    let l:shell = ['sh']
  endif
  if !executable(l:shell[0])
    echoerr '[vimshell] shell not found: ' . join(l:shell)
    return
  endif
  if resolve(exepath(l:shell[0])) =~# 'bash'
    let l:argv = l:shell + ['-i', '-c', a:cmd]
  else
    let l:argv = l:shell + ['-c', a:cmd]
  endif
  let l:tb = term_start(l:argv, {'hidden': 1, 'term_finish': 'close'})
  if l:tb <= 0 || !bufexists(l:tb)
    echoerr '[vimshell] could not open terminal'
    return
  endif
  execute 'belowright ' . get(g:, 'vimshell_term_height', 15) . 'split'
  execute 'buffer ' . l:tb
  call setbufvar(l:tb, 'vimshell_term', 1)
  if s:TermDead(l:tb)
    close
  else
    call s:EnsureReaper()
  endif
endfunction

" Level-triggered reaper for our terminals: edge events get lost while
" a buffered job runs, so poll every 2s instead. Death is verified
" against the OS (/proc), not Vim's bookkeeping, which can wedge.
" Stops when none left.
function! s:EnsureReaper() abort
  if !exists('s:reaper') || s:reaper < 0
    let s:reaper = timer_start(2000, function('s:ReapTerminals'), {'repeat': -1})
  endif
endfunction

function! s:TermDead(tb) abort
  try
    let l:job = term_getjob(a:tb)
    if job_status(l:job) !=# 'run'
      return 1
    endif
    if isdirectory('/proc')
      let l:pid = get(job_info(l:job), 'process', 0)
      return l:pid > 0 && !isdirectory('/proc/' .. l:pid)
    endif
  catch
  endtry
  return 0
endfunction

function! s:ReapTerminals(timer) abort
  let l:any = 0
  for l:n in range(1, bufnr('$'))
    if !getbufvar(l:n, 'vimshell_term', 0)
      continue
    endif
    try
      let l:dead = s:TermDead(l:n)
    catch
      let l:dead = 1
    endtry
    let l:found = 0
    for l:w in range(1, winnr('$'))
      if winbufnr(l:w) == l:n
        let l:found = 1
        if l:dead && winnr('$') > 1
          call win_execute(win_getid(l:w), 'close')
        endif
      endif
    endfor
    if l:dead && !l:found
      call setbufvar(l:n, 'vimshell_term', 0)
    else
      let l:any = 1
    endif
  endfor
  if !l:any
    call timer_stop(a:timer)
    let s:reaper = -1
  endif
endfunction

function! vimshell#SetShell(shell) abort
  let l:parts = split(a:shell)
  if empty(l:parts) || !executable(l:parts[0])
    echoerr '[vimshell] shell not found: ' . a:shell
    return
  endif
  let g:vimshell_shell = a:shell
  echo '[vimshell] shell set to ' . a:shell . ' (new buffers)'
endfunction

" Common builtins for first-word completion (plus $PATH).
let s:builtins = ['alias', 'bg', 'break', 'builtin', 'cd', 'command', 'continue', 'echo', 'eval', 'exec', 'exit', 'export', 'false', 'fg', 'getopts', 'hash', 'help', 'history', 'jobs', 'kill', 'let', 'local', 'printf', 'pwd', 'read', 'readonly', 'return', 'set', 'shift', 'source', 'suspend', 'test', 'times', 'trap', 'true', 'type', 'ulimit', 'umask', 'unalias', 'unset', 'wait']

function! s:PathCommands() abort
  if !exists('g:vimshell_path_cache')
    let l:cmds = {}
    for l:dir in split($PATH, ':')
      if isdirectory(l:dir)
        for l:f in readdir(l:dir)
          let l:cmds[l:f] = 1
        endfor
      endif
    endfor
    let g:vimshell_path_cache = keys(l:cmds)
  endif
  return g:vimshell_path_cache
endfunction

function! s:CommandFlags(cmd) abort
  if !exists('g:vimshell_flags_cache')
    let g:vimshell_flags_cache = {}
  endif
  if !has_key(g:vimshell_flags_cache, a:cmd)
    let g:vimshell_flags_cache[a:cmd] = s:ReadFlags(a:cmd)
  endif
  return g:vimshell_flags_cache[a:cmd]
endfunction

function! s:ReadFlags(cmd) abort
  " Only sane names: --help must not execute anything odd.
  if a:cmd !~# '^[A-Za-z0-9_./+:-]\+$' || !executable(a:cmd)
    return []
  endif
  let l:help = system(a:cmd . ' --help 2>&1')
  if v:shell_error != 0
    let l:help = system(a:cmd . ' -h 2>&1')
    if v:shell_error != 0
      return []
    endif
  endif
  let l:like_help = l:help =~? 'usage\|option\|flag'
  " Strip escapes (some --help output is hyperlinked).
  let l:help = substitute(l:help, "\e\\][^\\\\\\x07]*\\(\\\\\\|\x07\\)", '', 'g')
  let l:help = substitute(l:help, "\e\\[[0-9; ?]*[a-zA-Z]", '', 'g')
  let l:found = {}
  for l:tok in split(l:help)
    let l:tok = substitute(l:tok, '^[[(]*', '', '')
    let l:tok = substitute(l:tok, '[,.:;)\]]*$', '', '')
    let l:tok = substitute(l:tok, '[=\[].*', '', '')
    if l:tok =~# '^--[a-zA-Z][a-zA-Z0-9-]*$'
      let l:found[l:tok] = 1
    elseif l:like_help && l:tok =~# '^-[a-zA-Z]$'
      let l:found[l:tok] = 1
    endif
  endfor
  return sort(keys(l:found))
endfunction

function! s:CompletePath(frag) abort
  if a:frag ==# ''
    let l:exp = ''
  elseif a:frag[0] ==# '~'
    let l:exp = $HOME . strpart(a:frag, 1)
  else
    let l:exp = a:frag
  endif
  let l:slash = strridx(l:exp, '/')
  if l:slash < 0
    let l:dir = '.'
    let l:base = l:exp
    let l:keep = ''
  elseif l:slash == 0
    let l:dir = '/'
    let l:base = strpart(l:exp, 1)
    let l:keep = '/'
  else
    let l:dir = strpart(l:exp, 0, l:slash)
    let l:base = strpart(l:exp, l:slash + 1)
    let l:keep = strpart(l:exp, 0, l:slash + 1)
  endif
  " Keep the ~/ form the user typed.
  if a:frag !=# '' && a:frag[0] ==# '~' && strpart(l:keep, 0, len($HOME)) ==# $HOME
    let l:keep = '~' . strpart(l:keep, len($HOME))
  endif
  let l:realdir = l:dir[0] ==# '/' ? l:dir : getcwd() . '/' . l:dir
  if !isdirectory(l:realdir)
    return []
  endif
  let l:entries = []
  try
    let l:entries = readdir(l:realdir)
  catch
    return []
  endtry
  let l:out = []
  for l:f in l:entries
    if strpart(l:f, 0, len(l:base)) !=# l:base
      continue
    endif
    if l:f[0] ==# '.' && (l:base ==# '' || l:base[0] !=# '.')
      continue
    endif
    if isdirectory(l:realdir . '/' . l:f)
      call add(l:out, l:keep . l:f . '/')
    else
      call add(l:out, l:keep . l:f)
    endif
  endfor
  return l:out
endfunction

function! s:CommonPrefix(items) abort
  if empty(a:items)
    return ''
  endif
  let l:p = a:items[0]
  for l:s in a:items[1:]
    let l:max = min([strchars(l:p), strchars(l:s)])
    let l:i = 0
    while l:i < l:max && strcharpart(l:p, l:i, 1) ==# strcharpart(l:s, l:i, 1)
      let l:i += 1
    endwhile
    let l:p = strcharpart(l:p, 0, l:i)
    if l:p ==# ''
      break
    endif
  endfor
  return l:p
endfunction

" <Tab>: commands first, paths after, flags when the fragment starts
" with -. One candidate replaces; several extend or get listed.
function! vimshell#Complete() abort
  let l:lnum = s:PromptLine()
  if l:lnum == 0
    return ''
  endif
  let l:prompt = get(b:, 'vimshell_ps1', '')
  let l:input = strpart(getline(l:lnum), len(l:prompt))
  let l:cut = len(l:input)
  if line('.') == l:lnum
    let l:cut = max([0, min([col('.') - 1 - len(l:prompt), len(l:input)])])
  endif
  let l:ts = l:cut
  if !(l:cut < len(l:input) && strpart(l:input, l:cut, 1) =~# '\s')
    while l:ts > 0 && strpart(l:input, l:ts - 1, 1) !~# '\s'
      let l:ts -= 1
    endwhile
  endif
  let l:te = l:cut
  while l:te < len(l:input) && strpart(l:input, l:te, 1) !~# '\s'
    let l:te += 1
  endwhile
  let l:head = strpart(l:input, 0, l:ts)
  let l:frag = strpart(l:input, l:ts, l:te - l:ts)
  let l:after = strpart(l:input, l:te)
  if matchstr(l:head . l:frag, '^\s*\zs.*') !~# '\s'
    if l:frag ==# ''
      return ''
    endif
    let l:cands = filter(s:PathCommands() + s:builtins, 'strpart(v:val, 0, len(l:frag)) ==# l:frag')
    let l:space = 1
  else
    if l:frag =~# '^-'
      let l:cmd = matchstr(l:head . l:frag, '^\s*\zs\S\+')
      " copy(): filter() would mutate the cached list.
      let l:cands = filter(copy(s:CommandFlags(l:cmd)), 'strpart(v:val, 0, len(l:frag)) ==# l:frag')
      let l:space = 1
    else
      let l:cands = s:CompletePath(l:frag)
      let l:space = 0
    endif
  endif
  if empty(l:cands)
    return ''
  endif
  if len(l:cands) == 1
    let l:pick = l:cands[0] . (l:space ? ' ' : '')
  else
    let l:pick = s:CommonPrefix(l:cands)
    if l:pick ==# l:frag
      " List in the buffer below the prompt, keeping typed text; skip
      " repeats so double-Tab doesn't pile up.
      let l:key = l:frag . "\x01" . join(sort(copy(l:cands)), "\x02")
      if get(b:, 'vimshell_last_list', '') ==# l:key
        return ''
      endif
      let b:vimshell_last_list = l:key
      let l:show = sort(copy(l:cands))
      if len(l:show) > 40
        let l:show = l:show[:39] + ['... +' . (len(l:cands) - 40) . ' more']
      endif
      call s:AppendOutput(bufnr(''), l:show)
      return ''
    endif
  endif
  call s:Unlock()
  call setline(l:lnum, l:prompt . l:head . l:pick . l:after)
  call cursor(l:lnum, len(l:prompt . l:head . l:pick) + 1)
  call s:FixModifiable(bufnr(''))
  return ''
endfunction

" Line to complete/recall on: the cursor's own prompt line, else the
" last line if it is a prompt, else none (0).
function! s:PromptLine() abort
  let l:ps1 = get(b:, 'vimshell_ps1', '')
  if l:ps1 !=# ''
    let l:cur = getline('.')
    if strpart(l:cur, 0, len(l:ps1)) ==# l:ps1
      return line('.')
    endif
    if line('$') == 1 && getline(1) ==# ''
      return 1
    endif
    let l:last = getline('$')
    if strpart(l:last, 0, len(l:ps1)) ==# l:ps1
      return line('$')
    endif
  endif
  return 0
endfunction

" No pty means escapes are always garbage.
function! s:Sanitize(line) abort
  let l:line = substitute(a:line, "\<Esc>\\[[0-9; ?]*[a-zA-Z]", '', 'g')
  return substitute(l:line, '^.*\r', '', '')
endfunction

function! s:AppendOutput(buf, lines) abort
  if !bufexists(a:buf) || empty(a:lines)
    return
  endif
  call setbufvar(a:buf, '&modifiable', 1)
  call appendbufline(a:buf, len(getbufline(a:buf, 1, '$')), a:lines)
  call s:FixModifiable(a:buf)
endfunction

function! s:Note(msg) abort
  call s:AppendOutput(bufnr(''), [a:msg])
endfunction

" stderr mainly carries the shell's own noise; drop the known lines.
function! vimshell#OnErr(buf, channel, msg) abort
  if !bufexists(a:buf)
    return
  endif
  if a:msg =~# s:noise
    return
  endif
  call s:AppendOutput(a:buf, [s:Sanitize(a:msg)])
endfunction

function! vimshell#OnExit(buf, job, status) abort
  if !bufexists(a:buf)
    return
  endif
  call setbufvar(a:buf, 'vimshell_dead', 1)
  call s:AppendOutput(a:buf, ['[vimshell] process exited (code ' . a:status . ')'])
endfunction
