return {
	"nvim-tree/nvim-tree.lua",
	version = "*",
	lazy = false,
	dependencies = {
		"nvim-tree/nvim-web-devicons",
	},
	keys = {
		{ "<leader>ee", "<cmd>NvimTreeToggle<CR>", desc = "Toggle the file explorer" },
		{ "<leader>ee", "<cmd>NvimTreeToggle<CR>", desc = "Toggle file explorer" },
		{ "<leader>ef", "<cmd>NvimTreeFindFileToggle<CR>", desc = "Toggle file explorer on file" },
		{ "<leader>ec", "<cmd>NvimTreeCollapse<CR>", desc = "Collapse file explorer" },
		{ "<leader>er", "<cmd>NvimTreeRefresh<CR>", desc = "Refresh file explorer" },
	},
	config = function()
		local nvimtree = require("nvim-tree")

		-- disable netrw at the very start
		vim.g.loaded_netrw = 1
		vim.g.loaded_netrwPlugin = 1

		-- enable 24-bit colour
		vim.opt.termguicolors = true

		--Set up local variables
		local function open_win_config_func()
			local scr_w = vim.opt.columns:get()
			local scr_h = vim.opt.lines:get()
			local tree_w = 80
			local tree_h = math.floor(tree_w * scr_h / scr_w)
			return {
				border = "rounded",
				relative = "editor",
				width = tree_w,
				height = tree_h,
				col = (scr_w - tree_w) / 3,
				row = (scr_h - tree_h) / 2,
			}
		end

		require("nvim-tree").setup({
			sort = {
				sorter = "case_sensitive",
			},

			view = {
				signcolumn = "yes",
				float = {
					enable = false,
					open_win_config = open_win_config_func,
				},
				cursorline = false,
			},

			modified = {
				enable = true,
			},

			renderer = {
				group_empty = true,
				indent_width = 3,
				icons = {
					show = {
						hidden = true,
					},
					git_placement = "after",
					bookmarks_placement = "after",
					symlink_arrow = " -> ",
					glyphs = {
						folder = {
							arrow_closed = " ",
							arrow_open = " ",
							default = " ",
							open = " ",
							empty = " ",
							empty_open = " ",
							symlink = " ",
							symlink_open = " ",
						},
						default = "󱓻 ",
						symlink = " ",
						bookmark = " ",
						modified = " ",
						hidden = "󱙝 ",
						git = {
							unstaged = " ",
							staged = " ",
							unmerged = "󰧾 ",
							untracked = " ",
							renamed = " ",
							deleted = " ",
							ignored = " ",
						},
					},
				},
			},

			filters = {
				git_ignored = false,
				custom = { ".DS_Store" }, -- For macos
			},

			hijack_cursor = true,
			sync_root_with_cwd = true,
		})
	end,
}
