" Implementation of a MATLAB-like cellmode for python scripts where cells
" are delimited by ##
"
" You can define the following globals or buffer config variables
"  let g:cellmode_tmux_sessionname='$ipython'
"  let g:cellmode_tmux_windowname='ipython'
"  let g:cellmode_tmux_panenumber='0'
"  let g:cellmode_screen_sessionname='ipython'
"  let g:cellmode_screen_window='0'
"  let g:cellmode_use_tmux=1

function! PythonUnindent(code)
  " The code is unindented so the first selected line has 0 indentation
  " So you can select a statement from inside a function and it will run
  " without python complaining about indentation.
  let l:lines = split(a:code, "\n")
  if len(l:lines) == 0 " Special case for empty string
    return a:code
  end
  let l:nindents = strlen(matchstr(l:lines[0], '^\s*'))
  " Remove nindents from each line
  let l:subcmd = 'substitute(v:val, "^\\s\\{' . l:nindents . '\\}", "", "")'
  call map(l:lines, l:subcmd)
  let l:ucode = join(l:lines, "\n")
  return l:ucode
endfunction

function! GetVar(name, default)
  " Return a value for the given variable, looking first into buffer, then
  " globals and defaulting to default
  if (exists ("b:" . a:name))
    return b:{a:name}
  elseif (exists ("g:" . a:name))
    return g:{a:name}
  else
    return a:default
  end
endfunction

function! CleanupTempFiles()
  " Called when leaving current buffer; Cleans up temporary files
  if (exists('b:cellmode_fnames'))
    for fname in b:cellmode_fnames
      call delete(fname)
    endfor
    unlet b:cellmode_fnames
  end
endfunction

function! GetNextTempFile()
  " Returns the next temporary filename to use
  "
  " We use temporary files to communicate with tmux. That is we :
  " - write the content of a register to a tmpfile
  " - have ipython running inside tmux load and run the tmpfile
  " If we use only one temporary file, quick execution of multiple cells will
  " result in the tmpfile being overrident. So we use multiple tmpfile that
  " act as a rolling buffer (the size of which is configured by
  " cellmode_n_files)
  if !exists("b:cellmode_fnames")
    au BufDelete <buffer> call CleanupTempFiles()
    let b:cellmode_fnames = []
    for i in range(1, b:cellmode_n_files)
      call add(b:cellmode_fnames, tempname())
    endfor
    let b:cellmode_fnames_index = 0
  end
  let l:cellmode_fname = b:cellmode_fnames[b:cellmode_fnames_index]
  " TODO: Would be better to use modulo, but vim doesn't seem to like % here...
  if (b:cellmode_fnames_index >= b:cellmode_n_files - 1)
    let b:cellmode_fnames_index = 0
  else
    let b:cellmode_fnames_index += 1
  endif

  "echo 'cellmode_fname : ' . l:cellmode_fname
  return l:cellmode_fname
endfunction

function! DefaultVars()
  " Load and set defaults config variables :
  " - b:cellmode_fname temporary filename
  " - g:cellmode_tmux_sessionname, g:cellmode_tmux_windowname,
  "   g:cellmode_tmux_panenumber : default tmux
  "   target
  " - b:cellmode_tmux_sessionname, b:cellmode_tmux_windowname,
  "   b:cellmode_tmux_panenumber :
  "   buffer-specific target (defaults to g:)
  let b:cellmode_n_files = GetVar('cellmode_n_files', 10)

  if !exists("b:cellmode_use_tmux")
    let b:cellmode_use_tmux = GetVar('cellmode_use_tmux', 1)
  end

  if !exists("b:cellmode_cell_delimiter")
    " By default, use ##, #%% or # %% (to be compatible with spyder)
    let b:cellmode_cell_delimiter = GetVar('cellmode_cell_delimiter',
                                         \ '\(##\|#%%\|#\s%%\)')
  end

  if !exists("b:cellmode_tmux_sessionname") ||
   \ !exists("b:cellmode_tmux_windowname") ||
   \ !exists("b:cellmode_tmux_panenumber")
    " Empty target session and window by default => try to automatically pick
    " tmux session
    let b:cellmode_tmux_sessionname = GetVar('cellmode_tmux_sessionname', '')
    let b:cellmode_tmux_windowname = GetVar('cellmode_tmux_windowname', '')
    let b:cellmode_tmux_panenumber = GetVar('cellmode_tmux_panenumber', '0')
  end

  if !exists("g:cellmode_screen_sessionname") ||
   \ !exists("b:cellmode_screen_window")
    let b:cellmode_screen_sessionname = GetVar('cellmode_screen_sessionname', 'ipython')
    let b:cellmode_screen_window = GetVar('cellmode_screen_window', '0')
  end
