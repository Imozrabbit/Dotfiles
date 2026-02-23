return {
	"nvim-treesitter/nvim-treesitter",
	lazy = false,
	build = ":TSUpdate",
	config = function()
		require("nvim-treesitter").setup({
			install_dir = vim.fn.stdpath("data") .. "/treesitter",
			highlight = { enable = true },
			indent = { enable = true },
			auto_install = false,
		})
		require("nvim-treesitter").install({
			"arduino",
			"c",
			"python",
			"make",
			"cmake",
			"lua",
			"yaml",
			"vim",
			"vimdoc",
			"dockerfile",
			"gitignore",
			"bash",
			"zsh",
			"markdown",
			"markdown_inline",
			"query",
			"qmljs",
			"html",
			"json",
			"css",
			"javascript",
			"typescript",
			"tmux",
			"hyprlang",
		})
	end,
}
