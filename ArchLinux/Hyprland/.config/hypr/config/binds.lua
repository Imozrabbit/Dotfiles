local mainMod = "SUPER"

-- Basic Fonctions
hl.bind(mainMod .. "+ RETURN", hl.dsp.exec_cmd(TERMINAL)) -- Open new terminal
hl.bind(mainMod .. "+ V", hl.dsp.window.float("toggle")) -- Toggle float
hl.bind(mainMod .. "+ F", hl.dsp.window.fullscreen("fullscreen", "toggle")) -- Toggle fullscreen mode

-- Open applications
hl.bind(mainMod .. "+ E", hl.dsp.exec_cmd(FILEMANAGER)) -- Open file manager
hl.bind(mainMod .. "+ SPACE", hl.dsp.exec_cmd(MENU)) -- Open app launcher
hl.bind(mainMod .. "+ B", hl.dsp.exec_cmd("zen-browser")) -- Open zen browser
hl.bind(mainMod .. "+ N", hl.dsp.exec_cmd(NOTES)) -- Open obsidian
hl.bind(mainMod .. "+ R", hl.dsp.exec_cmd("swaync-client -t")) -- Open side hub

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. "+ H", hl.dsp.focus({ direction = "left" })) -- Move focus to left
hl.bind(mainMod .. "+ L", hl.dsp.focus({ direction = "right" })) -- Move focus to right
hl.bind(mainMod .. "+ K", hl.dsp.focus({ direction = "up" })) -- Move focus to up
hl.bind(mainMod .. "+ J", hl.dsp.focus({ direction = "down" })) -- Move focus to down

for i = 1, 7 do
	local key = i % 10 -- 10 maps to key 0
	-- Switch workspaces with mainMod + [0-9]
	hl.bind(mainMod .. "+" .. key, hl.dsp.focus({ workspace = i }))
	-- Move active window to a workspace with mainMod + SHIFT + [0-9]
	hl.bind(mainMod .. "+ SHIFT +" .. key, hl.dsp.window.move({ workspace = i }))
end

-- special workspace for music player rmpc
hl.bind(mainMod .. "+ M", hl.dsp.workspace.toggle_special("rmpc"))
-- Special workspace for steam
hl.bind(mainMod .. "+ S", hl.dsp.workspace.toggle_special("steam"))

-- Scrolling with mainMod + scroll
local function scrollingBind(keybind, msg)
	hl.bind(keybind, function()
		local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
		if workspace == nil or workspace.tiled_layout ~= "scrolling" then
			return
		end
		return hl.dispatch(hl.dsp.layout(msg))
	end)
end
scrollingBind(mainMod .. " + mouse_down", "move -100") -- Scroll right
scrollingBind(mainMod .. " + mouse_up", "move +100") -- Scroll left
scrollingBind(mainMod .. " + mouse:274", "promote") -- Promote window
scrollingBind(mainMod .. " + mouse:276", "colresize +conf") -- Cycle column width
scrollingBind(mainMod .. " + mouse:275", "fit tobeg") -- Fit mode

-- Move/resize windows with mainMod + LMR/RMB and dragging
hl.bind(mainMod .. "+ mouse:272", hl.dsp.window.drag())
hl.bind(mainMod .. "+ mouse:273", hl.dsp.window.resize())

-- Open the windows-like alt-tab view
local layout = "smartgrid"
hl.bind(
	mainMod .. "+ TAB",
	hl.dsp.exec_cmd("qs ipc -p /home/Zrabbit/.config/quickshell/alt-tab_view/shell.qml call expose toggle " .. layout)
)

-- Set up knob for volume control
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
--hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), {locked = true})

-- Set up media control
hl.bind("F7", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("F8", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("F9", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("F10", hl.dsp.exec_cmd("rmpc remote keybind p"), { locked = true })
hl.bind("F11", hl.dsp.exec_cmd('rmpc remote keybind ","'), { locked = true, repeating = true })
hl.bind("F12", hl.dsp.exec_cmd('rmpc remote keybind "."'), { locked = true, repeating = true })

-- Screenshot
hl.bind(mainMod .. "+ DELETE", hl.dsp.exec_cmd("/home/Zrabbit/.config/shell/script/Screenshot/screenshot_region"))

-- Close & Kill steam
local function close_bind()
	return function()
		local window = hl.get_active_window()
		-- If steam is the active window then shut it down
		if window and window.class == "steam" and window.title == "Steam" then
			hl.dispatch(hl.dsp.exec_cmd("/home/Zrabbit/.config/shell/script/Steam/steam_clean -shutdown"))
			return
		end
		-- Otherwise close normally
		hl.dispatch(hl.dsp.window.close())
	end
end
hl.bind(mainMod .. "+ Q", close_bind())
