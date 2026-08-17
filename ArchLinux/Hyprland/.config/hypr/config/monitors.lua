-- Primary
hl.monitor({
	output = "eDP-1",
	mode = "1920x1080@60.01Hz",
	position = "0x0",
	scale = 1,
	vrr = 2, -- Fullscreen only
	bitdepth = 8,
	cm = "auto",
	max_luminance = 300,
	min_luminance = 0.0,
})

-- External monitor
hl.monitor({
	output = "DP-2",
	mode = "3440x1440@164.90Hz",
	scale = 1,
	vrr = 2, -- Fullscreen only
	bitdepth = 8,
	cm = "auto",
	supports_hdr = 1,
	supports_wide_color = 0,
	sdr_min_luminance = 0.000,
	sdr_max_luminance = 1000,
	sdrbrightness = 0.3,
	sdrsaturation = 1.18,
	max_luminance = 1000,
	min_luminance = 0.0,
})
