------------------ Set up workspaces for main monitors ------------------
hl.workspace_rule({
	workspace = "1",
	monitor = "eDP-1",
	layout = "scrolling",
	persistent = true,
})

-------------- Set up workspaces for specific applications --------------
-- Stremio
hl.workspace_rule({
	workspace = "4",
	monitor = "eDP-1",
	layout = "master",
})

-- Orcaslicer
hl.workspace_rule({
	workspace = "5",
	monitor = "eDP-1",
	layout = "master",
})

-- MATLAB
hl.workspace_rule({
	workspace = "6",
	monitor = "eDP-1",
	layout = "scrolling",
})

-- Games
hl.workspace_rule({
	workspace = "7",
	monitor = "eDP-1",
	layout = "master",
})
