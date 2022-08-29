vim.cmd([[
  command! PackerInstall packadd packer.nvim | lua require('packer').install()
  command! PackerUpdate packadd packer.nvim | lua require('packer').update()
  command! PackerSync packadd packer.nvim | lua require('packer').sync()
  command! PackerClean packadd packer.nvim | lua require('packer').clean()
  command! PackerCompile packadd packer.nvim | lua require('packer').compile()
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | lua require('packer').compile()
    autocmd BufWritePost init.lua source <afile> | lua require('packer').compile()
  augroup end
]])
