return {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local lazy_status = require("lazy.status") -- to configure lazy pending updates count
		-- Theme setup
		local custom_dark = require("lualine.themes.ayu_dark")
		-- Change the background of lualine_c section for normal mode
		custom_dark.normal.c.fg = "#FF61EF"
		require("lualine").setup({
			options = {
				theme = custom_dark,
				section_separators = { left = " ", right = " " },
				component_separators = { left = "", right = "" },
			},
			sections = {
				lualine_c = {
					{
						"filename",
						newfile_status = true,
						path = 3,
						symbols = {
							modified = "󰷥 ", -- Text to show when the file is modified.
							readonly = " ", -- Text to show when the file is non-modifiable or readonly.
							unnamed = "[No Name]", -- Text to show for unnamed buffers.
							newfile = "󰎔 ", -- Text to show for newly created file before first write
						},
					},
				},

				lualine_x = {
					{
						lazy_status.updates,
						cond = lazy_status.has_updates,
						color = { fg = "#ff9e64" },
					},
					{ require("opencode").statusline },
					{
						"lsp_status",
						icon = "󰒋", -- f013
						symbols = {
							spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }, -- Standard unicode symbols to cycle through for LSP progress
							done = " ", -- Standard unicode symbol for when LSP is done:
							separator = " ", -- Delimiter inserted between LSP names:
							-- ignore_lsp = {}, -- List of LSP names to ignore (e.g., `null-ls`):
							show_name = true, -- Display the LSP name
						},
					},
					{ "filetype" },
				},
			},
		})
	end,
}
