-- Primary
hl.monitor({
	output = "DP-1",
	mode = "3440x1440@164.90Hz",
	position = "0x0",
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
	--icc = "/home/Zrabbit/.config/hypr/rtings-icc-profile.icm",
})

-- Secondary Vertical
hl.monitor({
	output = "DP-2",
	mode = "1920x1080@165.00Hz",
	position = "3440x-500",
	scale = 1,
	bitdepth = 8,
	transform = 1,
	vrr = 3,
	cm = "auto",
})

-- Third vertical for monitoring system
hl.monitor({
	output = "HDMI-A-1",
	mode = "1920x515@60.00Hz",
	position = "4520x-500",
	scale = 1,
	transform = 1,
})
