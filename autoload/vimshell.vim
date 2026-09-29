" vimshell: Emacs shell-mode in Vim.
" Editable buffer over one persistent shell job (pipes, no pty).

let s:prompt_default = 'vimsh$ '
let s:history_max = 1000

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
  call s:StartJob()
  if !get(b:, 'vimshell_dead', 0)
    call vimshell#PrintPrompt()
  endif
endfunction

function! s:SetupBuffer() abort
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
  setlocal filetype=vimshell
  setlocal nowrap nonumber norelativenumber nocursorline nolist
  let b:vimshell_history = []
  let b:vimshell_history_idx = 0
  let b:vimshell_partial = ''
  let b:vimshell_dead = 0
  let b:vimshell_prompt_lnum = 0
  let b:vimshell_prompt = ''
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
endfunction

function! s:Prompt() abort
  return get(g:, 'vimshell_prompt', s:prompt_default)
endfunction

" Expand $PWD, $HOME, $USER, $SHELL, $HOSTNAME and ${...}; $$ is literal.
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
  return substitute(l:p, "\x01", '$', 'g')
endfunction

" Highlight the prompt prefix of the current line (matched by line
" number and expanded text, which may change).
function! s:HighlightPrompt(lnum) abort
  silent! syntax clear vimshellPrompt
  execute 'syntax match vimshellPrompt /\%' . a:lnum . 'l^\V' . escape(get(b:, 'vimshell_prompt', ''), '/\') . '/'
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
    " fish only reads piped stdin at EOF, so it can't work here.
    call s:Note('[vimshell] fish needs a tty, falling back to sh (set g:vimshell_shell to override)')
    let l:argv = ['sh']
  endif
  " -i loads the rc file. bash needs --noediting: it uses readline even
  " on pipes. Matched on the resolved binary (sh is often a symlink).
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
  let b:vimshell_job = job_start(l:argv, {
        \ 'in_io': 'pipe', 'out_io': 'pipe', 'err_io': 'pipe',
        \ 'out_mode': 'raw', 'err_mode': 'raw',
        \ 'out_cb': function('vimshell#OnOutput', [bufnr('')]),
        \ 'err_cb': function('vimshell#OnOutput', [bufnr('')]),
        \ 'exit_cb': function('vimshell#OnExit', [bufnr('')]),
        \ 'env': {'TERM': 'dumb', 'PAGER': 'cat', 'MANPAGER': 'cat',
        \         'PS1': '', 'PS2': ''}})
  if job_status(b:vimshell_job) !=# 'run'
    call s:Note('[vimshell] could not start: ' . join(l:argv))
    let b:vimshell_dead = 1
  else
    let b:vimshell_dead = 0
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

function! vimshell#PrintPrompt() abort
  let b:vimshell_prompt = s:ExpandPrompt()
  let b:vimshell_last_list = ''
  if line('$') == 1 && getline(1) ==# ''
    call setline(1, b:vimshell_prompt)
  else
    call append(line('$'), b:vimshell_prompt)
  endif
  let b:vimshell_prompt_lnum = line('$')
  call s:HighlightPrompt(b:vimshell_prompt_lnum)
  call cursor(line('$'), col('$'))
  silent! startinsert!
endfunction

function! vimshell#ExecuteLine() abort
  if get(b:, 'vimshell_dead', 0)
    call s:StartJob()
    if get(b:, 'vimshell_dead', 0)
      return
    endif
    call vimshell#PrintPrompt()
    return
  endif
  if get(b:, 'vimshell_prompt_lnum', 0) < 1 || b:vimshell_prompt_lnum > line('$')
    call vimshell#PrintPrompt()
    return
  endif
  " RET on an old line copies it to the prompt without executing.
  if line('.') != b:vimshell_prompt_lnum
    let l:old = getline('.')
    let l:prompt = get(b:, 'vimshell_prompt', '')
    if l:prompt !=# '' && strpart(l:old, 0, len(l:prompt)) ==# l:prompt
      let l:old = strpart(l:old, len(l:prompt))
    endif
    call setline(b:vimshell_prompt_lnum, l:prompt . l:old)
    call cursor(b:vimshell_prompt_lnum, col('$'))
    silent! startinsert!
    return
  endif
  let l:cmd = strpart(getline('.'), len(get(b:, 'vimshell_prompt', '')))
  if l:cmd ==# ''
    return
  endif
  " clear is buffer business (TERM=dumb has no escapes to interpret).
  if l:cmd =~# '^\s*clear\s*$'
    call vimshell#ClearScreen()
    return
  endif
  " Plain `cd <dir>` also :cds so $PWD stays truthful. Anything
  " fancier (vars, globs, quotes) moves only the shell.
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
  call add(b:vimshell_history, l:cmd)
  if len(b:vimshell_history) > s:history_max
    call remove(b:vimshell_history, 0)
  endif
  let b:vimshell_history_idx = len(b:vimshell_history)
  if !exists('b:vimshell_job') || job_status(b:vimshell_job) !=# 'run'
    let b:vimshell_dead = 1
    call s:Note('[vimshell] process is not running')
    return
  endif
  try
    call ch_sendraw(b:vimshell_job, l:cmd . "\n")
  catch
    let b:vimshell_dead = 1
    call s:Note('[vimshell] process is not running')
    return
  endtry
  call vimshell#PrintPrompt()
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
  if get(b:, 'vimshell_prompt_lnum', 0) < 1 || b:vimshell_prompt_lnum > line('$')
    call vimshell#PrintPrompt()
    return
  endif
  let b:vimshell_history_idx += a:dir
  let b:vimshell_history_idx = max([0, min([b:vimshell_history_idx, len(b:vimshell_history)])])
  let l:cmd = b:vimshell_history_idx < len(b:vimshell_history)
        \ ? b:vimshell_history[b:vimshell_history_idx] : ''
  call setline(b:vimshell_prompt_lnum, get(b:, 'vimshell_prompt', '') . l:cmd)
  call s:HighlightPrompt(b:vimshell_prompt_lnum)
  call cursor(b:vimshell_prompt_lnum, col('$'))
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
  if s:CurrentInput() ==# '' && exists('b:vimshell_job')
    silent! call ch_close_in(b:vimshell_job)
  endif
endfunction

function! s:CurrentInput() abort
  if get(b:, 'vimshell_prompt_lnum', 0) < 1 || b:vimshell_prompt_lnum > line('$')
    return ''
  endif
  return strpart(getline(b:vimshell_prompt_lnum), len(get(b:, 'vimshell_prompt', '')))
endfunction

function! vimshell#ClearScreen() abort
  silent! %delete _
  call vimshell#PrintPrompt()
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

" Flags from --help, cached per command. Long flags always; short ones
" only when it really looks like help (else -h may have listed a dir).
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
  if get(b:, 'vimshell_prompt_lnum', 0) < 1 || b:vimshell_prompt_lnum > line('$')
    return ''
  endif
  let l:lnum = b:vimshell_prompt_lnum
  let l:prompt = get(b:, 'vimshell_prompt', '')
  let l:input = strpart(getline(l:lnum), len(l:prompt))
  " Complete the whole token under the cursor; splitting at the cursor
  " used to duplicate text ('dir/' + 'r' -> 'dir/r').
  let l:cut = max([0, min([col('.') - 1 - len(l:prompt), len(l:input)])])
  if line('.') != l:lnum
    let l:cut = len(l:input)
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
      " List in the buffer above the prompt, keeping typed text; skip
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
  call setline(l:lnum, l:prompt . l:head . l:pick . l:after)
  call cursor(l:lnum, len(l:prompt . l:head . l:pick) + 1)
  return ''
endfunction

function! vimshell#OnOutput(buf, channel, msg) abort
  if !bufexists(a:buf)
    return
  endif
  let l:text = getbufvar(a:buf, 'vimshell_partial', '') . a:msg
  let l:lines = split(l:text, "\n", 1)
  call setbufvar(a:buf, 'vimshell_partial', remove(l:lines, -1))
  let l:out = []
  for l:line in l:lines
    let l:line = s:Sanitize(l:line)
    " Drop bash's job-control startup warnings (EN/ES). They only say
    " there is no tty, which we already know.
    if l:line =~# 'terminal process group\|grupo de proceso de terminal\|no job control in this shell\|no hay control de trabajos en este shell'
      continue
    endif
    call add(l:out, l:line)
  endfor
  if !empty(l:out)
    call s:AppendOutput(a:buf, l:out)
  endif
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
  let l:n = len(getbufline(a:buf, 1, '$'))
  let l:at = l:n
  let l:prompt = getbufvar(a:buf, 'vimshell_prompt', '')
  if l:prompt !=# '' && l:n > 0 && strpart(getbufline(a:buf, l:n)[0], 0, len(l:prompt)) ==# l:prompt
    let l:at = l:n - 1
  endif
  call appendbufline(a:buf, l:at, a:lines)
  " Track the prompt mark (and its highlight when current) as output
  " pushes it down.
  if l:at == l:n - 1
    call setbufvar(a:buf, 'vimshell_prompt_lnum', l:n + len(a:lines))
    if bufnr('') == a:buf
      call s:HighlightPrompt(l:n + len(a:lines))
      if line('.') == l:n
        call cursor(l:n + len(a:lines), col('.'))
      endif
    endif
  endif
endfunction

function! s:Note(msg) abort
  call s:AppendOutput(bufnr(''), [a:msg])
endfunction

function! vimshell#OnExit(buf, job, status) abort
  if !bufexists(a:buf)
    return
  endif
  call setbufvar(a:buf, 'vimshell_dead', 1)
  let l:part = s:Sanitize(getbufvar(a:buf, 'vimshell_partial', ''))
  call setbufvar(a:buf, 'vimshell_partial', '')
  let l:lines = l:part ==# '' ? [] : [l:part]
  call add(l:lines, '[vimshell] process exited (code ' . a:status . ')')
  call s:AppendOutput(a:buf, l:lines)
endfunction
