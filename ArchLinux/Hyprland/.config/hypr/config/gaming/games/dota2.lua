-- Dota2
hl.window_rule({
	name = "Dota 2 follow the general gaming window rule",
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
