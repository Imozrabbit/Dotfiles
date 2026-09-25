-- Valheim, Project Zomboid
hl.window_rule({
	name = "Force steam games to be opaque and to appear on workspace 7",
	match = {
		class = "Project Zomboid",
	},
	content = "game",
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
})
