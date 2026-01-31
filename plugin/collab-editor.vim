" File: nvim/plugin/collab-editor.vim
" Auto-load plugin for collaborative editing

if exists('g:loaded_collab_editor')
  finish
endif
let g:loaded_collab_editor = 1

" Default configuration (can be overridden before loading)
if !exists('g:collab_editor_server_url')
  let g:collab_editor_server_url = ''
endif

if !exists('g:collab_editor_debug')
  let g:collab_editor_debug = 0
endif

" Setup will be called when user explicitly requires the module
" or calls one of the commands

" Highlight groups for remote cursors (can be overridden by colorscheme)
highlight default CollabCursor1 guibg=#FF6B6B guifg=#000000
highlight default CollabCursor2 guibg=#4ECDC4 guifg=#000000
highlight default CollabCursor3 guibg=#FFE66D guifg=#000000
highlight default CollabCursor4 guibg=#95E1D3 guifg=#000000

highlight default CollabCursorLabel1 guifg=#FF6B6B gui=bold
highlight default CollabCursorLabel2 guifg=#4ECDC4 gui=bold
highlight default CollabCursorLabel3 guifg=#FFE66D gui=bold
highlight default CollabCursorLabel4 guifg=#95E1D3 gui=bold