endfunction

function! CallSystem(cmd)
  " Execute the given system command, reporting errors if any
  let l:out = system(a:cmd)
  if v:shell_error != 0
    echom 'Vim-cellmode, error running ' . a:cmd . ' : ' . l:out
  end
endfunction

" Avoids pasting, and sharing the namespace.
function! RunViaTmux()
    call DefaultVars()
    "execute "normal :w\<CR>"
    execute ":w"

    let l:msg = 'run Space \"' . bufname("%") . '\" Enter'

    if b:cellmode_tmux_sessionname== ""
        execute "!tmux send-keys" l:msg
    else
        execute "!tmux send-keys -t" b:cellmode_tmux_sessionname l:msg
    endif
endfunction

function! CopyToTmux(code)
  " Copy the given code to tmux. We use a temp file for that
  let l:lines = split(a:code, "\n")
  let l:cellmode_fname = GetNextTempFile()
  call writefile(l:lines, l:cellmode_fname)

  " Set target tmux
  let target = b:cellmode_tmux_sessionname . ':'
             \ . b:cellmode_tmux_windowname . '.'
             \ . b:cellmode_tmux_panenumber

  " Use "run -i" rather than (the original implementation's) load-buffer.
  " Avoids cluttering terminal with input.
  let l:cellmode_fname = '\"' . l:cellmode_fname . '\"'
  let l:run_cmd = '"run -i "' . l:cellmode_fname
  " Append suffix to temp-file-name
  if exists("g:cellmode_run_comment")
      let l:run_cmd .= '" # "' . g:cellmode_run_comment
      unlet g:cellmode_run_comment
  endif

  call CallSystem("tmux send-keys -t " . target . " " . l:run_cmd . " Enter")
endfunction

function! CopyToScreen(code)
  let l:lines = split(a:code, "\n")
  " If the file is empty, it seems like tmux load-buffer keep the current
  " buffer and this cause the last command to be repeated. We do not want that
  " to happen, so add a dummy string
  if len(l:lines) == 0
    call add(l:lines, ' ')
  end
  let l:cellmode_fname = GetNextTempFile()
  call writefile(l:lines, l:cellmode_fname)

  if has('macunix')
    call system("pbcopy < " . l:cellmode_fname)
  else
    call system("xclip -i -selection c " . l:cellmode_fname)
  end
  call system("screen -S " . b:cellmode_screen_sessionname .
             \ " -p " . b:cellmode_screen_window
              \ . " -X stuff '%paste\n'")
endfunction

function! RunTmuxPythonReg()
  " Paste into tmux the content of the register @a
  let l:code = PythonUnindent(@a)
  if b:cellmode_use_tmux
    call CopyToTmux(l:code)
  else
    call CopyToScreen(l:code)
  end
endfunction

