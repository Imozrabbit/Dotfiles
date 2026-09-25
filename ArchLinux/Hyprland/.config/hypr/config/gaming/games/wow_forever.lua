-- Valheim, Project Zomboid
hl.window_rule({
	name = "Force World of Warcraft to be opaque and to appear on workspace 7",
	match = {
		class = "steam_app_default",
		title = "World of Warcraft",
	},
	content = "game",
	--confine_pointer = true,
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
})
