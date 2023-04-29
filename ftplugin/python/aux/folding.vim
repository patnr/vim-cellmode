command! FoldAll :call FoldAll()

function! FoldCreate(restore_cursor)
  call DefaultVars()
  let xx = b:cellmode_cell_delimiter
  let line0=line('.')

  " Find starting delim
  let has_delim=-1<match(getline(line0), "^\\s*".xx)
  if !has_delim | call MoveCellWise(0, 0) | endif
  let line1=line('.')

  " Find ending delim
  call MoveCellWise(1, 0)
  let has_delim=-1<match(getline(line(".")), "^\\s*".xx)
  if has_delim | execute 'norm! k' | endif
  let line2=line('.')

  " Fold
  execute ":" . line1 . "," . line2 . "fold"

  if a:restore_cursor
      call setpos('.', [0, line0, 0, 0])
  end
endfunction


function! FoldAll()
  call DefaultVars()
  let line0=line('.')
  norm gg

  let is_on_last_line = line(".") == line("$")
  while !is_on_last_line
      if !foldlevel(".")
          call FoldCreate(0)
          norm j
      else
          let line_tmp = getline(".")
          norm gj
          " Fix corner case (gj doesnt move to bottom when on last fold)
          if getline(".") == line_tmp
              silent $
          endif
      endif
      let is_on_last_line = line(".") == line("$")
  endwhile

  " Restore cursor pos
  call setpos('.', [0, line0, 0, 0])
endfunction
