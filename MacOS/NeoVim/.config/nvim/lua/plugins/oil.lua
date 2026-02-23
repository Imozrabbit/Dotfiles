return {
	{
		"stevearc/oil.nvim",
		---@module 'oil'
		---@type oil.SetupOpts
		opts = {},
		keys = {
			{ "-", "<CMD>Oil<CR>", desc = "Open parent directory in oil" },
		},
		-- Optional dependencies
		dependencies = { "nvim-tree/nvim-web-devicons" },
		-- Lazy loading is not recommended because it is very tricky to make it work correctly in all situations.
		lazy = false,
		config = function()
			require("oil").setup({
				keymaps = {
					["gd"] = {
						desc = "Toggle file detail view",
						callback = function()
							detail = not detail
							if detail then
								require("oil").set_columns({ "icon", "permissions", "size", "mtime" })
							else
								require("oil").set_columns({ "icon" })
							end
						end,
					},
				},
				default_file_explorer = true,
				delete_to_trash = true,
				view_options = {
					sort = {
						{ "type", "asc" },
					},
					show_hidden = true,
					is_always_hidden = function(name, _)
						return name == ".DS_Store"
					end,
				},
				win_options = {
					wrap = true,
				},
			})
		end,
	},
}
