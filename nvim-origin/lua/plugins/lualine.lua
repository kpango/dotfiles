local status, lualine = pcall(require, "lualine")
if not status then
    error "LuaLine is not installed"
    return
end

local status, navic = pcall(require, "nvim-navic")
if not status then
    error "navic is not installed"
    return
end

lualine.setup {
    options = {
        icons_enabled = true,
        theme = "ayu_dark",
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        disabled_filetypes = {
            statusline = {},
            winbar = {},
        },
        ignore_focus = {},
        always_divide_middle = true,
        colored = false,
        globalstatus = false,
        refresh = {
            statusline = 1000,
            tabline = 1000,
            winbar = 1000,
        },
    },
    sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = {
            {
                "filename",
                path = 2,
                file_status = true,
                shorting_target = 40,
                symbols = {
                    modified = " [+]",
                    readonly = " [RO]",
                    unnamed = "Untitled",
                },
            },
            {
                navic.get_location,
                cond = navic.is_available,
                color = { fg = "#f3ca28" },
            },
        },
        lualine_x = {
            {
                "diagnostics",
                sources = { "nvim_diagnostic" },
                symbols = {
                    error = " ",
                    warn = " ",
                    info = " ",
                    hint = " ",
                },
            },
            "encoding",
            "filetype",
        },
        lualine_y = { "progress" },
        lualine_z = { "location" },
    },
    inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = {
            {
                "filename",
                path = 2,
                file_status = true,
                shorting_target = 40,
                symbols = {
                    modified = " [+]",
                    readonly = " [RO]",
                    unnamed = "Untitled",
                },
            },
        },
        lualine_x = { "location" },
        lualine_y = {},
        lualine_z = {},
    },
    tabline = {},
    winbar = {},
    inactive_winbar = {},
    extensions = { "fugitive" },
}
