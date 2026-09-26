hl.window_rule({
	name = "Proton Valheim window rule",
	match = {
		class = "steam_app_892970",
		title = "Valheim",
	},
	content = "game",
	confine_pointer = true,
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
})

hl.window_rule({
	name = "Native Valheim window rule",
	match = {
		class = "valheim.x86_64",
		title = "Valheim",
	},
	content = "game",
	confine_pointer = true,
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
})
