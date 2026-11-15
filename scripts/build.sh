#!/usr/bin/env bash

set -xeuo pipefail

git clone "https://github.com/bootc-dev/bootc.git" .

# Reuse cargo build artifacts from the cache mount when building in a container
if [ -d /var/cache/cargo-target ]; then
    ln -sT /var/cache/cargo-target target
fi

# bootc's release profile keeps full debug info (debug = true) for RPM builds
# to split into a debuginfo package. Nothing splits it here, so it would ship
# in the image (bootc 415 MB instead of ~38 MB). Without it cargo strips the
# debug info but keeps the symbol table, so backtraces still name functions.
export CARGO_PROFILE_RELEASE_DEBUG=false

# Not install-all: that adds the integration test suite and the hooks for the
# ostree CLI's `ostree container`, which the image doesn't ship
make bin install DESTDIR=/output

