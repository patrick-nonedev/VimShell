if exists('g:loaded_vimshell')
  finish
endif
let g:loaded_vimshell = 1

let s:save_cpo = &cpo
set cpo&vim

command! -nargs=0 VimShell       call vimshell#Open('curwin')
command! -nargs=0 VimShellOpen   call vimshell#Open('new')
command! -nargs=0 VimShellSplit  call vimshell#Open('split')
command! -nargs=0 VimShellVSplit call vimshell#Open('vsplit')
command! -nargs=1 VimShellShell   call vimshell#SetShell(<q-args>)


let &cpo = s:save_cpo
unlet s:save_cpo
