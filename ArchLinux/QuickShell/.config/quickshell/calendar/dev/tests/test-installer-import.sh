#!/bin/sh
set -eu

workdir=$(mktemp -d "$PWD/.installer-import-test.XXXXXXXX")
cleanup() {
    result=$?
    if [ "$result" -ne 0 ] && [ -f "$workdir/output" ]; then
        printf '%s\n' 'Installer import test failed; captured output:' >&2
        tail -n 15 "$workdir/output" >&2
    fi
    rm -rf -- "$workdir"
    exit "$result"
}
trap cleanup EXIT
mkdir -p "$workdir/bin"
cat > "$workdir/bin/systemctl" <<'SYSTEMCTL'
#!/bin/sh
if [ "$2" = is-enabled ] && [ "${IMPORT_SERVICE_DISABLED:-0}" = 1 ] &&
   [ "$4" = quickshell-calendar-import.service ]; then exit 1; fi
case "$2" in
    is-enabled|is-active) exit 0 ;;
esac
printf '%s\n' "$*" >> "$SERVICE_LOG"
if [ "${IMPORT_FAIL:-0}" = 1 ] && [ "$2" = enable ] &&
   [ "$4" = quickshell-calendar-import.service ]; then exit 1; fi
SYSTEMCTL
chmod +x "$workdir/bin/systemctl"
export PATH="$workdir/bin:$PATH" SERVICE_LOG="$workdir/service.log"
export HOME="$workdir/home" XDG_CONFIG_HOME="$workdir/home/.config"
export XDG_DATA_HOME="$workdir/home/data" XDG_STATE_HOME="$workdir/home/state"
mkdir -p "$XDG_STATE_HOME/quickshell-calendar/installer" "$HOME/.config/quickshell/calendar/parse"
printf '#!/bin/sh\nexit 0\n' > "$HOME/.config/quickshell/calendar/parse/convert"
cp "$HOME/.config/quickshell/calendar/parse/convert" "$HOME/.config/quickshell/calendar/parse/calendar-sync-helper"
chmod +x "$HOME/.config/quickshell/calendar/parse/convert" "$HOME/.config/quickshell/calendar/parse/calendar-sync-helper"
printf '1 1 1\n' > "$XDG_STATE_HOME/quickshell-calendar/installer/sources"
sh ./setup-import.sh > "$workdir/output" 2>&1
unit_dir="$XDG_CONFIG_HOME/systemd/user"
test -f "$unit_dir/quickshell-calendar-import.service"
test -f "$unit_dir/quickshell-calendar-import.path"
grep -Fxq '[Install]' "$unit_dir/quickshell-calendar-import.service"
grep -Fxq 'WantedBy=default.target' "$unit_dir/quickshell-calendar-import.service"
systemd-analyze --user verify "$unit_dir/quickshell-calendar-import.service" "$unit_dir/quickshell-calendar-import.path" > "$workdir/systemd-check.log" 2>&1 || {
    tail -n 10 "$workdir/systemd-check.log" >&2
    exit 1
}
grep -Fq "$HOME/.config/quickshell/calendar/parse/convert" "$unit_dir/quickshell-calendar-import.service"
grep -Fq 'holidays_fr.json" holidays_fr' "$unit_dir/quickshell-calendar-import.service"
grep -Fq 'personal.sync.json" personal' "$unit_dir/quickshell-calendar-import.service"
grep -Fq "$XDG_DATA_HOME/calendars/edt_unistra" "$unit_dir/quickshell-calendar-import.path"
grep -Fq "$XDG_DATA_HOME/calendars/holidays_fr" "$unit_dir/quickshell-calendar-import.path"
grep -Fq "$XDG_DATA_HOME/calendars/personal" "$unit_dir/quickshell-calendar-import.path"
grep -q '^--user enable --now quickshell-calendar-import.path$' "$SERVICE_LOG"
grep -q '^--user enable --now quickshell-calendar-import.service$' "$SERVICE_LOG"

: > "$SERVICE_LOG"
sh ./setup-import.sh > "$workdir/output" 2>&1
test ! -s "$SERVICE_LOG"

: > "$SERVICE_LOG"
IMPORT_SERVICE_DISABLED=1 sh ./setup-import.sh > "$workdir/output" 2>&1
grep -q '^--user enable --now quickshell-calendar-import.service$' "$SERVICE_LOG"

printf 'stale unit\n' > "$unit_dir/quickshell-calendar-import.service"
: > "$SERVICE_LOG"
printf 'y\nn\n' | sh ./setup-import.sh > "$workdir/output" 2>&1
grep -q '^--user daemon-reload$' "$SERVICE_LOG"
grep -q '^--user enable --now quickshell-calendar-import.service$' "$SERVICE_LOG"

export HOME="$workdir/existing-home" XDG_CONFIG_HOME="$workdir/existing-home/.config"
export XDG_DATA_HOME="$workdir/existing-home/data" XDG_STATE_HOME="$workdir/existing-home/state"
mkdir -p "$XDG_STATE_HOME/quickshell-calendar/installer" "$XDG_CONFIG_HOME/systemd/user"
printf '0 1 0\n' > "$XDG_STATE_HOME/quickshell-calendar/installer/sources"
printf 'original unit\n' > "$XDG_CONFIG_HOME/systemd/user/quickshell-calendar-import.service"
if printf 'n\n' | sh ./setup-import.sh > "$workdir/output" 2>&1; then exit 1; fi
grep -q 'original unit' "$XDG_CONFIG_HOME/systemd/user/quickshell-calendar-import.service"

printf 'y\ny\n' | sh ./setup-import.sh > "$workdir/output" 2>&1
set -- "$XDG_CONFIG_HOME/systemd/user"/quickshell-calendar-import.service.backup-*
test "$#" -eq 1
grep -q 'original unit' "$1"
if grep -q 'edt_unistra\|personal.sync.json' "$XDG_CONFIG_HOME/systemd/user/quickshell-calendar-import.service"; then exit 1; fi

export HOME="$workdir/retry-home" XDG_CONFIG_HOME="$workdir/retry-home/.config"
export XDG_DATA_HOME="$workdir/retry-home/data" XDG_STATE_HOME="$workdir/retry-home/state"
mkdir -p "$XDG_STATE_HOME/quickshell-calendar/installer"
printf '0 1 0\n' > "$XDG_STATE_HOME/quickshell-calendar/installer/sources"
if IMPORT_FAIL=1 sh ./setup-import.sh > "$workdir/output" 2>&1; then exit 1; fi
test -f "$XDG_CONFIG_HOME/systemd/user/quickshell-calendar-import.path"
test ! -e "$XDG_STATE_HOME/quickshell-calendar/installer/import-done"
: > "$SERVICE_LOG"
sh ./setup-import.sh < /dev/null > "$workdir/output" 2>&1
grep -q '^--user enable --now quickshell-calendar-import.service$' "$SERVICE_LOG"
test -f "$XDG_STATE_HOME/quickshell-calendar/installer/import-done"

printf 'Installer import tests passed\n'
