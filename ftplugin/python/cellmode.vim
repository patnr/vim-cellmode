" Implementation of a MATLAB-like cellmode for python scripts.
" Cells are delimited by ##

execute 'source' expand('<sfile>:p:h') . '/aux/vars.vim'
call DefaultVars()
execute 'source' expand('<sfile>:p:h') . '/aux/movement.vim'
execute 'source' expand('<sfile>:p:h') . '/aux/folding.vim'
execute 'source' expand('<sfile>:p:h') . '/aux/tmux.vim'
execute 'source' expand('<sfile>:p:h') . '/aux/comms.vim'


function! RunCell(restore_cursor)
  if a:restore_cursor
    let l:winview = winsaveview()
  end

  call MoveCellWise(1, 0)
  let xx = b:cellmode_cell_delimiter

  call YankA(g:line1, g:line2)

  " Get header/footer lines, and check if they contain ##
  " (might not be the case at TOP/BOTTOM)
  let l:header = getline(g:line1)
  let l:header_exists = -1<match(l:header, "^\\s*".xx)
  let l:footer = getline(g:line2)
  let l:footer_exists = -1<match(l:footer, "^\\s*".xx)

  " Format header
  if l:header_exists
    " Rm delimiters (for prettiness)
    let l:header = substitute(l:header, xx, "", "g")
    " Rm # which bash command views as comments:
    let l:header = substitute(l:header, "#", "", "g")
    " Trim initial space
    let l:header = substitute(l:header, "^ \\+", "", "g")
    " Check if header not empty
    if l:header != ""
      let s:cellmode_header = l:header
    endif
  endif

  " Position cursor in next block for chaining execution
  call setpos('.', [0, g:line2, 0, 0])

  if l:footer_exists
    " Decrement line2 by 1 (for printing the linenumber, later)
    let g:line2 -= 1
  endif

  " The above will have the leading and trailing ## in the register,
  " but we have to remove them (especially leading one) to get
  " correct indentation estimate.
  " So just select the correct subrange of lines [iStart:iEnd]
  let l:iStart = l:header_exists ? 1 : 0
  let l:iEnd   = l:footer_exists ? -2 : -1
  let @a=join(split(@a, "\n")[l:iStart : l:iEnd], "\n")

  call RunRegister()

  if a:restore_cursor
    call winrestview(l:winview)
  end
endfunction


" Run entire current file
function! RunViaTmux(...)
  call DefaultVars()
  execute ":w"
  let interact = a:0 >= 1 ? a:1 : 0
  let fname = fnamemodify(bufname("%"), b:cellmode_abs_path ? ":p" : ":p:~:.")
  let fname = EscapeForTmuxKeys(fname)
  let l:msg = '%run Space '.(interact ? "-i Space " : "").'\"'.fname.'\" Enter'
  call ClearIPythonLine()
  silent call SendKeys(l:msg)
endfunction


function! RunVisual() range
  call DefaultVars()
  let g:line1=line("'<")
  let g:line2=line("'>")
  call YankA(g:line1, g:line2)
  " silent normal gv"ay
  let s:cellmode_header = "[visual]"
  call RunRegister()
endfunction


function! RunLine()
  call DefaultVars()
  silent normal "ayy
  call RunRegister()
endfunction


" Yank into register a
" Work around the fact that ranges does not work well with folds
function! YankA(from, to)
    let l:save_foldenable = &l:foldenable
    setlocal nofoldenable
    silent execute ":" . a:from . "," . a:to . "yank a"
    let &l:foldenable = l:save_foldenable
endfunction


function! IpdbRunCall(...)
  call DefaultVars()

  " Parse current line
  let ln = getline(".")
  " Remove up to "=" except if its inside parantheses
  let ln = substitute(ln, "^[^\(]*= *", "", "")
  " Replace first "(" by ", "
  let ln = substitute(ln, "(", ", ", "")

  let ln = EscapeForTmuxKeys(ln)
  let msg = 'import Space ipdb Space Enter'
  let msg .= ' ipdb.runcall\(' . ln
  call ClearIPythonLine()
  silent call SendKeys(msg)
endfunction


function! SetBreakPoint(...)
  call DefaultVars()
  let msg = 'b Space ' . line(".")
  call ClearIPythonLine()
  silent call SendKeys(msg)
endfunction


if g:cellmode_default_mappings
    vmap <buffer> <silent> <CR> :call RunVisual()<CR>
    noremap zf<CR> :call FoldCreate(1)<CR>

    noremap  <buffer> <F5>        :w<CR>:silent call RunViaTmux()<CR>
    inoremap <buffer> <F5>   <Esc>:w<CR>:silent call RunViaTmux()<CR>
    inoremap <buffer> <S-F5> <Esc>:w<CR>:silent call RunViaTmux(1)<CR>
    noremap  <buffer> <S-F5> <Esc>:w<CR>:silent call RunViaTmux(1)<CR>

    nnoremap <buffer> <silent> <S-U> :call MoveCellWise(0, 0)<CR>
    nnoremap <buffer> <silent> <S-D> :call MoveCellWise(1, 0)<CR>
    vnoremap <buffer> <silent> <S-U> :call MoveCellWise(0, 1)<CR>
    vnoremap <buffer> <silent> <S-D> :call MoveCellWise(1, 1)<CR>
endif
