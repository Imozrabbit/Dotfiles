#!/bin/sh
set -eu
umask 077

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'Calendar installer requires Python 3.11+. Install python, then rerun this script.' >&2
    exit 1
fi
if [ ! -f "$root/deployment/deploy.py" ] || [ ! -f "$root/deployment/release_archive.py" ]; then
    printf '%s\n' 'Run install.sh from a complete extracted Calendar runtime release, not a standalone raw-master script.' >&2
    exit 1
fi
exec python3 -I -B "$root/deployment/deploy.py" "$@"
