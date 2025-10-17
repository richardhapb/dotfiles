set number
set relativenumber
set smartindent
set smarttab
set expandtab
set noswapfile

set ignorecase
set smartcase
set nowrap
set incsearch
set hlsearch

syntax on

" DIFF colors
hi DiffAdd      ctermfg=NONE          ctermbg=DarkBlue
hi DiffChange   ctermfg=NONE          ctermbg=NONE
hi DiffDelete   ctermfg=LightBlue     ctermbg=Red
hi DiffText     ctermfg=Yellow        ctermbg=Red


colorscheme habamax

function! IsRaspberryPi()
  if !filereadable('/proc/cpuinfo')
    return 0
  endif
  
  let l:cpuinfo = readfile('/proc/cpuinfo')
  
  for line in l:cpuinfo
    if line =~ 'Raspberry Pi'
      return 1
    endif
  endfor
  
  return 0
endfunction

function! IsSSH()
  return !empty($SSH_CLIENT) || !empty($SSH_TTY)
endfunction

if has('unix') || IsRaspberryPi() || IsSSH()

  let g:clipboard = {
        \ 'name': 'ssh-clipboard',
        \ 'copy': {
        \   '+': ['nc', '-q0', 'localhost', '2224'],
        \   '*': ['nc', '-q0', 'localhost', '2224'],
        \ },
        \ 'paste': {
        \   '+': ['nc', '-q0', 'localhost', '2225'],
        \   '*': ['nc', '-q0', 'localhost', '2225'],
        \ },
        \ 'cache_enabled': 1
        \ }

  set clipboard=unnamedplus

endif
