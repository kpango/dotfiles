local status, onedark = pcall(require, "onedark")
if not status then
    error "onedark colorscheme is not installed"
    return
end

onedark.setup {
    style = "darker",
}
onedark.load()
