#!/bin/sh
set -eu
umask 077

case "$#:$*" in
    0:) set -- --update ;;
    1:--confirm) set -- --confirm-update ;;
    *) printf 'Usage: %s [--confirm]\n' "$0" >&2; exit 2 ;;
esac
case "${HOME:-}" in
    /*) ;;
    *) printf 'HOME must be an absolute path\n' >&2; exit 1 ;;
esac

temp_base=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
case "$temp_base" in
    /*) ;;
    *) printf 'Temporary directory must be an absolute path\n' >&2; exit 1 ;;
esac
if [ ! -d "$temp_base" ] || [ ! -w "$temp_base" ]; then
    printf 'Temporary directory must exist and be writable: %s\n' "$temp_base" >&2
    exit 1
fi
workdir=$(mktemp -d "$temp_base/calendar-update.XXXXXXXX")
trap 'rm -rf -- "$workdir"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

curl -fsSL --output "$workdir/install.sh" \
    https://raw.githubusercontent.com/Imozrabbit/Dotfiles/master/ArchLinux/QuickShell/.config/quickshell/calendar/install.sh
sh "$workdir/install.sh" "$@"
