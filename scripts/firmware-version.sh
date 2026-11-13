#!/usr/bin/env bash
# firmware-version.sh <dir>: U-Boot LOCALVERSION for firmware built from <dir>
# (all of its inputs live there), e.g. -dotos.7.g1a2b3c4:
#   7        commits that changed <dir>
#   g1a2b3c4 the last of them
#   .dirty   appended when <dir> has uncommitted changes
# It changes only when the firmware sources do and grows along history, as
# dotos-firmware's `sort -V` downgrade check needs. Prints nothing when <dir>
# does not exist (images without firmware).
set -euo pipefail

dir=$1
[ -d "$dir" ] || exit 0

# A shallow clone undercounts, which would look like a downgrade on the board
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
    echo "firmware-version.sh: shallow clone, fetch the full history (fetch-depth: 0)" >&2
    exit 1
fi

n=$(git rev-list --count HEAD -- "$dir")
v="-dotos.$n"
[ "$n" -eq 0 ] || v+=".g$(git log -1 --format=%h --abbrev=7 -- "$dir")"
[ -z "$(git status --porcelain -- "$dir")" ] || v+=".dirty"
echo "$v"
