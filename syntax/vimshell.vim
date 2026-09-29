if exists('b:current_syntax')
  finish
endif

" Prompt prefix is set by the plugin; generic shell patterns below.
syntax match vimshellNote /^\[vimshell\].*$/

syntax match vimshellString /"[^"]*"/
syntax match vimshellString /'[^']*'/

syntax match vimshellVariable /\$\w\+/
syntax match vimshellVariable /\${\w\+}/

syntax match vimshellNumber /\<\d\+\>/

syntax match vimshellComment /#.*/

syntax match vimshellOperator /&&\|||\|[|&;<>]/

syntax match vimshellFlag /\s\zs--\=[a-zA-Z][a-zA-Z0-9-]*/

syntax match vimshellError /\<[Ee]rror\>\|\<[Ff]ailed\>\|\<[Ff]ailure\>\|No such file\|command not found\|Permission denied/

highlight default link vimshellPrompt Identifier
highlight default link vimshellNote Comment
highlight default link vimshellString String
highlight default link vimshellVariable PreProc
highlight default link vimshellNumber Number
highlight default link vimshellComment Comment
highlight default link vimshellOperator Operator
highlight default link vimshellFlag Special
highlight default link vimshellError Error

let b:current_syntax = 'vimshell'
