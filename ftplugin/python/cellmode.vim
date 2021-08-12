" Implementation of a MATLAB-like cellmode for python scripts where cells
" are delimited by ##
"
" You can define the following global/buffer config variables
"  let g:cellmode_tmux_sessionname='$ipython'
"  let g:cellmode_tmux_windowname='ipython'
"  let g:cellmode_tmux_panenumber='0'
"  let g:cellmode_screen_sessionname='ipython'
"  let g:cellmode_screen_window='0'
"  let g:cellmode_use_tmux=1
"  let g:cellmode_echo=0
"  let g:cellmode_echo_assigments_too=0
"  let g:cellmode_verbose=0


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


  let b:cellmode_verbose = GetVar('cellmode_verbose', 0)
  let b:cellmode_echo = GetVar('cellmode_echo', 0)
  let b:cellmode_echo_assigments_too = GetVar('cellmode_echo_assigments_too', 0)

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


function! TmuxSendText(text)
  " Set target tmux
  let target = b:cellmode_tmux_sessionname . ':'
             \ . b:cellmode_tmux_windowname . '.'
             \ . b:cellmode_tmux_panenumber

  call CallSystem("tmux set-buffer " . a:text)
  if v:shell_error != 0
    echom 'Aborting paste.'
    return 1
  end
  call CallSystem("tmux paste-buffer -t " . target)
endfunction


function! TmuxSendKeys(keys)
  " Set target tmux
  let target = b:cellmode_tmux_sessionname . ':'
             \ . b:cellmode_tmux_windowname . '.'
             \ . b:cellmode_tmux_panenumber

  call CallSystem("tmux send-keys -t " . target . " " . a:keys)
endfunction

" Avoids pasting, and sharing the namespace.
function! RunViaTmux(...)
  call DefaultVars()
  execute ":w"

  " Leave tmux copy mode (silence error that arises if not)
  silent call TmuxSendKeys("-X cancel ")
  " Enter ipython's readline-vim-insert-mode (or write i otherwise)
  call TmuxSendKeys("i")
  " Cancel whatever is currently written
  call TmuxSendKeys("C-c")

  " Run as interactive?
  let interactive = a:0 >= 1 ? a:1 : 0
  if interactive
      let l:msg = '-i Space '
  else
      let l:msg = ''
  endif
  let l:msg = '%run Space ' . l:msg
  # Run
  let l:msg = l:msg . '\"' . fnamemodify(bufname("%"),":p") . '\" Enter'
  silent call TmuxSendKeys(l:msg)
endfunction


