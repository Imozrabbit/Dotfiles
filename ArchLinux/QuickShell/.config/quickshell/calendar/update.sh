#!/bin/sh
set -eu
umask 077

case "$#" in
    0) set -- --update ;;
    1) case "$1" in
        --confirm) set -- --confirm-update ;;
        --rollback) set -- --rollback ;;
        *) printf 'Usage: %s [--confirm|--rollback] or [--archive PATH]\n' "$0" >&2; exit 2 ;;
    esac ;;
    2) if [ "$1" = --archive ] && [ -n "$2" ]; then set -- --update --archive "$2";
       else printf 'Usage: %s [--confirm|--rollback] or [--archive PATH]\n' "$0" >&2; exit 2; fi ;;
    *) printf 'Usage: %s [--confirm|--rollback] or [--archive PATH]\n' "$0" >&2; exit 2 ;;
esac
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec sh "$root/install.sh" "$@"
