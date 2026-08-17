local M = {}
local homedir = vim.env.HOME

------------------------------------------------------------
------------------------- Commands -------------------------
------------------------------------------------------------
M.commands = {}
M.commands.EditBatConfig = {
	category = "CONFIG",
	action = function()
		vim.cmd("edit ~/.config/bat/config")
	end,
	description = "🦇 Edit bat config",
}

M.commands.EditGhosttyConfig = {
	category = "CONFIG",
	action = function()
		vim.cmd("edit ~/.config/ghostty/config")
	end,
	description = "👻 Edit Ghostty config",
}

M.commands.EditTmuxConfig = {
	category = "CONFIG",
	action = function()
		vim.cmd("edit ~/.config/tmux/tmux.conf")
	end,
	description = "🍱 Edit tmux config",
}

M.commands.EditLazygitConfig = {
	category = "CONFIG",
	action = function()
		vim.cmd("edit ~/.config/lazygit/config.yml")
	end,
	description = "🔱 Edit lazygit config",
}

M.commands.SourceNvimConfig = {
	category = "NVIM",
	action = function()
		vim.cmd("source $MYVIMRC")
	end,
	description = "🏄 Source Nvim config",
}

M.commands.EditLspLog = {
	category = "LSP",
	action = function()
		vim.cmd(":e " .. homedir .. "/.local/state/nvim/lsp.log")
	end,
	description = "🧰 Edit LSP Log",
}

M.commands.EmptyLspLog = {
	category = "LSP",
	action = function()
		vim.cmd("!echo > " .. homedir .. "/.local/state/nvim/lsp.log")
	end,
	description = "◻️ Empty LSP Log",
}

------------------------------------------------------------
---------------------------- Run ---------------------------
------------------------------------------------------------
M.run = function()
	local command_names = vim.tbl_keys(M.commands)

	table.sort(command_names, function(a, b)
		local category_a = M.commands[a].category or "OTHER"
		local category_b = M.commands[b].category or "OTHER"
		if category_a == category_b then
			return a < b
		end
		return category_a < category_b
	end)

	local menu_items = {}
	local previous_category
	for _, name in ipairs(command_names) do
		local category = M.commands[name].category or "OTHER"
		if previous_category and category ~= previous_category then
			table.insert(menu_items, "__separator__" .. category)
		end
		table.insert(menu_items, name)
		previous_category = category
	end

	vim.ui.select(menu_items, {
		prompt = "What you wanna do? ",
		kind = "command-menu",
		format_item = function(item)
			if vim.startswith(item, "__separator__") then
				return " "
			end
			local command = M.commands[item]
			return string.format("%-7s|  %s", command.category or "OTHER", command.description)
		end,
	}, function(choice)
		if choice == nil or vim.startswith(choice, "__separator__") then
			return
		end
		local chosen_command = M.commands[choice]
		chosen_command.action()
	end)
end

return M
