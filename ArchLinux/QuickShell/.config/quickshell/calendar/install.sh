#!/bin/sh
set -eu
umask 077

mode=install
case "$#" in
    0) ;;
    1) case "$1" in --update) mode=update ;; --confirm-update) mode=confirm-update ;; *) printf '%s\n' 'Usage: install.sh [--update|--confirm-update]' >&2; exit 2 ;; esac ;;
    *) printf '%s\n' 'Usage: install.sh [--update|--confirm-update]' >&2; exit 2 ;;
esac

# -----------------------------------------------------------------------------------------
# Stage 1: Download, build, and install the calendar module
# -----------------------------------------------------------------------------------------
if [ -z "${HOME:-}" ]; then
    printf '%s\n' 'HOME is required to install calendar.' >&2
    exit 1
fi
case "$HOME" in
    /*) ;;
    *) printf '%s\n' 'HOME must be an absolute path.' >&2; exit 1 ;;
esac

config_dir="$HOME/.config/quickshell"
target="$config_dir/calendar"
installer_state="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-calendar/installer"
app_receipt="$installer_state/app-path"
for path in "$(dirname "$installer_state")" "$installer_state"; do
    if [ -L "$path" ] || { [ -e "$path" ] && [ ! -d "$path" ]; }; then
        printf '%s\n' "Inspect installer state directory $path before continuing." >&2
        exit 1
    fi
done
for receipt in "$app_receipt" "$installer_state/update-previous" "$installer_state/sources" "$installer_state/import-done"; do
    if [ -L "$receipt" ] || { [ -e "$receipt" ] && [ ! -f "$receipt" ]; }; then
        printf '%s\n' "Inspect installer receipt $receipt before continuing." >&2
        exit 1
    fi
done
if [ "$mode" != confirm-update ] && [ -e "$installer_state/update-previous" ]; then
    printf '%s\n' 'Previous update awaits confirmation or recovery; resolve it before replacing calendar again.' >&2
    exit 1
fi
archive_url=https://codeload.github.com/Imozrabbit/Dotfiles/tar.gz/refs/heads/master
archive_path=Dotfiles-master/ArchLinux/QuickShell/.config/quickshell/calendar

confirm() {
    printf '%s [y/N] ' "$1"
    IFS= read -r answer || return 1
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

if [ "$mode" != install ]; then
    for path in "$HOME" "${XDG_CONFIG_HOME:-$HOME/.config}" "${XDG_DATA_HOME:-$HOME/.local/share}" "${XDG_STATE_HOME:-$HOME/.local/state}"; do
        case "$path" in /*) ;; *) printf '%s\n' "Expected absolute path: $path" >&2; exit 1 ;; esac
        if printf '%s' "$path" | LC_ALL=C grep -Eq '[[:cntrl:]"\\%]'; then
            printf '%s\n' 'Calendar update paths cannot contain control characters, quotes, backslashes, or systemd specifiers.' >&2
            exit 1
        fi
    done
    if [ -L "$config_dir" ] || [ -L "$target" ] || [ -L "$target/shell.qml" ] || [ ! -f "$target/shell.qml" ] ||
       [ -e "$target/.git" ] || { command -v git >/dev/null 2>&1 && git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; }; then
        printf '%s\n' 'Update requires an existing standalone calendar, not a symlink or Git checkout.' >&2
        exit 1
    fi
    mkdir -p -- "$installer_state"
    exec 8<"$installer_state"
    flock -n 8 || { printf '%s\n' 'Another calendar update is running.' >&2; exit 1; }
    # Another invocation may have completed unconfirmed after the early precheck.
    if [ "$mode" != confirm-update ] && { [ -e "$installer_state/update-previous" ] || [ -L "$installer_state/update-previous" ]; }; then
        printf '%s\n' 'Previous update awaits confirmation or recovery; resolve it before replacing calendar again.' >&2
        exit 1
    fi
    if [ "$mode" = confirm-update ]; then
        if [ ! -f "$target/update-runtime.sh" ]; then printf '%s\n' 'Installed update cleanup helper is missing.' >&2; exit 1; fi
        . "$target/update-runtime.sh"
        if confirm 'Calendar works correctly? Permanently remove previous version and rollback files?'; then update_remove_previous; fi
        exit 0
    fi
fi

backup=0
skip_app=0
previous_install=0
if [ -f "$app_receipt" ] && [ "$(cat "$app_receipt")" = "$target" ] &&
   [ -f "$target/shell.qml" ] && [ -f "$target/setup-sync.sh" ] &&
   [ -f "$target/parse/convert" ] && [ -f "$target/parse/calendar-sync-helper" ]; then
    previous_install=1
fi
# Treat symlinks as installed modules, but never modify their targets.
if [ "$mode" = install ] && { [ -e "$target" ] || [ -L "$target" ]; }; then
    if ! confirm 'Calendar module already exists. Replace it?'; then
        if [ "$previous_install" -eq 0 ]; then
            printf '%s\n' 'Installation stopped; existing calendar was not installed by this script.'
            exit 1
        fi
        skip_app=1
        printf '%s\n' 'Skipping already installed calendar module.'
    fi
    if [ "$skip_app" -eq 0 ] && confirm 'Keep a timestamped backup of the existing module?'; then
        backup=1
    fi
fi

if [ "$skip_app" -eq 0 ]; then
# Check build requirements before downloading or replacing any calendar files.
missing_packages=''
require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        missing_packages="$missing_packages $2"
    fi
}
require_command curl curl
require_command tar tar
require_command make make
require_command g++ gcc
require_command pkg-config pkgconf
require_command quickshell quickshell
require_command systemctl systemd
if [ "$mode" = update ]; then
    require_command jq jq
    require_command flock util-linux
    require_command busctl systemd
fi
if command -v pkg-config >/dev/null 2>&1; then
    if ! pkg-config --exists libical; then missing_packages="$missing_packages libical"; fi
    if ! pkg-config --exists Qt6Core; then missing_packages="$missing_packages qt6-base"; fi
else
    # Without pkg-config, package metadata cannot show whether these libraries exist.
    missing_packages="$missing_packages libical qt6-base"
fi
if [ -n "$missing_packages" ]; then
    printf '%s\n' "Missing Arch packages:$missing_packages"
    if [ "$mode" = install ] && confirm 'Install these packages with pacman?'; then
        # Package names contain no spaces; split list into pacman arguments.
        sudo pacman -S --needed $missing_packages
    else
        printf '%s\n' "Install them manually with: sudo pacman -S --needed$missing_packages" >&2
        exit 1
    fi
fi

mkdir -p -- "$config_dir"
# Stage on the destination filesystem so activation is a local move.
staging=$(mktemp -d "$config_dir/.calendar-install.XXXXXXXX")
previous=''
cleanup() {
    exit_code=$?
    trap - EXIT
    if [ "$mode" = update ] && command -v update_cleanup >/dev/null 2>&1; then
        update_cleanup
    fi
    # Restore the old module after a failed move; preserve it if the target reappeared.
    if [ "$mode" = install ] && [ "$exit_code" -ne 0 ] && [ -n "$previous" ] && { [ -e "$previous" ] || [ -L "$previous" ]; }; then
        if [ ! -e "$target" ] && [ ! -L "$target" ]; then
            printf '%s\n' 'Restoring previous calendar module.' >&2
            mv -- "$previous" "$target" || exit_code=1
        elif [ "$backup" -eq 0 ]; then
            recovery="$config_dir/calendar.recovery-$(date +%Y%m%d-%H%M%S)-$$"
            if mv -- "$previous" "$recovery"; then
                printf '%s\n' "Installation failed; previous module saved at $recovery." >&2
            else
                printf '%s\n' "Installation failed; previous module remains at $previous." >&2
                exit "$exit_code"
            fi
        fi
    fi
    rm -rf -- "$staging"
    exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s\n' 'Downloading calendar sources from GitHub...'
if ! curl -fsSL "$archive_url" -o "$staging/calendar.tar.gz" > "$staging/download.log" 2>&1; then
    printf '%s\n' 'Could not download calendar sources from GitHub.' >&2
    tail -n 8 "$staging/download.log" >&2
    exit 1
fi
printf '%s\n' 'Extracting calendar module...'
# Extract a source-only client module, even from an older archive with dev debris.
if ! tar -xzf "$staging/calendar.tar.gz" -C "$staging" \
    --exclude="$archive_path/dev" \
    --exclude="$archive_path/parse/test" \
    --exclude="$archive_path/parse/.clangd" \
    --exclude="$archive_path/parse/output" \
    --exclude="$archive_path/parse/convert" \
    --exclude="$archive_path/parse/calendar-sync-helper" \
    --exclude='AGENTS.md' --exclude='.git' --exclude='.cache' --exclude='__pycache__' \
    --exclude='*.tar.gz' --exclude='*.log' --exclude='*.bak' --exclude='*.backup*' \
    --exclude='*.pyc' --exclude='*.qmlc' --exclude='*.jsc' \
    --exclude='.installer*-test.*' --exclude='.updater-test.*' --exclude='.update-bootstrap-test.*' \
    "$archive_path" > "$staging/extract.log" 2>&1; then
    printf '%s\n' 'Could not extract calendar module from the archive.' >&2
    tail -n 8 "$staging/extract.log" >&2
    exit 1
fi
source_dir="$staging/$archive_path"
if [ ! -f "$source_dir/shell.qml" ] || [ ! -f "$source_dir/setup-sync.sh" ] ||
    [ ! -f "$source_dir/setup-import.sh" ] ||
    [ ! -f "$source_dir/parse/conflict-broker.sh" ] || [ ! -x "$source_dir/parse/conflict-broker.sh" ] ||
   [ ! -f "$source_dir/parse/Makefile" ] || [ -e "$source_dir/.git" ]; then
    printf '%s\n' 'Downloaded archive does not contain a standalone calendar module.' >&2
    exit 1
fi

# Build inside staging so compiler failures leave the active module untouched.
printf '%s\n' 'Building native helpers...'
if ! make -s -C "$source_dir/parse" clean convert calendar-sync-helper > "$staging/build.log" 2>&1; then
    printf '%s\n' 'Could not build native calendar helpers.' >&2
    tail -n 12 "$staging/build.log" >&2
    exit 1
fi

# Object files are build debris, not part of the installed runtime.
if [ -d "$source_dir/parse/output" ]; then
    find "$source_dir/parse/output" -maxdepth 1 -type f -name '*.o' -delete
fi
if [ "$mode" = update ]; then
    if [ ! -f "$source_dir/update-runtime.sh" ] || [ ! -f "$source_dir/update.sh" ] ||
       [ ! -x "$source_dir/parse/convert" ] || [ ! -x "$source_dir/parse/calendar-sync-helper" ]; then
        printf '%s\n' 'Downloaded module lacks update support or executable helpers.' >&2
        exit 1
    fi
    . "$source_dir/update-runtime.sh"
    update_prepare
    update_pause
fi

# Move the old module only after the replacement is ready.
if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$mode" = update ]; then
        printf '%s\n' "Keeping temporary rollback copy at $update_rollback..."
    elif [ "$backup" -eq 1 ]; then
        previous="$config_dir/calendar.backup-$(date +%Y%m%d-%H%M%S)-$$"
        printf '%s\n' "Saving existing calendar module to $previous..."
    else
        previous="$staging/previous-calendar"
        printf '%s\n' 'Replacing existing calendar module without a retained backup...'
    fi
    mv -- "$target" "$previous"
fi

printf '%s\n' "Installing calendar module at $target..."
mv -- "$source_dir" "$target"
if [ "$mode" = update ]; then
    update_finish
    exit 0
fi
install -d -m 700 -- "$installer_state"
printf '%s\n' "$target" > "$app_receipt"
printf '%s\n' 'Calendar module installed; native helpers built locally.'
fi

# -----------------------------------------------------------------------------------------
# Stage 2: Configure pimsync, source directories, and user service
# -----------------------------------------------------------------------------------------
sh "$target/setup-sync.sh"

# -----------------------------------------------------------------------------------------
# Stage 3: Install the calendar import service and directory watcher
# -----------------------------------------------------------------------------------------
sh "$target/setup-import.sh"
