#!/bin/sh
set -eu
umask 077

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
if [ -L "$installer_state" ] || [ -L "$app_receipt" ]; then
    printf '%s\n' 'Inspect installer state symlink before continuing.' >&2
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

backup=0
skip_app=0
previous_install=0
if [ -f "$app_receipt" ] && [ "$(cat "$app_receipt")" = "$target" ] &&
   [ -f "$target/shell.qml" ] && [ -f "$target/setup-sync.sh" ] &&
   [ -f "$target/parse/convert" ] && [ -f "$target/parse/calendar-sync-helper" ]; then
    previous_install=1
fi
# Treat symlinks as installed modules, but never modify their targets.
if [ -e "$target" ] || [ -L "$target" ]; then
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
if command -v pkg-config >/dev/null 2>&1; then
    if ! pkg-config --exists libical; then missing_packages="$missing_packages libical"; fi
    if ! pkg-config --exists Qt6Core; then missing_packages="$missing_packages qt6-base"; fi
else
    # Without pkg-config, package metadata cannot show whether these libraries exist.
    missing_packages="$missing_packages libical qt6-base"
fi
if [ -n "$missing_packages" ]; then
    printf '%s\n' "Missing Arch packages:$missing_packages"
    if confirm 'Install these packages with pacman?'; then
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
    # Restore the old module after a failed move; preserve it if the target reappeared.
    if [ "$exit_code" -ne 0 ] && [ -n "$previous" ] && { [ -e "$previous" ] || [ -L "$previous" ]; }; then
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
# Extract only the calendar subtree; GitHub archives do not contain .git.
if ! tar -xzf "$staging/calendar.tar.gz" -C "$staging" "$archive_path" > "$staging/extract.log" 2>&1; then
    printf '%s\n' 'Could not extract calendar module from the archive.' >&2
    tail -n 8 "$staging/extract.log" >&2
    exit 1
fi
source_dir="$staging/$archive_path"
if [ ! -f "$source_dir/shell.qml" ] || [ ! -f "$source_dir/setup-sync.sh" ] ||
   [ ! -f "$source_dir/setup-import.sh" ] ||
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

# Move the old module only after the replacement is ready.
if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$backup" -eq 1 ]; then
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