function! CopyToTmux(code)
  let l:lines = split(a:code, "\n")

  " Tmp Filename
  " ---------
  if b:cellmode_verbose
    let l:cellmode_fname = GetNextTempFile()
  else
  " Shorter (only valid on *NIX):
    "let l:cellmode_fname = "/tmp/" . fnamemodify(bufname("%"),":t")
    let l:cellmode_fname = "/tmp/" . expand("%:t:r") . "_.py"
  end

  " Write code to tmpfile
  call writefile(l:lines, l:cellmode_fname)

  " MATLAB-like auto-printing of expressions
  " ---------
  " Inspired by: https://stackoverflow.com/a/44507944
  if b:cellmode_echo

    let l:apdx = ["","","","",
          \ "# AUTO-PRINTING",
          \ "",
          \ "def my_ast_printer(thing):",
          \ "    if hasattr(thing, 'id'):",
          \ "        # Avoid recursion for one particular var-name (___x___)",
          \ "        ___x___ = thing.id",
          \ "        if ___x___ != '___x___':",
          \ "            try: eval(___x___)",
          \ "            except NameError: return",
          \ "            print(___x___, ':', sep='')",
          \ "            ___x___ = str(eval(___x___))",
          \ "            ___x___ = '    ' + '    \\n'.join(___x___.split('\\n'))",
          \ "            print(___x___)",
          \ "",
          \ "import ast as ___ast",
          \ "class ___Visitor(___ast.NodeVisitor):",
          \ "    def visit_Expr(self, node):",
          \ "        my_ast_printer(node.value)",
          \ "        self.generic_visit(node)",
          \]
    call writefile(l:apdx, l:cellmode_fname, "a")

    if b:cellmode_echo_assigments_too
      let l:apdx = ["","",
          \ "    def visit_Assign(self, node):",
          \ "        for target in node.targets:",
          \ "            my_ast_printer(target)",
          \ "        self.generic_visit(node)",
          \]
      call writefile(l:apdx, l:cellmode_fname, "a")
    end

    let l:apdx = ["",
          \ "___Visitor().visit(___ast.parse(open(__file__).read()))",
          \ "del my_ast_printer, ___Visitor",
          \]
    call writefile(l:apdx, l:cellmode_fname, "a")
  end

  " Send lines
  " ---------
  " Use `%run -i` rather `%load` (like the original implementation).
  " Leave tmux copy mode (silence error that arises if not)
  silent call TmuxSendKeys("-X cancel ")
  " Surround tmp path by quotation marks.
  let l:cellmode_fname = '\"' . l:cellmode_fname . '\"'
  " Use % in front of run to allow multiline (for comments).
  let l:cmd = '"%run -i "' . l:cellmode_fname

  " Get line numbers
  " ---------
  let l:winview = winsaveview()
  " Find starting, ending, lineno
  execute "normal! '[" | let l:line1 = line(".")
  execute "normal! ']" | let l:line2 = line(".")
  " Load saved cursor position
  call winrestview(l:winview)

  " Write line numbers
  " ---------
  if b:cellmode_verbose
    " Start a new line
    call TmuxSendText(l:cmd)
    call TmuxSendKeys("C-v C-j")
    " Insert actual file path and line numbers.
    let l:cmd = '"# "' . expand("%:p") . ":"
  else
    let l:cmd .= '" # "'
  end
  let l:cmd .= l:line1.'":"'.l:line2

  " Append headers
  " ---------
  if exists("s:cellmode_header")
    if b:cellmode_verbose
      call TmuxSendText(l:cmd)
      call TmuxSendKeys("C-v C-j")
      let l:cmd = '"# "'
    else
      let l:cmd .= '" :: "'
    end
    let l:cmd .= '"' . s:cellmode_header . '"'
    unlet s:cellmode_header
  endif

  " Execute
  " ---------
  call TmuxSendText(l:cmd)
  call TmuxSendKeys("Enter")

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
  "let l:pat = ':?' . b:cellmode_cell_delimiter . '?;/' . b:cellmode_cell_delimiter . '/y a'
  " Execute it
  "silent exe l:pat
  
  " Search for delimiters, allowing for TOP and BOTTOM
  let l:wpscn=&wrapscan
  set nowrapscan
  let l:pat = ':?' . b:cellmode_cell_delimiter
  try | exec pat | catch /search hit TOP/ | silent 0 | finally | mark [ | endtry
  let l:pat = ':/' . b:cellmode_cell_delimiter
  try | exec pat | catch /search hit BOTTOM/ | silent $ | finally | mark ] | endtry
  if l:wpscn | set wrapscan | endif
  " Yank (includes delimiter lines, if they exist)
  silent normal '["ay']


  " Get header/footer lines, and check if
  " they contain delmiters (might not be the case at TOP/BOTTOM)
  execute "normal! '["
  let l:header = getline(".")
  let l:header_delim_exists = -1<match(l:header, "^\\s*".b:cellmode_cell_delimiter)
  execute "normal! ']"
  let l:footer = getline(".")
  let l:footer_delim_exists = -1<match(l:footer, "^\\s*".b:cellmode_cell_delimiter)

  " Format header
  if l:header_delim_exists
    " Rm delimiters (for prettiness) 
    let l:header = substitute(l:header, b:cellmode_cell_delimiter, "", "g")
    " Rm # which bash command views as comments:
    let l:header = substitute(l:header, "#", "", "g")
    " Trim initial space
    let l:header = substitute(l:header, "^ \\+", "", "g")
    " Check if header not empty
    if l:header != ""
      let s:cellmode_header = l:header
    endif
  endif

  "silent :?\=b:cellmode_cell_delimiter?;/\=b:cellmode_cell_delimiter/y a

  " Now, we want to position ourselves inside the next block to allow block
  " execution chaining (of course if restore_cursor is true, this is a no-op
  " Move to the last character of the previously yanked text
  execute "normal! ']"

  if l:footer_delim_exists
    " Set the ] mark 1 line upward
    " (for printing the linenumber, later)
    normal k
    mark ]
    normal j
  endif

  " The above will have the leading and ending ## in the register, but we
  " have to remove them (especially leading one) to get a correct indentation
  " estimate. So just select the correct subrange of lines [iStart:iEnd]
  let l:iStart = 0
  let l:iEnd = -1
  if l:header_delim_exists | let l:iStart += 1 | endif
  if l:footer_delim_exists | let l:iEnd   -= 1 | endif
  let @a=join(split(@a, "\n")[l:iStart : l:iEnd], "\n")

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

  " Creates a range from the first line to the closest ## above.
  " See RunTmuxPythonCell for explanations
  silent exe ':1,?' . b:cellmode_cell_delimiter . '?y a'

  let @a=join(split(@a, "\n")[:-2], "\n")
  call RunTmuxPythonReg()
  call setpos(".", l:cursor_pos)
endfunction


function! RunTmuxPythonChunk() range
  call DefaultVars()
  " Yank current selection to register a
  silent normal gv"ay
  let s:cellmode_header = "[visual]"

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
