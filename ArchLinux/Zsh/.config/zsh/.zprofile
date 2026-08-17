# Only affect the login shell
alias hypr='start-hyprland'

# Auto log into hyprland session
if [ -z "$DISPLAY" ] && [ "${XDG_VTNR:-0}" -eq 1 ] && [ -z "$WAYLAND_DISPLAY" ]; then
  exec start-hyprland
fi
