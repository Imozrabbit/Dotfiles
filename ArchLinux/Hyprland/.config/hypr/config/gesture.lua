-- Switch workspace
hl.gesture({
	fingers = 4,
	direction = "horizontal",
	action = "workspace",
})

-- Scroll
hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "scroll_move",
})

-- Zoom
hl.gesture({
	fingers = 2,
	direction = "pinch",
	action = "cursor_zoom",
	mode = "live",
	zoom_level = 1,
})
