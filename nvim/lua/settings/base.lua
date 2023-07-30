-- opt.foldmethod=manual
-- opt.guioptions:append('a')
-- opt.listchars={ 'tab:> ', 'trail:_', 'eol:↲', 'extends:»', 'precedes:«', 'nbsp:%' }
-- opt.nobackup=true
-- opt.noerrorbells=true
-- opt.noswapfile=true
-- opt.novisualbell=true
-- opt.nowritebackup=true
-- opt.relativenumber=true
-- opt.termencoding = "utf-8"
-- opt.viminfo='100,/50,%,<1000,f50,s100,:100,c,h,!'
-- opt.whichwrap={ 'b', 's', 'h', 'l', '<', '>', '[', ']' }
local opt = vim.opt
opt.ambiwidth = "double"
opt.autoindent = true
opt.autoread = true
opt.autowrite = true
opt.background = "dark"
opt.backspace = { "start", "eol", "indent" }
opt.backup = true
opt.backupdir = os.getenv "HOME" .. "/.vim/backup"
opt.backupskip = { "/tmp/*", "/private/tmp/*" }
opt.clipboard:append "unnamedplus"
opt.cmdheight = 1
opt.cursorline = false
opt.display = lastline
opt.encoding = "utf-8"
opt.expandtab = true
opt.fileencoding = "utf-8"
opt.fileencodings = { "utf-8", "euc-jp", "iso-2022-jp", "cp932", "ucs-boms" }
opt.fileformat = unix
opt.fileformats = unix, dos, mac
opt.filetype = extension
opt.formatoptions:append "mM"
opt.formatoptions:append "r"
opt.formatoptions:remove "t"
opt.guifont = "HackGen35 Console"
opt.helplang = ja
opt.hidden = true
opt.history = 100
opt.hlsearch = true
opt.ignorecase = true
opt.inccommand = "split"
opt.incsearch = true
opt.infercase = true
opt.laststatus = 2
opt.lazyredraw = true
opt.matchpairs:append "<:>"
opt.matchtime = 2
opt.modifiable = true
opt.mouse = a
opt.nrformats = "bin,hex"
opt.number = true
opt.pumblend = 20
opt.redrawtime = 6000
opt.scrolloff = 5
opt.shell = zsh
opt.shiftround = true
opt.shiftwidth = 4
opt.shortmess:append "I"
opt.showbreak = "↪"
opt.showcmd = true
opt.showmatch = true
opt.smartcase = true
opt.smartindent = true
opt.smarttab = true
opt.softtabstop = 0
opt.splitbelow = true
opt.splitright = true
opt.swapfile = false
opt.switchbuf = useopen
opt.synmaxcol = 2000
opt.syntax = "enable"
opt.tabstop = 4
opt.termguicolors = true
opt.title = true
opt.ttyfast = true
opt.virtualedit = block
opt.visualbell = false
opt.whichwrap = "b,s,[,],<,>"
opt.wildignore = { "*.o", "*.a", "__pycache__" }
opt.wildmenu = true
opt.wildmode = { list = { longest, full } }
opt.wildoptions = "pum"
opt.winblend = 20
opt.wrap = true
opt.wrapscan = true
vim.b.nobackup = true
vim.b.noswapfile = true
vim.b.nowritebackup = true
vim.g.colorscheme = "aurora"
vim.g.mapleader = " "
vim.g.python3_host_prog = "/usr/bin/python3"
vim.g.shell = "/usr/bin/zsh"
vim.scriptencoding = "utf-8"
vim.wo.number = true
