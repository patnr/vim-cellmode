function! MoveCellWise(downwards, was_visual)
    " Find cell delimiters, moving via search (for delimiters).
    " If there are exceptions, move to TOP (0), or BOTTOM ($).

    call DefaultVars()
    let xx = b:cellmode_cell_delimiter
    " let so=&scrolloff | set so=10

    " Old method: Search and create range with :?##?;/##/. Works like so:
    " - ?##? search backwards for ##
    " - ';' start the range from the result of the previous search (##)
    " - /##/ End the range at the next ##
    " See the doce on 'ex ranges' here: http://tnerual.eriogerg.free.fr/vimqrc.html
    " let l:pat = ':?' . xx . '?;/' . xx . '/y a'
    " silent exe l:pat

    " Turn off wrapscan
    let l:wpscn=&wrapscan | set nowrapscan

    " Move INTO cell if currently on delim
    if getline(".") =~ xx && a:downwards
        " NB: we must move entire folds (whence gj, gk) because if we're inside a fold
        "     then vim search won't find the above delimiter.
        "     Of course, this still does not work when we're on the very last fold.
        normal gj
    end

    " Find match above
    try
        exec ':?'.xx
    catch
        silent 0
    endtry
    let g:line1=line('.')

    " Find match below
    try
        exec ':/'.xx
    catch
        silent $
    endtry
    let g:line2=line('.')

    " Re-select visual
    if a:was_visual
        normal gv
    endif

    " Goto match
    if a:downwards
        call setpos('.', [0, g:line2, 0, 0])
    else
        call setpos('.', [0, g:line1, 0, 0])
    endif

    " Manual scrolloff
    mark a
    normal 10j
    normal 'a
    normal 10k
    normal 'a

    " Always scroll: center, then down 25%
    " normal zz
    " exe "normal " . &lines/4. "\<C-e>"

    " Restore setting
    if l:wpscn | set wrapscan | endif
    " let &so=so
endfunction
