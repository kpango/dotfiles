local status, comment = pcall(require, "nvim_comment")
if not status then
    error "nvim_comment is not installed"
    return
end

comment.setup {
    -- Linters prefer comment and line to have a space in between markers
    marker_padding = true,
    -- should comment out empty or whitespace only lines
    comment_empty = true,
    -- trim empty comment whitespace
    comment_empty_trim_whitespace = true,
    -- Should key mappings be created
    create_mappings = true,
    -- Normal mode mapping left hand side
    line_mapping = "gcc",
    -- Visual/Operator mapping left hand side
    operator_mapping = "gc",
    -- text object mapping, comment chunk,,
    comment_chunk_text_object = "ic",
    -- Hook function to call before commenting takes place
    hook = nil,
}

vim.api.nvim_set_keymap("n", "<C-C>", ":CommentToggle<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<C-C>", ":'<,'>CommentToggle<CR>", { noremap = true, silent = true })
