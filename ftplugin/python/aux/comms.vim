function! CallSystem(cmd)
  " Execute the given system command, reporting errors if any
  let l:out = system(a:cmd)
  if v:shell_error != 0
    echom 'Vim-cellmode, error running ' . a:cmd . ' : ' . l:out
  end
endfunction


function! SendKeys(keys)
    let [socket, target] = GetTmux()
    call CallSystem(socket . " send-keys " . target . " " . a:keys)
endfunction


function! SendText(text)
    let [socket, target] = GetTmux()
    call CallSystem(socket . " set-buffer " . target . " " . a:text)
    if v:shell_error != 0
        echom 'Aborting paste.'
        return 1
    end
    call CallSystem(socket . " paste-buffer " . target)
endfunction


function! ClearIPythonLine()
  " Leave tmux copy mode (silence error that arises if not)
  silent call SendKeys("-X cancel ")
  " Quit pager in case we're in ipython's help
  call SendKeys("q")
  " Enter ipython's readline-vim-insert-mode (or write i otherwise)
  call SendKeys("i")
  " Cancel whatever is currently written
  call SendKeys("C-c")
endfunction


function! RunRegister()
  " Paste into tmux the content of the register @a
  let l:code = PythonUnindent(@a)
  call RunInTmuxViaTmpFile(l:code)
endfunction


function! RunInTmuxViaTmpFile(code)
  let l:lines = split(a:code, "\n")

  " Strip >>>
  let l:lines = map(l:lines, 'substitute(v:val, "^ *>>> *", "", "")')

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

  call ClearIPythonLine()

  " Send lines
  " ---------
  " Use `%run -i` rather `%load` (like the original implementation).
  " Surround tmp path by quotation marks.
  let l:cellmode_fname = '\"' . l:cellmode_fname . '\"'
  " Use % in front of run to allow multiline (for comments).
  let l:cmd = '"%run -i "' . l:cellmode_fname

  " Get line numbers
  " ---------
  let l:winview = winsaveview()
  " Load saved cursor position
  call winrestview(l:winview)

  " Write line numbers
  " ---------
  if b:cellmode_verbose
    " Start a new line
    call SendText(l:cmd)
    call SendKeys("C-v C-j")
    " Insert actual file path and line numbers.
    let l:cmd = '"# "' . expand("%:p") . ":"
  else
    let l:cmd .= '" # "'
  end
  let l:cmd .= g:line1.'":"'.g:line2

  " Append headers
  " ---------
  if exists("s:cellmode_header")
    if b:cellmode_verbose
      call SendText(l:cmd)
      call SendKeys("C-v C-j")
      let l:cmd = '"# "'
    else
      let l:cmd .= '" :: "'
    end
    let l:cmd .= '"' . s:cellmode_header . '"'
    unlet s:cellmode_header
  endif

  " Execute
  " ---------
  call SendText(l:cmd)
  call SendKeys("Enter")
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

  return l:cellmode_fname
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


" Escape special characters for use with SendKeys
function! EscapeForTmuxKeys(str)
    let ln = a:str
    " Escape some special chars
    let ln = substitute(ln, '\(["()&]\)', '\\\1', "g")
    let ln = substitute(ln, "'", "\\\\'", "g")
    " Replace spaces
    let ln = substitute(ln, ' ', ' Space ', "g")
    return ln
endfunction


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
