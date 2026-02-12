return {
	"goolord/alpha-nvim",
	event = "VimEnter",
	config = function()
		local alpha = require("alpha")
		local dashboard = require("alpha.themes.dashboard")

		-- Set header
		dashboard.section.header.val = {
			"                                                     ",
			"  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗ ",
			"  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║ ",
			"  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║ ",
			"  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║ ",
			"  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║ ",
			"  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝ ",
			"                                                     ",
		}

		-- Set menu
		dashboard.section.buttons.val = {
			dashboard.button("e", "  > New File", "<cmd>ene<CR>"),
			dashboard.button("SPC ee", "  > Toggle file explorer", "<cmd>NvimTreeToggle<CR>"),
			dashboard.button("-", "  > Open current directory", "<cmd>Oil<CR>"),
			dashboard.button("SPC ff", "󰱼  > Find File", function()
				require("fzf-lua").files()
			end),
			dashboard.button("SPC fd", "  > Find Dotfile File", function()
				require("fzf-lua").files({ cwd = vim.fs.abspath("~/Documents/Dotfiles/ArchLinux") })
			end),
			dashboard.button("SPC fg", "  > Grep Word", function()
				require("fzf-lua").live_grep()
			end),
			dashboard.button("wr", "  > Restore Session For Current Directory", "<cmd>AutoSession restore<CR>"),
			dashboard.button("l", "  > Open plugin manager", "<cmd>Lazy<CR>"),
			dashboard.button("m", "󰒋  > Open LSP manager", "<cmd>Mason<CR>"),
			dashboard.button("q", "󰩈  > Quit", "<cmd>:q<CR>"),
		}

		-- Send config to alpha
		alpha.setup(dashboard.opts)

		-- Disable folding on alpha buffer
		vim.cmd([[autocmd FileType alpha setlocal nofoldenable]])
	end,
}
