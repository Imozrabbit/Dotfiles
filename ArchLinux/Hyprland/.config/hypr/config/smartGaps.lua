------- If only one window is visible, disable the border and gaps -------
return {
	hl.window_rule({
		border_size = 0,
		rounding = 0,
		match = {
			float = false,
			workspace = "w[tv1]",
		},
	}),

	hl.window_rule({
		border_size = 0,
		rounding = 0,
		match = {
			float = false,
			workspace = "f[1]",
		},
	}),

	hl.workspace_rule({
		workspace = "w[tv1]",
		gaps_out = 0,
		gaps_in = 0,
	}),

	hl.workspace_rule({
		workspace = "f[1]",
		gaps_out = 0,
		gaps_in = 0,
	}),
}
