-- Add blur for waybar and its popups, turn off its unnecessary animations
hl.layer_rule({
	match = { namespace = "waybar" },
	blur = true,
	ignore_alpha = 0.1,
	no_anim = true,
})

-- Add blur for swaync the notification center
hl.layer_rule({
	match = { namespace = "swaync-control-center" },
	blur = true,
	ignore_alpha = 0.3,
	animation = "slide",
})
-- Add blur for the swaync popup notifications
hl.layer_rule({
	match = { namespace = "swaync-notification-window" },
	blur = true,
	ignore_alpha = 0.1,
	animation = "slide",
})

-- Make volume-osd by quickshell blur and change its awful animation
hl.layer_rule({
	match = { namespace = "volume-osd" },
	blur = true,
	ignore_alpha = 0.3,
	animation = "slide bottom",
})

-- Make alt-tab-view by quickshell dim around and blur
hl.layer_rule({
	match = { namespace = "quickshell:expose" },
	blur = true,
	dim_around = true,
})

-- Make rofi blur and change its animation
hl.layer_rule({
	match = { namespace = "rofi" },
	blur = true,
	ignore_alpha = 0.1,
	animation = "fade",
})

-- Make GPU & CPU OSD blur
hl.layer_rule({
	match = { namespace = "system-osd" },
	blur = true,
	ignore_alpha = 0,
})
