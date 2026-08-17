local detail = false
return {
	{
		"stevearc/oil.nvim",
		---@module 'oil'
		---@type oil.SetupOpts
		keys = {
			{
				"-",
				function()
					require("oil").toggle_float(nil, {
						preview = {},
					}, require("scripts.oil_float").setup)
				end,
				mode = "n",
				desc = "Toggle oil file explorer",
			},
		},
		dependencies = { "nvim-tree/nvim-web-devicons" },
		-- Lazy loading is not recommended because it is very tricky to make it work correctly in all situations.
		lazy = false,
		opts = {
			default_file_explorer = true,
			delete_to_trash = true,
			view_options = {
				sort = {
					{ "type", "asc" },
					{ "name", "asc" },
				},
				show_hidden = true,
				is_always_hidden = function(name, _)
					return name == ".DS_Store" or name == ".windows-serial"
				end,
			},

			keymaps = {
				["-"] = false,
				["gd"] = {
					mode = "n",
					desc = "Toggle file detail view",
					callback = function()
						detail = not detail
						if detail then
							require("oil").set_columns({
								"icon",
								"permissions",
								"size",
								"mtime",
							})
						else
							require("oil").set_columns({
								"icon",
							})
						end
					end,
				},
				["<BS>"] = { "actions.parent", mode = "n" },
			},

			win_options = {
				wrap = true,
				signcolumn = "auto",
			},

			float = {
				padding = 2,
				max_width = 0.9,
				max_height = 0.4,
				border = nil,
				win_options = {
					number = false,
					relativenumber = false,
					winblend = 0,
				},
				get_win_title = require("scripts.oil_title").setup,
				preview_split = "right",
				override = function(conf)
					conf.row = 0
					conf.title = "Files"
					conf.title_pos = "center"
					return conf
				end,
			},

			preview_win = {
				update_on_cursor_moved = true,
				preview_method = "fast_scratch",
				disable_preview = function(filename)
					return false
				end,
				win_options = {},
			},

			-- Configuration for the floating action confirmation window
			confirmation = {
				min_width = 40,
				max_width = 60,
				width = nil,
				min_height = 5,
				max_height = 15,
				height = nil,
				border = "rounded",
				win_options = {
					winblend = 0,
				},
			},
		},
		require("scripts.oil_confirm").setup(),
	},
}
