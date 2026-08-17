------------------ Set up workspaces for main monitors ------------------
hl.workspace_rule({
	workspace = "1",
	monitor = "DP-1",
	layout = "scrolling",
	persistent = true,
})

hl.workspace_rule({
	workspace = "2",
	monitor = "DP-2",
	persistent = true,
})

hl.workspace_rule({
	workspace = "3",
	monitor = "HDMI-A-1",
	gaps_out = 2,
	gaps_in = 2,
	layout = "dwindle",
	persistent = true,
})

-------------- Set up workspaces for specific applications --------------
-- Stremio
hl.workspace_rule({
	workspace = "4",
	monitor = "DP-1",
	layout = "master",
})

-- Orcaslicer
hl.workspace_rule({
	workspace = "5",
	monitor = "DP-1",
	layout = "master",
})

-- MATLAB
hl.workspace_rule({
	workspace = "6",
	monitor = "DP-1",
	layout = "scrolling",
})

-- Games
hl.workspace_rule({
	workspace = "7",
	monitor = "DP-1",
	layout = "master",
})

---------------------- Set up my secondary monitor ----------------------
hl.workspace_rule({
	workspace = "m[DP-2]",
	gaps_out = 2,
	gaps_in = 4,
	layout = "scrolling",
	layout_opts = {
		direction = "down",
	},
})
