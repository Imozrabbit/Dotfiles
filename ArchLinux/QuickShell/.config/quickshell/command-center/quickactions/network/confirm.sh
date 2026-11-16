#!/bin/sh
set -eu

theme="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/themes/confirmation-box.rasi"
for tool in nmcli rofi; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Network confirmation requires %s\n' "$tool" >&2
        exit 127
    fi
done
if [ ! -r "$theme" ]; then
    printf 'Network confirmation theme is unreadable: %s\n' "$theme" >&2
    exit 1
fi

# Scope C locale to nmcli; Qt IPC locale warnings would corrupt its boolean reply.
networking=$(LC_ALL=C nmcli -t -f NETWORKING general status)
case "$networking" in
    enabled) target=off; prompt="Confirm to Disable Networking" ;;
    disabled) target=on; prompt="Confirm to Enable Networking" ;;
    *) printf 'NetworkManager networking state is unavailable\n' >&2; exit 1 ;;
esac

if [ -n "${COMMAND_CENTER_PID:-}" ]; then
    closed=$(quickshell ipc --pid "$COMMAND_CENTER_PID" call command-center close)
    case "$closed" in
        true|false) ;;
        *) printf 'Could not close command-center before confirmation\n' >&2; exit 1 ;;
    esac
fi

status=0
choice=$(printf '%s\n' No Yes | rofi -x11 -dmenu -normal-window -window-title confirmbox -mesg "$prompt" -theme "$theme") || status=$?
if [ "$status" -ne 0 ]; then
    [ "$status" -eq 1 ] && exit 0
    printf 'Network confirmation failed (exit %s)\n' "$status" >&2
    exit "$status"
fi
[ "$choice" = Yes ] || exit 0

# Apply the confirmed target even if another client changed state while Rofi was open.
LC_ALL=C exec nmcli networking "$target"
