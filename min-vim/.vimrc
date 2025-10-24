set number
set relativenumber

set smartindent
set smarttab
set expandtab
set noswapfile
set autoindent
set tabstop=4
set softtabstop=4
set shiftwidth=4


set ignorecase
set smartcase
set nowrap
set incsearch
set hlsearch

set autocomplete
 
set clipboard^=unnamed,unnamedplus

syntax on

" DIFF colors
hi DiffAdd      ctermfg=NONE          ctermbg=DarkBlue
hi DiffChange   ctermfg=NONE          ctermbg=NONE
hi DiffDelete   ctermfg=LightBlue     ctermbg=Red
hi DiffText     ctermfg=Yellow        ctermbg=Red

colorscheme habamax

" Transparent
hi Normal  ctermbg=NONE guibg=NONE
hi NormalNC  ctermbg=NONE guibg=NONE

let mapleader = ' '

nmap <silent> <C-j> <C-w><C-j>
nmap <silent> <C-k> <C-w><C-k>
nmap <silent> <C-h> <C-w><C-h>
nmap <silent> <C-l> <C-w><C-l>
nmap <silent> <BS> :Explore<CR>
nmap <silent> sv :vsplit<CR><C-l>
nmap <silent> ss :split<CR><C-j>
nmap <silent> <leader><leader> :find<space>



