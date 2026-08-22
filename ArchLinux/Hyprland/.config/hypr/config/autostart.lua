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
	hl.exec_cmd("qs -p ~/.config/quickshell/level-osd/shell.qml")
	hl.exec_cmd("qs -p ~/.config/quickshell/alt-tab_view/shell.qml")
	hl.exec_cmd("qs -p ~/.config/quickshell/bar/shell.qml")
	hl.exec_cmd("qs -n -p ~/.config/quickshell/lockscreen")

	-- Autostart the input methode framework fcitx5
	hl.exec_cmd("fcitx5 --replace -d")
end)
