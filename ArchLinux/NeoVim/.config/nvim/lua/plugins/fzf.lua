return {
	"ibhagwan/fzf-lua",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	---@module "fzf-lua"
	---@type fzf-lua.Config|{}
	---@diagnostic disable: missing-fields

	cmd = "FzfLua",

	opts = {
		files = {
			follow = true,
		},
	},
	---@diagnostic enable: missing-fields

	config = function(_, opts)
		local fzf = require("fzf-lua")
		fzf.setup(opts)
		fzf.register_ui_select(function(ui_opts)
			if ui_opts.kind == "command-menu" then
				return {
					fzf_opts = {
						["--delimiter"] = "[.] ",
						["--with-nth"] = "2..",
					},
				}
			end

			return {}
		end)
	end,

	keys = {
		{
			"<leader>ff",
			function()
				require("fzf-lua").files()
			end,
			desc = "Find file in current working directory",
		},

		{
			"<leader>fg",
			function()
				require("fzf-lua").live_grep()
			end,
			desc = "Find words in current working directory",
		},

		{
			"<leader>fc",
			function()
				require("fzf-lua").files({ cwd = vim.fs.abspath("~/.config") })
			end,
			desc = "Find configs in .config directory",
		},

		{
			"<leader>fd",
			function()
				require("fzf-lua").files({ cwd = vim.fs.abspath("~/Documents/Dotfiles/ArchLinux") })
			end,
			desc = "Find configs in dotfile directory",
		},

		{
			"<leader>f<leader>",
			function()
				require("fzf-lua").buffers()
			end,
			desc = "Find existing buffers",
		},

		{
			"<leader>fo",
			function()
				require("fzf-lua").oldfiles()
			end,
			desc = "Find old files",
		},

		{
			"<leader>fs",
			function()
				require("fzf-lua").builtin()
			end,
			desc = "Open all the fuzzy find options",
		},
	},
}
