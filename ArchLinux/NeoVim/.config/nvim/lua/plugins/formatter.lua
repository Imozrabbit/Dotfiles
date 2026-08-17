return {
	"stevearc/conform.nvim",
	opts = {
		formatters_by_ft = {
			lua = { "stylua" },
			c = { "clang-format" },
			cpp = { "clang-format" },
			arduino = { "clang-format" },
			verilog = { "verible" },
			systemverilog = { "verible" },
		},

		formatters = {
			["clang-format"] = {
				prepend_args = {
					"--style=file:" .. vim.fn.expand("~/.config/nvim/after/clang-format/style"),
				},
			},
		},

		format_on_save = {
			-- Format the file on save
			timeout_ms = 500,
			lsp_format = "fallback",
		},
	},
}
