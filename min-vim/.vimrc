set number
set relativenumber
set nocompatible

set smarttab
set expandtab
set noswapfile
set tabstop=4
set softtabstop=4
set shiftwidth=4
set splitright

set cindent
set cinkeys-=0#
set autoindent


set ignorecase
set smartcase
set nowrap
set incsearch
set hlsearch
 
set clipboard^=unnamed,unnamedplus
set encoding=utf-8

" Enable folding
set foldmethod=indent
set foldlevel=99

set wildmenu
set wildoptions=pum

" Man files
runtime! ftplugin/man.vim
   

syntax on

" DIFF colors
hi DiffAdd      ctermfg=NONE          ctermbg=DarkBlue
hi DiffChange   ctermfg=NONE          ctermbg=NONE
hi DiffDelete   ctermfg=LightBlue     ctermbg=Red
hi DiffText     ctermfg=Yellow        ctermbg=Red

" Commments
hi Comment	term=bold ctermfg=Cyan guifg=#80a0ff gui=bold

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
nmap <silent> sa ggVG
nmap <silent> <leader><leader> :find<space>

" Python

if has('python3')
    py3 << EOF
import os
import sys
if 'VIRTUAL_ENV' in os.environ:
  project_base_dir = os.environ['VIRTUAL_ENV']
  activate_this = os.path.join(project_base_dir, 'bin/activate_this.py')
  exec(open(activate_this).read(), dict(__file__=activate_this))
EOF
endif

