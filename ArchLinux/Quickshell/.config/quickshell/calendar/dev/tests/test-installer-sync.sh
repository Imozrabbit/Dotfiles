#!/bin/sh
set -eu

workdir=$(mktemp -d "$PWD/.installer-sync-test.XXXXXXXX")
cleanup() {
    result=$?
    if [ "$result" -ne 0 ] && [ -f "$workdir/output" ]; then
        printf '%s\n' 'Installer sync test failed; captured installer output:' >&2
        tail -n 15 "$workdir/output" >&2
        if [ -f "$workdir/pimsync-check.log" ]; then tail -n 10 "$workdir/pimsync-check.log" >&2; fi
    fi
    rm -rf -- "$workdir"
    exit "$result"
}
trap cleanup EXIT
mkdir -p "$workdir/bin"
cat > "$workdir/bin/pimsync" <<'PIMSYNC'
#!/bin/sh
if [ "${1:-}" = -c ] && grep -q invalid_config "$2"; then exit 1; fi
exit 0
PIMSYNC
cat > "$workdir/bin/systemctl" <<'SYSTEMCTL'
#!/bin/sh
if [ "$2" != is-enabled ] && [ "$2" != is-active ]; then printf '%s\n' "$*" >> "$SERVICE_LOG"; fi
if [ "${SERVICE_FAIL:-0}" = 1 ] && [ "$2" = enable ]; then exit 1; fi
if [ "${SERVICE_INACTIVE:-0}" = 1 ] && [ "$2" = is-active ]; then exit 1; fi
exit 0
SYSTEMCTL
chmod +x "$workdir/bin/pimsync" "$workdir/bin/systemctl"
export PATH="$workdir/bin:$PATH" SERVICE_LOG="$workdir/service.log"

export HOME="$workdir/new-home" XDG_DATA_HOME="$workdir/new-home/data" XDG_STATE_HOME="$workdir/new-home/state"
export XDG_CONFIG_HOME="$HOME/.config"
printf '\n\n\nhttps://example.org/university.ics\nhttps://example.org/caldav/\nstudent\nprivate-password\n' |
    sh ./setup-sync.sh > "$workdir/output" 2>&1
config="$HOME/.config/pimsync/pimsync.conf"
test -f "$config"
if [ -x /usr/bin/pimsync ]; then
    if ! timeout 5 /usr/bin/pimsync -c "$config" list pairs > "$workdir/pimsync-check.log" 2>&1; then
        printf '%s\n' 'Generated pimsync configuration failed validation.' >&2
        exit 1
    fi
fi
grep -q 'collection edt_unistra' "$config"
grep -q 'collection holidays_fr' "$config"
grep -q 'collection personal' "$config"
test -d "$XDG_STATE_HOME/pimsync/status"
test -d "$XDG_DATA_HOME/calendars/edt_unistra"
test -d "$XDG_DATA_HOME/calendars/holidays_fr"
test -d "$XDG_DATA_HOME/calendars/personal"
test -f "$XDG_DATA_HOME/calendars/profiles.json"
grep -q '"type":"synced"' "$XDG_DATA_HOME/calendars/profiles.json"
secret="$HOME/.config/pimsync/secrets/radicale3-password"
test "$(stat -c %a "$secret")" = 600
test "$(cat "$secret")" = private-password
if grep -q private-password "$workdir/output" "$config"; then exit 1; fi
grep -q '^--user enable --now pimsync.service$' "$SERVICE_LOG"
grep -Fq "Environment=\"XDG_CONFIG_HOME=$XDG_CONFIG_HOME\"" "$HOME/.config/systemd/user/pimsync.service"
systemd-analyze --user verify "$HOME/.config/systemd/user/pimsync.service" > "$workdir/systemd-check.log" 2>&1 || {
    tail -n 10 "$workdir/systemd-check.log" >&2
    exit 1
}

printf 'synced event\n' > "$XDG_DATA_HOME/calendars/personal/remote.ics"
: > "$SERVICE_LOG"
sh ./setup-sync.sh < /dev/null > "$workdir/output" 2>&1
test "$(cat "$secret")" = private-password
test ! -s "$SERVICE_LOG"
grep -q 'already configured' "$workdir/output"

: > "$SERVICE_LOG"
SERVICE_INACTIVE=1 sh ./setup-sync.sh < /dev/null > "$workdir/output" 2>&1
grep -q '^--user enable --now pimsync.service$' "$SERVICE_LOG"

cp "$config" "$workdir/valid-pimsync.conf"
printf 'invalid_config\n' > "$config"
if sh ./setup-sync.sh < /dev/null > "$workdir/output" 2>&1; then exit 1; fi
cp "$workdir/valid-pimsync.conf" "$config"
cp "$XDG_STATE_HOME/quickshell-calendar/installer/sources" "$workdir/valid-sources"
printf '1 1 invalid\n' > "$XDG_STATE_HOME/quickshell-calendar/installer/sources"
if sh ./setup-sync.sh < /dev/null > "$workdir/output" 2>&1; then exit 1; fi
cp "$workdir/valid-sources" "$XDG_STATE_HOME/quickshell-calendar/installer/sources"

export HOME="$workdir/occupied-home" XDG_DATA_HOME="$workdir/occupied-home/data" XDG_STATE_HOME="$workdir/occupied-home/state"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$XDG_DATA_HOME/calendars/holidays_fr"
printf 'user data\n' > "$XDG_DATA_HOME/calendars/holidays_fr/event.ics"
if printf '\n\n\n' | sh ./setup-sync.sh > "$workdir/output" 2>&1; then exit 1; fi
grep -q "$XDG_DATA_HOME/calendars" "$workdir/output"
test ! -e "$HOME/.config/pimsync/pimsync.conf"

export HOME="$workdir/retry-home" XDG_DATA_HOME="$workdir/retry-home/data" XDG_STATE_HOME="$workdir/retry-home/state"
export XDG_CONFIG_HOME="$HOME/.config"
if printf 'n\ny\nn\n' | SERVICE_FAIL=1 sh ./setup-sync.sh > "$workdir/output" 2>&1; then exit 1; fi
config="$HOME/.config/pimsync/pimsync.conf"
test -f "$config"
printf 'downloaded event\n' > "$XDG_DATA_HOME/calendars/holidays_fr/event.ics"
: > "$SERVICE_LOG"
sh ./setup-sync.sh < /dev/null > "$workdir/output" 2>&1
test -f "$HOME/.config/systemd/user/pimsync.service"
grep -q '^--user enable --now pimsync.service$' "$SERVICE_LOG"
if grep -q 'storage unistra\|storage radicale' "$config"; then exit 1; fi
grep -q '"type":"local"' "$XDG_DATA_HOME/calendars/profiles.json"

export HOME="$workdir/unsafe-home" XDG_DATA_HOME="$workdir/unsafe-home/data" XDG_STATE_HOME="$workdir/unsafe-home/state"
export XDG_CONFIG_HOME="$HOME/.config"
if printf 'y\nn\nn\nhttps://example.org/a b\n' | sh ./setup-sync.sh > "$workdir/output" 2>&1; then exit 1; fi
test ! -e "$HOME/.config/pimsync/pimsync.conf"

printf 'Installer sync tests passed\n'
