#!/bin/sh
set -eu

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cat > "$workdir/fail.sh" <<'FAIL'
exit 1
FAIL
cat > "$workdir/pass.sh" <<PASS
touch "$workdir/pass-ran"
PASS

if make --no-print-directory node-tests NODE=sh NODE_TESTS="$workdir/fail.sh $workdir/pass.sh"; then
    exit 1
fi
test ! -e "$workdir/pass-ran"
