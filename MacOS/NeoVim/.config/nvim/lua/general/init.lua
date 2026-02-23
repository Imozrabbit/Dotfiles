require("general.keymaps")
require("general.options")
require("general.api")
require("general.lsp")

-- Make the lsp log less noisy
-- default value : 3 for warnings and errors
vim.lsp.set_log_level(4)
