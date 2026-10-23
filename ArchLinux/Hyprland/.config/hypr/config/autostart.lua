hl.on("hyprland.start", function()
	-- Password box Authentification Agent
	hl.exec_cmd("systemctl --user start hyprpolkitagent")

	-- Notification Daemon
	hl.exec_cmd("swaync")

	-- Wallpaper
	hl.exec_cmd("/home/Zrabbit/.config/quickshell/wallpaper_switcher/scripts/apply.sh")

	-- Setup Cursor
	hl.exec_cmd("hyprctl setcursor Bibata-Modern-Ice 24")

	-- Idle Daemon
	hl.exec_cmd("hypridle")

	-- Clipboard History
	hl.exec_cmd("wl-paste --type text/plain --watch cliphist store # Stores only text data")
	hl.exec_cmd("wl-paste --type image --watch cliphist store # Stores only image data")

	-- QuickShell
	hl.exec_cmd("qs -c volume-osd -d")
	hl.exec_cmd("qs -c system-osd -d")
	hl.exec_cmd("qs -c clock -d")
	hl.exec_cmd("qs -c ram-osd -d")
	hl.exec_cmd("qs -c weather -d")
	hl.exec_cmd("qs -c alt-tab_view -d")
	hl.exec_cmd("qs -c calendar -d")
	hl.exec_cmd("qs -c bar -d")
	hl.exec_cmd("qs -c desktop-status -d")

	-- Autostart the input methode framework fcitx5
	hl.exec_cmd("fcitx5 --replace -d")

	-- Set up DP-1 as my primary monitor in x11 sessions like some steam games
	hl.exec_cmd("xrandr --output DP-1 --primary")

	-- Autostart handy
	hl.exec_cmd("handy --start-hidden")
end)
