-----------------------------------------------------------------------
-- Make sure games appear on workspace 7
-----------------------------------------------------------------------
local GAME_WORKSPACE = 7

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

hl.window_rule({
	name = "Force steam games to be opaque and to appear on workspace 7",
	match = {
		class = "^(steam_app_.*|valheim[.]x86_64|Project Zomboid)$",
	},
	content = "game",
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
})

hl.window_rule({
	name = "Stoneshard follow the general gaming window rule",
	match = {
		class = "",
		title = "Stoneshard",
	},
	content = "game",
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
})

hl.window_rule({
	name = "Stoneshard follow the general gaming window rule",
	match = {
		class = "dota2",
		title = "Dota 2",
	},
	content = "game",
	confine_pointer = true,
	fullscreen = true,
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
})
