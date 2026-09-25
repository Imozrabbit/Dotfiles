-- Gamescope
hl.window_rule({
	name = "Make games launched with gamescope opaque and appear on the workspace 7",
	match = {
		initial_class = "gamescope",
		class = "gamescope",
	},
	content = "game",
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
	--immediate = true, -- Force window to allow tearing for competitive games
	--confine_pointer = true, -- Confine cursur in the game window frame
})
