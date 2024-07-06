function safe_require(module_name)
	local status, module = pcall(require, module_name)
	if not status then
		vim.api.nvim_err_writeln("Error loading module: " .. module_name)
		return nil
	end
	return module
end

require("settings.skip_default")
require("settings.autocmd")
require("settings.base")
require("settings.keymap")
