-- vim.opt.foldmethod=manual
-- vim.opt.guioptions:append('a')
-- vim.opt.listchars={ 'tab:> ', 'trail:_', 'eol:↲', 'extends:»', 'precedes:«', 'nbsp:%' }
-- vim.opt.nobackup=true
-- vim.opt.noerrorbells=true
-- vim.opt.noswapfile=true
-- vim.opt.novisualbell=true
-- vim.opt.nowritebackup=true
-- vim.opt.relativenumber=true
-- vim.opt.viminfo='100,/50,%,<1000,f50,s100,:100,c,h,!'
-- vim.opt.whichwrap={ 'b', 's', 'h', 'l', '<', '>', '[', ']' }
vim.g.colorscheme = "aurora"
vim.b.nobackup = true
vim.b.noswapfile = true
vim.b.nowritebackup = true
vim.g.mapleader = " "
vim.g.shell = "/usr/bin/zsh"
vim.opt.ambiwidth = double
vim.opt.autoindent = true
vim.opt.autoread = true
vim.opt.autowrite = true
vim.opt.background = "dark"
vim.opt.backspace = { "start", "eol", "indent" }
vim.opt.backup = true
vim.opt.backupdir = os.getenv "HOME" .. "/.vim/backup"
vim.opt.backupskip = { "/tmp/*", "/private/tmp/*" }
vim.opt.clipboard:append "unnamedplus"
vim.opt.cmdheight = 1
vim.opt.completeopt = menu, preview, noselect
vim.opt.cursorline = false
vim.opt.display = lastline
vim.opt.encoding = "utf-8"
vim.opt.expandtab = true
vim.opt.fileencoding = "utf-8"
vim.opt.fileencodings = { "utf-8", "euc-jp", "iso-2022-jp", "cp932", "ucs-boms" }
vim.opt.fileformat = unix
vim.opt.fileformats = unix, dos, mac
vim.opt.filetype = extension
vim.opt.formatoptions:append "mM"
vim.opt.formatoptions:append "r"
vim.opt.formatoptions:remove "t"
vim.opt.helplang = ja
vim.opt.hidden = true
vim.opt.history = 100
vim.opt.hlsearch = true
vim.opt.ignorecase = true
vim.opt.inccommand = "split"
vim.opt.incsearch = true
vim.opt.infercase = true
vim.opt.laststatus = 2
vim.opt.lazyredraw = true
vim.opt.redrawtime = 6000
vim.opt.matchpairs:append "<:>"
vim.opt.modifiable = true
vim.opt.mouse = a
vim.opt.nrformats = "bin,hex"
vim.opt.number = true
vim.opt.pumblend = 20
vim.opt.scrolloff = 5
vim.opt.shell = zsh
vim.opt.shiftround = true
vim.opt.shiftwidth = 4
vim.opt.shortmess:append "I"
vim.opt.showbreak = "↪"
vim.opt.showcmd = true
vim.opt.showmatch = true
vim.opt.matchtime = 2
vim.opt.smartcase = true
vim.opt.smartindent = true
vim.opt.smarttab = true
vim.opt.softtabstop = 0
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.swapfile = false
vim.opt.switchbuf = useopen
vim.opt.synmaxcol = 2000
vim.opt.syntax = "enable"
vim.opt.tabstop = 4
vim.opt.termencoding = "utf-8"
vim.opt.termguicolors = true
vim.opt.title = true
vim.opt.ttyfast = true
vim.opt.virtualedit = block
vim.opt.visualbell = false
vim.opt.whichwrap = "b,s,[,],<,>"
vim.opt.wildignore = { "*.o", "*.a", "__pycache__" }
vim.opt.wildmenu = true
vim.opt.wildmode = { list = { longest, full } }
vim.opt.wildoptions = "pum"
vim.opt.winblend = 20
vim.opt.wrap = true
vim.opt.wrapscan = true
vim.scriptencoding = "utf-8"
vim.wo.number = true
