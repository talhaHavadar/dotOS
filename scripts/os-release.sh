#!/usr/bin/env bash
# Stamps the image variant and build version into /usr/lib/os-release.
# Each image layer (base, dev, ...) runs both subcommands with its own values:
#
#   os-release.sh variant <id> <name>        e.g. variant base Base
#       VARIANT_ID, VARIANT, IMAGE_ID, PRETTY_NAME.
#       Run early: the initramfs embeds os-release, and these values only
#       change when the Containerfile does, so layer caching is unaffected.
#
#   os-release.sh version <version> [commit] e.g. version 20261027 3725797
#       VERSION_ID, VERSION, IMAGE_VERSION, BUILD_ID.
#       Run last: the version changes with every build.
#
# bootc names boot entries after ID, PRETTY_NAME and VERSION_ID.

set -xeuo pipefail

os_release=/usr/lib/os-release

# Replaces KEY's line, or appends it
set_key() {
    sed -i "/^$1=/d" "$os_release"
    printf '%s="%s"\n' "$1" "$2" >> "$os_release"
}

get_key() {
    sed -n "s/^$1=//p" "$os_release" | tr -d '"'
}

# os-release limits IDs and versions to lowercase letters, digits and ".-_"
check_id() {
    if ! [[ "$1" =~ ^[a-z0-9._-]+$ ]]; then
        echo "invalid value '$1': only a-z, 0-9, '.', '_' and '-' are allowed" >&2
        exit 1
    fi
}

case "${1:-}" in
variant)
    id="$2"
    name="$3"
    check_id "$id"
    set_key VARIANT_ID "$id"
    set_key VARIANT "$name"
    set_key IMAGE_ID "$(get_key ID)-$id"
    set_key PRETTY_NAME "$(get_key NAME) $name"
    ;;
version)
    version="$2"
    commit="${3:-}"
    check_id "$version"
    set_key VERSION_ID "$version"
    set_key VERSION "$version ($(get_key VARIANT))"
    set_key IMAGE_VERSION "$version"
    if [ -n "$commit" ]; then
        set_key BUILD_ID "$commit"
    fi
    ;;
*)
    echo "usage: $0 variant <id> <name> | version <version> [commit]" >&2
    exit 1
    ;;
esac
