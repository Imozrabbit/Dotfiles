#!/bin/sh
set -eu

action=${1-}
case "$action" in
    poweroff) prompt="Confirm to Shutdown" ;;
    reboot) prompt="Confirm to reboot" ;;
    logout) prompt="Confirm to Logout" ;;
    suspend) prompt="Confirm to Suspend" ;;
    hibernate) prompt="Hibernate to Disque" ;;
    *) printf 'Unknown power action: %s\n' "$action" >&2; exit 2 ;;
esac

theme="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/themes/confirmation-box.rasi"
if ! command -v rofi >/dev/null 2>&1; then
    printf 'Power confirmation requires rofi\n' >&2
    exit 127
fi
if [ ! -r "$theme" ]; then
    printf 'Power confirmation theme is unreadable: %s\n' "$theme" >&2
    exit 1
fi

if [ -n "${COMMAND_CENTER_PID:-}" ]; then
    closed=$(quickshell ipc --pid "$COMMAND_CENTER_PID" call command-center close)
    case "$closed" in
        true|false) ;;
        *) printf 'Could not close command-center before confirmation\n' >&2; exit 1 ;;
    esac
fi

set -- -dmenu -normal-window -window-title confirmbox -mesg "$prompt" -theme "$theme"
[ "$action" = reboot ] || set -- -x11 "$@"
status=0
choice=$(printf '%s\n' No Yes | rofi "$@") || status=$?
if [ "$status" -ne 0 ]; then
    [ "$status" -eq 1 ] && exit 0
    printf 'Power confirmation failed (exit %s)\n' "$status" >&2
    exit "$status"
fi
[ "$choice" = Yes ] || exit 0

case "$action" in
    poweroff) exec hyprctl dispatch "hl.dsp.exec_cmd('hyprshutdown -t Shutting_Down... --post-cmd poweroff')" ;;
    reboot) exec hyprctl dispatch "hl.dsp.exec_cmd('hyprshutdown -t Restarting... --post-cmd reboot')" ;;
    logout)
        if command -v hyprshutdown >/dev/null 2>&1; then
            exec hyprshutdown -t "Logging out..."
        else
            exec hyprctl dispatch exit
        fi
        ;;
    suspend) exec systemctl suspend ;;
    hibernate) exec systemctl hibernate ;;
esac
