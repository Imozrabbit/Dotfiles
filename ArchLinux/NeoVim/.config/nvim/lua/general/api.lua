local api = vim.api

-- Set up nvim tree background
vim.cmd("autocmd VimEnter * hi NvimTreeNormal guibg=NONE")
vim.cmd("autocmd VimEnter * hi NvimTreeNormalNC guibg=NONE")
vim.cmd("autocmd VimEnter * hi NvimTreeWinSeparator guibg=NONE")
