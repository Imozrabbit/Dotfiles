#!/bin/bash
killall -9 waybar
sleep 0.2

waybar -c "$HOME/.config/waybar/config_DP1.jsonc" -s "$HOME/.config/waybar/style_DP1.css" &
waybar -c "$HOME/.config/waybar/config_DP2.jsonc" -s "$HOME/.config/waybar/style_DP2.css" &
