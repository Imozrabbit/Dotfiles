return {
	"jedrzejboczar/nvim-dap-cortex-debug",
	dependencies = {
		"mfussenegger/nvim-dap",
		{
			"rcarriga/nvim-dap-ui",
			dependencies = {
				"nvim-neotest/nvim-nio",
			},
		},
	},
	config = function()
		local dap, dapui, widgets, vscode =
			require("dap"), require("dapui"), require("dap.ui.widgets"), require("dap.ext.vscode")

		-------------------------------------------------------------------------------------------
		-- Cortex debugger setup
		-------------------------------------------------------------------------------------------
		require("dap-cortex-debug").setup({
			debug = false, -- log debug messages
			-- path to cortex-debug extension, supports vim.fn.glob
			-- by default tries to guess: mason.nvim or VSCode extensions
			extension_path = nil,
			lib_extension = nil, -- shared libraries extension, tries auto-detecting, e.g. 'so' on unix
			node_path = "node", -- path to node.js executable
			dapui_rtt = true, -- register nvim-dap-ui RTT element
			-- make :DapLoadLaunchJSON register cortex-debug for C/C++, set false to disable
			dap_vscode_filetypes = { "c", "cpp" },
			rtt = {
				buftype = "Terminal", -- 'Terminal' or 'BufTerminal' for terminal buffer vs normal buffer
			},
		})

		-- Custom launch.json location
		dap.providers.configs["dap.launch.json"] = function()
			local path = vim.fn.getcwd() .. "/debug/launch.json"
			return vscode.getconfigs(path)
		end

		-------------------------------------------------------------------------------------------
		-- Debugger UI hook and set up
		-------------------------------------------------------------------------------------------
		dap.listeners.before.attach.dapui_config = function()
			dapui.open()
		end
		dap.listeners.before.launch.dapui_config = function()
			dapui.open()
		end
		dap.listeners.before.event_terminated.dapui_config = function()
			dapui.close()
		end
		dap.listeners.before.event_exited.dapui_config = function()
			dapui.close()
		end

		dapui.setup({
			layouts = {
				{
					position = "left",
					size = 96,
					elements = {
						{ id = "scopes", size = 0.4 },
						{ id = "rtt", size = 0.6 },
					},
				},
			},
		})

		-------------------------------------------------------------------------------------------
		-- Debugger keybinds
		-------------------------------------------------------------------------------------------
		vim.keymap.set("n", "<Leader>d1", function()
			dap.continue()
		end, { desc = "Continue/Start debugging" })

		vim.keymap.set("n", "<Leader>d2", function()
			dap.step_over()
		end, { desc = "Step over" })

		vim.keymap.set("n", "<Leader>d3", function()
			dap.step_into()
		end, { desc = "Step into" })

		vim.keymap.set("n", "<Leader>d4", function()
			dap.step_out()
		end, { desc = "Step out" })

		vim.keymap.set("n", "<Leader>dt", function()
			dap.toggle_breakpoint()
		end, { desc = "Toggle breakpoint" })

		vim.keymap.set("n", "<Leader>db", function()
			dap.set_breakpoint()
		end, { desc = "Set breakpoint" })

		vim.keymap.set("n", "<Leader>dsl", function()
			dap.set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
		end, { desc = "Set breakpoint with an optional log message" })

		vim.keymap.set("n", "<Leader>dr", function()
			dap.repl.open()
		end, { desc = "Open an interactive debugging console" })

		vim.keymap.set("n", "<Leader>dl", function()
			dap.run_last()
		end, { desc = "Restart the most recently used debugging config" })

		vim.keymap.set({ "n", "v" }, "<Leader>dh", function()
			widgets.hover()
		end, { desc = "Open a floating window showing the evaluated value" })

		vim.keymap.set({ "n", "v" }, "<Leader>dp", function()
			widgets.preview()
		end, { desc = "Open a preview window showing the evaluated value" })

		vim.keymap.set("n", "<Leader>df", function()
			widgets.centered_float(widgets.frames)
		end, { desc = "Open a centered floating window displaying the call stack" })

		vim.keymap.set("n", "<Leader>ds", function()
			widgets.centered_float(widgets.scopes)
		end, { desc = "Open a centered floating window showing scoped variables" })
	end,
}
