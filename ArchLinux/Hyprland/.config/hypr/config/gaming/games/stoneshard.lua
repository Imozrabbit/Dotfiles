-- StoneShard
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
