-- Enable your lsp here by adding the lsp server name, the lspconfig plugin will pull the config file for you
vim.lsp.enable({
	"neocmake",
	"qmlls",
	"cssls",
	"lua_ls",
	"jsonls",
	"arduino_language_server",
	"bashls",
	"hyprls",
	"clangd",
	"verible",
})

-- Configure error/warnings interface
local severity = vim.diagnostic.severity
vim.diagnostic.config({
	virtual_text = true,
	severity_sort = true,
	float = {
		style = "minimal",
		border = "rounded",
		header = "",
		prefix = "",
	},
	signs = {
		text = {
			[severity.ERROR] = " ",
			[severity.WARN] = " ",
			[severity.HINT] = " ",
			[severity.INFO] = " ",
		},
	},
})
