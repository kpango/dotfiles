local status, onedark = pcall(require, "onedark.nvim")
if (not status) then
  error("onedark colorscheme is not installed")
  return
end

onedark.setup({
    style = 'darker'
})
onedark.load()
