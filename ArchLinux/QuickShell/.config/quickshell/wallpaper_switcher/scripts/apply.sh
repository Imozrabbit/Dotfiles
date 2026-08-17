#!/usr/bin/env bash
set -euo pipefail
# -e: exit after an unhandled command failure
# -u: treat an unset variable as an error
# pipefail: fail a pipeline if any command within it fails

JSON_PATH="${1:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/wallpapers.json}"

# Verify the JSON file exists
if [[ ! -f "$JSON_PATH" || ! -s "$JSON_PATH" ]]; then
    exit 0
fi

# Make sure jq, pgrep and pkill exist on the sytem
if ! command -v jq > /dev/null 2>&1; then
    printf 'apply.sh: jq is required\n' >&2
    exit 1 
fi
if ! command -v pgrep >/dev/null 2>&1 || ! command -v pkill >/dev/null 2>&1; then
    printf 'apply.sh: pgrep and pkill are required' >&2
    exit 1
fi

# Verify the JSON file's value & syntax
if ! jq -e '
    type == "object"
    and .version == 1
    and (.utility | type == "string")
    and (.outputs | type == "object")
    and (
        (.utility == "" and (.outputs | length == 0))
        or
        (
            (.utility == "swaybg" or .utility == "hyprpaper")
            and (.outputs | length > 0)
        )
    )
    and all(
        .outputs | to_entries[];
        (.key | length > 0)
        and (.value | type == "object")
        and (.value.wallpaper | type == "string")
        and (.value.wallpaper | length > 0)
        and (.value.mode | type == "string")
        and (.value.mode | length > 0)
    )
' "$JSON_PATH" >/dev/null; then
    printf 'apply.sh: invalid wallpaper state: %s\n' "$JSON_PATH" >&2
    exit 1
fi

# Register important variables
utility=$(jq -r '.utility' "$JSON_PATH")
monitors=()
wallpapers=()
modes=()
while IFS= read -r entry; do
    monitors+=("$(jq -r '.key' <<< "$entry")")
    wallpapers+=("$(jq -r '.value.wallpaper' <<< "$entry")")
    modes+=("$(jq -r '.value.mode' <<< "$entry")")
done < <(jq -c '.outputs | to_entries[]' "$JSON_PATH")

if [[ ${#monitors[@]} -eq 0 ]]; then
    exit 0
fi

# Check swaybg and hyprland's flag value
for index in "${!monitors[@]}"; do
    if [[ ! -f "${wallpapers[$index]}" || ! -r "${wallpapers[$index]}" ]]; then
        printf 'apply.sh: unreadable wallpaper for %s: %s\n' \
            "${monitors[$index]}" \
            "${wallpapers[$index]}" >&2
        exit 1
    fi

    case "${utility}:${modes[$index]}" in
        swaybg:stretch|swaybg:fill|swaybg:fit|swaybg:center|swaybg:tile|hyprpaper:cover|hyprpaper:tile|hyprpaper:fill|hyprpaper:contain)
            ;;
        *)
            printf 'apply.sh: invalid mode "%s" for %s on %s\n' \
                "${modes[$index]}" \
                "$utility" \
                "${monitors[$index]}" >&2
            exit 1
            ;;
    esac
done

# Stop the old swaybg instance if existed
stop_swaybg() {
    local status=0
    pkill -TERM -x -u "$UID" swaybg 2>/dev/null || status=$?

    # pkill returns 1 when no matching process exists.
    if (( status == 1 )); then
        return 0
    fi

    if (( status != 0 )); then
        printf 'apply.sh: failed to terminate swaybg; status=%s\n' "$status" >&2
        return "$status"
    fi

    # Wait up to two seconds for every old swaybg process to exit.
    for _ in {1..100}; do
        if ! pgrep -x -u "$UID" swaybg >/dev/null; then
            return 0
        fi

        sleep 0.02
    done

    printf 'apply.sh: swaybg did not terminate within two seconds\n' >&2
    return 1
}

# Apply
stop_swaybg 
case "${utility:-}" in
    swaybg)
        swaybg_arguments=()
        for index in "${!monitors[@]}"; do
            swaybg_arguments+=(
                -o "${monitors[$index]}"
                -i "${wallpapers[$index]}"
                -m "${modes[$index]}"
            )
        done
        exec swaybg "${swaybg_arguments[@]}"
    ;;

    hyprpaper)
        for index in "${!monitors[@]}"; do
            hyprctl hyprpaper reload \
            "${monitors[$index]},${wallpapers[$index]},${modes[$index]}"
        done
    ;;
    *)
        notify-send "Cannot find the wallpaper utility $utility"
    ;;
esac
