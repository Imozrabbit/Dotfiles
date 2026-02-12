vim.g.mapleader = " "

local keymap = vim.keymap

---------------------------------------------------------------------------------------------------------------
-----------------------                             General                             -----------------------
---------------------------------------------------------------------------------------------------------------
-- window management
keymap.set("n", "<leader>sv", "<C-w>v", { desc = "Split window vertically" })
keymap.set("n", "<leader>sh", "<C-w>s", { desc = "Split window horizontally" })
keymap.set("n", "<leader>se", "<C-w>=", { desc = "Make split equal size" })
keymap.set("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close current split" })

keymap.set("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "Open new tab" })
keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close current tab" })
keymap.set("n", "<leader>tn", "<cmd>tabn<CR>", { desc = "Go to next tab" })
keymap.set("n", "<leader>tp", "<cmd>tabp<CR>", { desc = "Go to previous tab" })
keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open current buffer in new tab" })

-- Clear search in normal mode on pressing ESC
keymap.set("n", "<ESC>", "<cmd>nohlsearch<CR>")

-- Formatting
keymap.set("n", "<leader>F", function()
	require("conform").format()
end, { desc = "Format current file" })

---------------------------------------------------------------------------------------------------------------
-----------------------                                LSP                              -----------------------
---------------------------------------------------------------------------------------------------------------
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
	callback = function(event)
		local map = function(keys, func, desc)
			vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
		end
		map("gld", require("fzf-lua").lsp_definitions, "Goto Definition")
		map("glr", require("fzf-lua").lsp_references, "Goto Reference")
		map("gli", require("fzf-lua").lsp_implementations, "Goto Implementation")
		map("glt", require("fzf-lua").lsp_typedefs, "Goto Type Definition")
		map("gls", require("fzf-lua").lsp_document_symbols, "Goto Document Symbols")
		map("glS", require("fzf-lua").lsp_workspace_symbols, "Goto All Document Symbols")
		map("glR", vim.lsp.buf.rename, "Rename")
		map("gla", vim.lsp.buf.code_action, "Code Action")
		map("K", vim.lsp.buf.hover, "Hover Documentation")
		map("glD", vim.lsp.buf.declaration, "Goto Declaration")
		map("g<leader>", vim.diagnostic.open_float, "Open diagnostics")
	end,
})

---------------------------------------------------------------------------------------------------------------
-----------------------                             OpenCode                            -----------------------
---------------------------------------------------------------------------------------------------------------
keymap.set({ "n", "x" }, "<leader>oa", function()
	require("opencode").ask("@this: ", { submit = true })
end, { desc = "Ask opencode…" })

keymap.set({ "n", "x" }, "<leader>ox", function()
	require("opencode").select()
end, { desc = "Execute opencode action…" })

keymap.set({ "n", "t" }, "<leader>oo", function()
	require("opencode").toggle()
end, { desc = "Toggle opencode" })

keymap.set({ "n", "x" }, "<leader>or", function()
	return require("opencode").operator("@this ")
end, { desc = "Add range to opencode", expr = true })

keymap.set("n", "<leader>ol", function()
	return require("opencode").operator("@this ") .. "_"
end, { desc = "Add line to opencode", expr = true })

keymap.set("n", "<leader>ou", function()
	require("opencode").command("session.half.page.up")
end, { desc = "Scroll opencode up" })

keymap.set("n", "<leader>od", function()
	require("opencode").command("session.half.page.down")
end, { desc = "Scroll opencode down" })
