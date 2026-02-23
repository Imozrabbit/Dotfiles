vim.cmd("let g:netrw_liststyle = 3")

local opt = vim.opt

opt.number = true
opt.relativenumber = true

-- tabs & indentation
opt.tabstop = 4 -- 2 spaces for tabs (prettier default)
opt.shiftwidth = 4 -- 2 spaces for indent width
opt.expandtab = true -- expand tab to spaces
opt.autoindent = true -- copy indent from current line when starting new one
opt.breakindent = true -- make wrapping follow the nesting order

-- search settings
opt.ignorecase = true -- ignore case when searching
opt.smartcase = true -- if you include mixed case in your search, assumes you want case-sensitive

-- Just for visual clarity
opt.cursorline = true
opt.showmode = false -- Hide the mode all the way on the bottom cuz it already shows on the lualine
opt.signcolumn = "yes" -- Alway leave a column all the way on the left for diagnostics, even if empty
opt.fillchars = { eob = " " } -- Hide the ugly ~ after EOF

-- turn on termguicolors for colorscheme to work
opt.termguicolors = true
opt.background = "dark"

-- backsapce
opt.backspace = "indent,eol,start" -- allow backspace on indent, end of line or insert mode start position

-- split windows
opt.splitright = true -- split vertical window to the right
opt.splitbelow = true -- split horizontal window to the bottom

-- Keep cursor at least { } rows from top/bot
opt.scrolloff = 7

-- Decrease time
opt.updatetime = 250 -- Decrease update time
opt.timeoutlen = 300 -- Decrease mapped sequence wait time

-- undo dir settings
opt.backup = false

-- Enable mouse mode, can be useful for resizing splits for example
opt.mouse = "a"

-- Make popup window have a border for visual clarity
vim.o.winborder = "rounded"

-- Make cursor look normal in terminal/tmux
vim.api.nvim_create_autocmd("VimLeave", {
	pattern = "*",
	callback = function()
		vim.opt.guicursor = "a:ver25"
	end,
})

-- LSP symbols
local severity = vim.diagnostic.severity
vim.diagnostic.config({
	signs = {
		text = {
			[severity.ERROR] = " ",
			[severity.WARN] = " ",
			[severity.HINT] = " ",
			[severity.INFO] = " ",
		},
	},
})
