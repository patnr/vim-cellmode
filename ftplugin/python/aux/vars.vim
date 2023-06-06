function! GetVar(name, default)
  " Get `b:name`, `g:name`, or `default` (by order of preference)
  if (exists ("b:" . a:name))
    return b:{a:name}
  elseif (exists ("g:" . a:name))
    return g:{a:name}
  else
    return a:default
  end
endfunction


" Set config vars.
" User config files must use `g:` prefixed variables,
" while live configuration must use `b:` prefixed variables.
function! DefaultVars()
    " Only use abs path when file not under pwd.
    " If 1: always use abs path.
    let b:cellmode_abs_path = GetVar('cellmode_abs_path', 0)

    " Verbosity control
    let b:cellmode_verbose = GetVar('cellmode_verbose', 0)
    let b:cellmode_echo = GetVar('cellmode_echo', 0)
    let b:cellmode_echo_assigments_too = GetVar('cellmode_echo_assigments_too', 0)

    let b:cellmode_run_args = GetVar('cellmode_run_args', [])
    let b:cellmode_bufname = GetVar('cellmode_bufname', "")

    " Num. of temp files to rotate between
    let b:cellmode_n_files = GetVar('cellmode_n_files', 10)

    " Empty target session & window (default) => tmux auto-picks
    " Doesn't work since now using separate tmux servers.
    let b:cellmode_sessionname = GetVar('cellmode_sessionname', "")
    let b:cellmode_windowname = GetVar('cellmode_windowname', '')
    let b:cellmode_panenumber = GetVar('cellmode_panenumber', '0')

    " default: ##, #%% or # %% (for spyder)
    let b:cellmode_cell_delimiter = GetVar('cellmode_cell_delimiter',
                \ '\v^\s*#(#+|\s+(##+|\%\%+)).*')

    " Set default maps?
    let g:cellmode_default_mappings = GetVar('g:cellmode_default_mappings', 1)
endfunction
