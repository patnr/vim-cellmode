" Put this in after/syntax to avoid it being overruled.
" Otherwise, this is the output of :scriptnames :
" 133: ~/.vim/plugged/vim-cellmode/syntax/python.vim
" 134: ~/.vim/plugged/vim-polyglot/syntax/python.vim
" 135: /usr/share/vim/vim82/syntax/python.vim

if exists("b:cellmode_syntax")
  finish
endif

" Highlight cell delimiters
syntax match cellDelim '\v^\s*#(#+|\s+(##+|\%\%+)).*'
highlight default link cellDelim TabLine

let b:cellmode_syntax = "done"
