return {
	"UtkarshVerma/molokai.nvim",
	priority = 1000,
	config = function()
		require("molokai").setup({ transparent = true })
		vim.cmd("colorscheme molokai")

		-- Disable highlight for brackets and delimiters, that shit hurts me eyes
		vim.api.nvim_set_hl(0, "@punctuation.bracket", { link = "Normal" })
		vim.api.nvim_set_hl(0, "Delimiter", { link = "Normal" })

		-----------------------------------------------------------------------------------------------
		-----------------------                  Floating Window                -----------------------
		-----------------------------------------------------------------------------------------------
		-- Change the floating window more transparent
		vim.api.nvim_set_hl(0, "Pmenu", { link = "Normal" })
		vim.api.nvim_set_hl(0, "PmenuThumb", { bg = "#3A5C8F" })
		vim.api.nvim_set_hl(0, "NormalFloat", { link = "Normal" })
		vim.api.nvim_set_hl(0, "NormalFloatBorder", { fg = "#57b3c5", bg = "NONE" })
		vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#57b3c5", bg = "NONE" })

		-----------------------------------------------------------------------------------------------
		-----------------------                    Indent Scope                 -----------------------
		-----------------------------------------------------------------------------------------------
		vim.api.nvim_set_hl(0, "MiniIndentscopeSymbol", { fg = "#702963" })

		-----------------------------------------------------------------------------------------------
		-----------------------                       Blink                     -----------------------
		-----------------------------------------------------------------------------------------------
		-- Change the color of blink's popup menu scrollbar
		vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelpBorder", { bg = "NONE", fg = "#57b3c5" })
		vim.api.nvim_set_hl(0, "CmpDocumentationBorder", { bg = "NONE", fg = "#57b3c5" })

		-----------------------------------------------------------------------------------------------
		-----------------------                        LSP                      -----------------------
		-----------------------------------------------------------------------------------------------
		-- Change the color of lsp's hover menu
		-- vim.api.nvim_set_hl(0, "LspFloatWinNormal", { link = "Normal" })
		vim.api.nvim_set_hl(0, "LspInfoBorder", { bg = "NONE", fg = "#57b3c5" })
	end,
}
