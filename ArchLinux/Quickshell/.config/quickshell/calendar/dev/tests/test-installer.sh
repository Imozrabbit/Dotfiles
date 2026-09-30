#!/bin/sh
set -eu

workdir=$(mktemp -d "$PWD/.installer-test.XXXXXXXX")
trap 'rm -rf -- "$workdir"' EXIT
source="$workdir/source/Dotfiles-master/ArchLinux/QuickShell/.config/quickshell/calendar"
mkdir -p "$source/parse" "$workdir/bin" "$workdir/tmp"
printf 'ShellRoot {}\n' > "$source/shell.qml"
printf 'all:\n\t@true\n' > "$source/parse/Makefile"
cat > "$source/setup-sync.sh" <<'SYNC'
#!/bin/sh
if [ "${SYNC_FAIL:-0}" = 1 ]; then exit 3; fi
printf 'sync setup invoked\n' >> "$SYNC_LOG"
SYNC
cat > "$source/setup-import.sh" <<'IMPORT'
#!/bin/sh
printf 'import setup invoked\n' >> "$IMPORT_LOG"
IMPORT
tar -czf "$workdir/archive.tar.gz" -C "$workdir/source" Dotfiles-master

cat > "$workdir/bin/curl" <<'CURL'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) output=$2; shift 2 ;;
        *) shift ;;
    esac
done
cp "$ARCHIVE_FIXTURE" "$output"
printf 'raw curl output\n'
CURL
cat > "$workdir/bin/make" <<'MAKE'
#!/bin/sh
printf 'raw make output\n'
while [ "$#" -gt 0 ]; do
    case "$1" in
        -C) directory=$2; shift 2 ;;
        *) shift ;;
    esac
done
if [ "${MAKE_FAIL:-0}" = 1 ]; then exit 2; fi
touch "$directory/convert" "$directory/calendar-sync-helper"
MAKE
cat > "$workdir/bin/mv" <<'MOVE'
#!/bin/sh
if [ "${FAIL_INSTALL_MOVE:-0}" = 1 ]; then
    case "$2" in
        */Dotfiles-master/*)
            mkdir -p -- "$3"
            exit 1
            ;;
    esac
fi
exec /usr/bin/mv "$@"
MOVE
chmod +x "$workdir/bin/curl" "$workdir/bin/make" "$workdir/bin/mv"
export PATH="$workdir/bin:$PATH" ARCHIVE_FIXTURE="$workdir/archive.tar.gz" TMPDIR="$workdir/tmp"
export HOME="$workdir/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/data" XDG_STATE_HOME="$HOME/state"
export SYNC_LOG="$workdir/sync.log"
export IMPORT_LOG="$workdir/import.log"

sh ./install.sh > "$workdir/output" 2>&1
installed="$HOME/.config/quickshell/calendar"
test -f "$installed/parse/convert"
test -f "$installed/parse/calendar-sync-helper"
test ! -e "$installed/.git"
test -s "$IMPORT_LOG"
grep -q 'Downloading calendar' "$workdir/output"
grep -q 'Building native helpers' "$workdir/output"
if grep -q 'raw curl output\|raw make output' "$workdir/output"; then exit 1; fi

printf 'existing install\n' > "$installed/user-note"
printf 'n\n' | sh ./install.sh > "$workdir/output" 2>&1
test -f "$installed/user-note"
grep -q 'Skipping already installed calendar module' "$workdir/output"

printf 'y\ny\n' | sh ./install.sh > "$workdir/output" 2>&1
test ! -e "$installed/user-note"
set -- "$HOME/.config/quickshell"/calendar.backup-*
test "$#" -eq 1
test -f "$1/user-note"

printf 'existing again\n' > "$installed/user-note"
if printf 'y\nn\n' | MAKE_FAIL=1 sh ./install.sh > "$workdir/output" 2>&1; then exit 1; fi
test -f "$installed/user-note"

if printf 'y\nn\n' | FAIL_INSTALL_MOVE=1 sh ./install.sh > "$workdir/output" 2>&1; then exit 1; fi
set -- "$HOME/.config/quickshell"/calendar.recovery-*
test "$#" -eq 1
test -f "$1/user-note"
rm -r -- "$installed"
mv -- "$1" "$installed"

printf 'y\nn\n' | sh ./install.sh > "$workdir/output" 2>&1
test ! -e "$installed/user-note"
set -- "$HOME/.config/quickshell"/calendar.backup-*
test "$#" -eq 1

export HOME="$workdir/link-home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/data" XDG_STATE_HOME="$HOME/state"
mkdir -p "$HOME/.config/quickshell" "$workdir/existing-source"
printf 'original checkout\n' > "$workdir/existing-source/user-note"
ln -s "$workdir/existing-source" "$HOME/.config/quickshell/calendar"
printf 'y\nn\n' | sh ./install.sh > "$workdir/output" 2>&1
test ! -L "$HOME/.config/quickshell/calendar"
test -f "$workdir/existing-source/user-note"

export HOME="$workdir/retry-home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/data" XDG_STATE_HOME="$HOME/state"
if SYNC_FAIL=1 sh ./install.sh > "$workdir/output" 2>&1; then exit 1; fi
test -f "$HOME/.config/quickshell/calendar/parse/convert"
test -f "$XDG_STATE_HOME/quickshell-calendar/installer/app-path"
printf 'n\n' | sh ./install.sh > "$workdir/output" 2>&1
grep -q 'Skipping already installed calendar module' "$workdir/output"
test -f "$HOME/.config/quickshell/calendar/parse/convert"

# Exercise the real sync stage through the downloaded module after a partial install.
cp ./setup-sync.sh "$source/setup-sync.sh"
tar -czf "$workdir/archive.tar.gz" -C "$workdir/source" Dotfiles-master
cat > "$workdir/bin/pimsync" <<'PIMSYNC'
#!/bin/sh
exit 0
PIMSYNC
cat > "$workdir/bin/systemctl" <<'SYSTEMCTL'
#!/bin/sh
if [ "${SERVICE_FAIL:-0}" = 1 ] && [ "$2" = enable ]; then exit 1; fi
exit 0
SYSTEMCTL
chmod +x "$workdir/bin/pimsync" "$workdir/bin/systemctl"
export HOME="$workdir/full-home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/data" XDG_STATE_HOME="$HOME/state"
if printf 'n\ny\nn\n' | SERVICE_FAIL=1 sh ./install.sh > "$workdir/output" 2>&1; then exit 1; fi
test -f "$HOME/.config/quickshell/calendar/setup-sync.sh"
test -f "$HOME/.config/pimsync/pimsync.conf"
printf 'calendar data\n' > "$XDG_DATA_HOME/calendars/holidays_fr/event.ics"
printf 'n\n' | sh ./install.sh > "$workdir/output" 2>&1
grep -q 'Skipping already installed calendar module' "$workdir/output"
test -f "$XDG_STATE_HOME/quickshell-calendar/installer/service-done"
test -s "$IMPORT_LOG"

printf 'Installer bootstrap tests passed\n'
