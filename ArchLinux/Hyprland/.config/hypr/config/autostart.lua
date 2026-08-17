hl.on("hyprland.start", function()
	-- Status bar
	hl.exec_cmd("waybar -c /home/Zrabbit/.config/waybar/config_DP1.jsonc -s /home/Zrabbit/.config/waybar/style_DP1.css")
	hl.exec_cmd("waybar -c /home/Zrabbit/.config/waybar/config_DP2.jsonc -s /home/Zrabbit/.config/waybar/style_DP2.css")
	hl.exec_cmd("/home/Zrabbit/.config/hypr/scripts/waybar_auto_hide --side bottom --always-hidden")

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
	hl.exec_cmd("qs -p ~/.config/quickshell/volume-osd/shell.qml")
	hl.exec_cmd("qs -p ~/.config/quickshell/system-osd/shell.qml")
	hl.exec_cmd("qs -p ~/.config/quickshell/clock/shell.qml")
	hl.exec_cmd("qs -p ~/.config/quickshell/ram-osd/shell.qml")
	hl.exec_cmd("qs -p ~/.config/quickshell/weather/shell.qml")
	hl.exec_cmd("qs -p ~/.config/quickshell/alt-tab_view/shell.qml")

	-- Autostart the input methode framework fcitx5
	hl.exec_cmd("fcitx5 --replace -d")
end)
