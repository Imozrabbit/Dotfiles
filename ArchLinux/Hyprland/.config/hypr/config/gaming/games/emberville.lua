hl.window_rule({
	name = "Emberville follow the general gaming window rule",
	match = {
		class = "steam_app_5355880",
		title = "Emberville",
	},
	content = "game",
	fullscreen = true,
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
})
