" File: plugin/viduct.vim
" Auto-load plugin for collaborative editing

if exists('g:loaded_viduct')
  finish
endif
let g:loaded_viduct = 1

" Default configuration (can be overridden before loading)
if !exists('g:viduct_server_url')
  let g:viduct_server_url = ''
endif

if !exists('g:viduct_debug')
  let g:viduct_debug = 0
endif

" Setup will be called when user explicitly requires the module
" or calls one of the commands

" Highlight groups for remote cursors (can be overridden by colorscheme)
highlight default ViductCursor1 guibg=#FF6B6B guifg=#000000
highlight default ViductCursor2 guibg=#4ECDC4 guifg=#000000
highlight default ViductCursor3 guibg=#FFE66D guifg=#000000
highlight default ViductCursor4 guibg=#95E1D3 guifg=#000000

highlight default ViductCursorLabel1 guifg=#FF6B6B gui=bold
highlight default ViductCursorLabel2 guifg=#4ECDC4 gui=bold
highlight default ViductCursorLabel3 guifg=#FFE66D gui=bold
highlight default ViductCursorLabel4 guifg=#95E1D3 gui=bold
