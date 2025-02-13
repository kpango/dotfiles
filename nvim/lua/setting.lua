function safe_require(module_name)
	local status, module = pcall(require, module_name)
	if not status then
		vim.api.nvim_err_writeln("Error loading module: " .. module_name)
		return nil
	end
	return module
end

safe_require("settings.skip_default")
safe_require("settings.autocmd")
safe_require("settings.base")
safe_require("settings.keymap")
safe_require("settings.env")