function! RunTmuxPythonCell(restore_cursor)
  " This is to emulate MATLAB's cell mode
  " Cells are delimited by ##. Note that there should be a ## at the end of the
  " file
  " The :?##?;/##/ part creates a range with the following
  " ?##? search backwards for ##

  " Then ';' starts the range from the result of the previous search (##)
  " /##/ End the range at the next ##
  " See the doce on 'ex ranges' here :
  " http://tnerual.eriogerg.free.fr/vimqrc.html
  "
  " Note that cell delimiters can be configured through
  " b:cellmode_cell_delimiter, but we keep ## in the comments for simplicity
  call DefaultVars()
  if a:restore_cursor
    let l:winview = winsaveview()
  end

  " Move one line down if we're currently on ##
  if getline(".") =~ b:cellmode_cell_delimiter
      execute "normal! j"
  end

  " Generates the cell delimiter search pattern
  let l:pat = ':?' . b:cellmode_cell_delimiter . '?;/' . b:cellmode_cell_delimiter . '/y a'

  " Execute it
  silent exe l:pat

  " Make suffix from filename and yank-range's linenumbers.
  let g:cellmode_run_comment = expand("%:t") . "@lines_"
  execute "normal! '["
  let g:cellmode_run_comment .= line(".")
  execute "normal! ']"
  let g:cellmode_run_comment .= ":" . line(".")

  " Append header
  execute "normal! '["
  let l:header = getline(".")
  let l:header = substitute(l:header, "#", "", "g")
  "let l:header = substitute(l:header, b:cellmode_cell_delimiter, "", "g")
  let g:cellmode_run_comment .= " Space " . l:header

  "silent :?\=b:cellmode_cell_delimiter?;/\=b:cellmode_cell_delimiter/y a

  " Now, we want to position ourselves inside the next block to allow block
  " execution chaining (of course if restore_cursor is true, this is a no-op
  " Move to the last character of the previously yanked text
  execute "normal! ']"
  " Move one line down
  execute "normal! j"

  " The above will have the leading and ending ## in the register, but we
  " have to remove them (especially leading one) to get a correct indentation
  " estimate. So just select the correct subrange of lines [1:-2]
  let @a=join(split(@a, "\n")[1:-2], "\n")
  call RunTmuxPythonReg()
  if a:restore_cursor
    call winrestview(l:winview)
  end

  " Unset
endfunction

function! RunTmuxPythonAllCellsAbove()
  " Executes all the cells above the current line. That is, everything from
  " the beginning of the file to the closest ## above the current line
  call DefaultVars()

  " Ask the user for confirmation, this could lead to huge execution
  if input("Execute all cells above ? [y]|n ", 'y') != "y"
    return
  endif

  let l:cursor_pos = getpos(".")

  " Creates a range from the first line to the closest ## above the current
  " line (?##? searches backward for ##)
  let l:pat = ':1,?' . b:cellmode_cell_delimiter . '?y a'
  silent exe l:pat

  let @a=join(split(@a, "\n")[:-2], "\n")
  call RunTmuxPythonReg()
  call setpos(".", l:cursor_pos)
endfunction

function! RunTmuxPythonChunk() range
  call DefaultVars()
  " Yank current selection to register a
  silent normal gv"ay
  "
  " Make suffix from filename and yank-range's linenumbers.
  let g:cellmode_run_comment = expand("%:t") . "@lines_"
  execute "normal! '["
  let g:cellmode_run_comment .= line(".")
  execute "normal! ']"
  let g:cellmode_run_comment .= ":" . line(".")

  call RunTmuxPythonReg()
endfunction

function! RunTmuxPythonLine()
  call DefaultVars()
  " Yank current selection to register a
  silent normal "ayy
  call RunTmuxPythonReg()
endfunction

" Returns:
"   1 if the var is set, 0 otherwise
function! InitVariable(var, value)
    if !exists(a:var)
        execute 'let ' . a:var . ' = ' . "'" . a:value . "'"
        return 1
    endif
    return 0
endfunction

call InitVariable("g:cellmode_default_mappings", 1)

if g:cellmode_default_mappings
    vmap <silent> <C-c> :call RunTmuxPythonChunk()<CR>
    noremap <silent> <C-b> :call RunTmuxPythonCell(0)<CR>
    noremap <silent> <C-g> :call RunTmuxPythonCell(1)<CR>
endif


command! -nargs=1 TpSession :let g:cellmode_tmux_sessionname="tp".<f-args> 
    \ | :bufdo :let b:cellmode_tmux_sessionname="tp".<f-args>
"command! -nargs=1 TpySess :let g:cellmode_tmux_sessionname=<f-args>
