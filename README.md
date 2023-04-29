Vim-cellmode
============

Work with cells similar to Jupyter (or Matlab, or Spyder, etc.) in Vim!

Communicates with an IPython REPL running in tmux.

Forked from `julienr/vim-cellmode`.

Usage
-----

Blocks are delimited by `##`, `#%%` or `# %%`
(customizable through `cellmode_cell_delimiter`).
For example, say you have the following python script :

    ##
    import numpy as np
    print 'Hello'                  # (1)
    np.zeros(3)
    ##
    if True:
      print 'Yay !'                # (2)
      print 'Foo'                  # (3)
    ##

If you put your cursor on the line marked with (1) and hit `Ctrl-Enter`,
the 3 lines in the first cell will be run in IPython (in Tmux).
If you hit `Shift-Enter`, the same will happen,
but the cursor will move to the line after the `##` (facilitates chaining).

You can also select line(s) and hit `Enter` to send them to tmux.
The plugin automatically deindent selected lines so that the first line has no
indentation. So for example if you select the line marked (2) and (3), the
print statements will be de-indented and sent to tmux and ipython will
correctly run them.

Disable default mappings :

    let g:cellmode_default_mappings='0'
