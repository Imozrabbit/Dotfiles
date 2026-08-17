require("general.keymaps")
require("general.options")
require("general.api")
require("general.lsp")
require("general.filetype")

-- Make the lsp log less noisy
-- default value
--      1 : Basically everything
--      2 : General informations
--      3 : warnings and errors
--      4 : Error only
--      5 : Off
vim.lsp.log.set_level(4)
