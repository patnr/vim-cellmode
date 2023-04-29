command! -buffer -nargs=1 Tp let b:cellmode_sessionname="tp<args>"

" Split b:cellmode_sessionname
function! GetTmux()
    call AutoTmuxLazy()
    " Alias
    let tp = b:cellmode_sessionname
    " Rm (auto) tag (if it's there)
    let tp = substitute(tp, "(auto)", "", "")
    " Compose
    let socket = "tmux -L " . tp
    let target = "-t " . tp . ':' . b:cellmode_windowname . '.' . b:cellmode_panenumber
    return [socket, target]
endfunction


" If `b:cellmode_sessionname` is empty or contains "(auto)"
" then try picking out the last automatically.
" But only if enough time has elapsed since last time.
function! AutoTmuxLazy() abort
  if !exists("s:last_run_time")
      let s:last_run_time = [0, 0]
  endif
  if reltimefloat(reltime(s:last_run_time)) > 2
      let s:last_run_time = reltime()
      if b:cellmode_sessionname == "" || b:cellmode_sessionname =~ "(auto)"
          let b:cellmode_sessionname = LastTmuxSocket()
          let b:cellmode_sessionname = b:cellmode_sessionname . "(auto)" " tag
      endif
  endif
endfunction


function! LastTmuxSocket()
    " Find last (latest?) tmux socket.
    " Careful! this must work for both mac and linux versions!
    let cmd = ["lsof -U 2>/dev/null",
                \"grep 'tmp/tmux'",
                \"tail -n 1",
                \"tr -s ' ' '\n'",
                \"grep 'tmux-[0-9]*/tp'",
                \"grep -o 'tp[0-9]'"]
    let tp = trim(system(join(cmd, " \| ")))
    if tp == ""
        throw "Could not find tmux socket. Presumably there is no running tmux server."
    endif
    return tp
endfunction
