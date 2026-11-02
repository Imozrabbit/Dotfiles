-- Add blur for multiple bar module panel windows
hl.layer_rule({
	match = {
		namespace = "^(calendar-menu|battery-menu|bluetooth-menu|wifi-menu|proton-manager|quickshell-bottom-bar)$",
	},
	blur = true,
	ignore_alpha = 0.5,
	animation = "slide bottom",
})

hl.layer_rule({
	match = {
		namespace = "quickshell-top-media",
	},
	blur = true,
	ignore_alpha = 0.5,
	animation = "slide top",
})

hl.layer_rule({
	match = {
		namespace = "quickshell-bar-tooltip",
	},
	blur = true,
	ignore_alpha = 0.5,
	animation = "fade",
})

-- Add blur and transparency to calendar module
hl.layer_rule({
	match = {
		namespace = "quickshell-calendar",
	},
	animation = "slide",
	blur = true,
	ignore_alpha = 0.5,
})

-- Add blur for swaync the notification center
hl.layer_rule({
	match = { namespace = "swaync-control-center" },
	blur = true,
	ignore_alpha = 0.3,
	animation = "slide",
})
hl.layer_rule({
	match = { namespace = "quickshell-command-center" },
	blur = true,
	ignore_alpha = 0.5,
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
	match = { namespace = "level-osd" },
	blur = true,
	ignore_alpha = 0.3,
	animation = "slide bottom",
})

-- Make alt-tab-view by quickshell dim around and blur
hl.layer_rule({
	match = { namespace = "quickshell:expose" },
	blur = true,
	dim_around = true,
	animation = "fade",
})

-- Make rofi blur and change its animation
hl.layer_rule({
	match = { namespace = "rofi" },
	blur = true,
	ignore_alpha = 0.1,
	animation = "popin",
})

-- Set animation for screenshot
hl.layer_rule({
	match = { namespace = "selection" },
	animation = "fade",
})

-- Make hex-hud appear from the edge
hl.layer_rule({
	match = {
		namespace = "hex-hud",
	},
	animation = "popin",
})
