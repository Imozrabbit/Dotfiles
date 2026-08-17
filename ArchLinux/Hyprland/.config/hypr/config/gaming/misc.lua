-- Set up R2modman
hl.window_rule({
	name = "make r2modman window float and opaque",
	match = {
		class = "r2modman",
	},
	float = true,
	persistent_size = true,
	opaque = true,
	xray = false,
})
