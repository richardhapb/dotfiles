set number
set relativenumber
set nocompatible

set smartindent
set smarttab
set expandtab
set noswapfile
set autoindent
set tabstop=4
set softtabstop=4
set shiftwidth=4
set splitright


set ignorecase
set smartcase
set nowrap
set incsearch
set hlsearch

set autocomplete
 
set clipboard^=unnamed,unnamedplus
set encoding=utf-8

" Enable folding
set foldmethod=indent
set foldlevel=99

" Man files
runtime! ftplugin/man.vim
   

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
nmap <silent> sa ggVG
nmap <silent> <leader><leader> :find<space>

" Python

au BufNewFile,BufRead *.py {
    set tabstop=4
    set softtabstop=4
    set shiftwidth=4
    set expandtab
    set autoindent
    set fileformat=unix
}

py3 << EOF
import os
import sys
if 'VIRTUAL_ENV' in os.environ:
  project_base_dir = os.environ['VIRTUAL_ENV']
  activate_this = os.path.join(project_base_dir, 'bin/activate_this.py')
  exec(open(activate_this).read(), dict(__file__=activate_this))
EOF

set wildmenu
set wildmode=noselect:longest:lastused,full
if executable('fd') && executable('fzf')
    set findfunc=FuzzyFindFunc
endif

packadd cfilter

set wildmenu
set wildmode=noselect:longest:lastused,full
set grepprg=rg\ --vimgrep\ --hidden\ -g\ '!.git/*'
if executable('fd') && executable('fzf')
    set findfunc=FuzzyFindFunc
endif

nnoremap <leader>f :find<space>
nnoremap <leader>F :vert sf<space>
nnoremap <leader>b :b<space>
nnoremap <leader>d :Findqf<space>
nnoremap <leader>g :grep ''<left>
nnoremap <leader>G :grep <C-R><C-W><cr>
nnoremap <leader>z :Zgrep<space>
nnoremap <leader>Z :Fzfgrep<space>
nnoremap <leader>cf :Cfilter<space> 
nnoremap <leader>cz :Cfuzzy<space> 
nnoremap <leader>co :colder<space> 
nnoremap <leader>cn :cnewer<space> 
cnoremap <C-space> .*
"nvim only
cnoremap <A-9> \(
cnoremap <A-0> \)
cnoremap <A-space> \<space>

command! -nargs=+ -complete=file_in_path Findqf call FdSetQuickfix(<f-args>)
command! -nargs=1 Cfuzzy call FuzzyFilterQf(<f-args>)
command! -nargs=+ -complete=file_in_path Zgrep call FuzzyFilterGrep(<f-args>)
command! -nargs=+ -complete=file_in_path Fzfgrep call FzfGrep(<f-args>)

function! FuzzyFilterGrep(query, path=".") abort
    exe "grep! '" .. a:query .. "' " .. a:path
    let sort_query = substitute(a:query, '\.\*', '', 'g')
    let sort_query = substitute(sort_query, '\\\(.\)', '\1', 'g')
    call FuzzyFilterQf(sort_query)
    cfirst
    copen
endfunction

function! FuzzyFilterQf(...) abort
    call setqflist(matchfuzzy(getqflist(), join(a:000, " "), {'key': 'text'}))
endfunction

function! FzfGrep(query, path=".")
    let oldgrepprg = &grepprg
    let &grepprg = "rg --column --hidden -g '!.git/*' . " 
        \.. a:path .. " \\| fzf --filter='$*' --delimiter : --nth 4.."
    exe "grep " .. a:query
    let &grepprg = oldgrepprg
endfunction

function! FuzzyFindFunc(cmdarg, cmdcomplete)
    return systemlist("fd --hidden . \| fzf --filter='" 
        \.. a:cmdarg .. "'")
endfunction

function! FdSetQuickfix(...) abort
    let fdresults = systemlist("fd -t f --hidden " .. join(a:000, " "))
    if v:shell_error
        echoerr "Fd error: " .. fdresults[0]
        return
    endif
    call setqflist(map(fdresults, {_, val -> 
        \{'filename': val, 'lnum': 1, 'text': val}}))
    copen
endfunction
