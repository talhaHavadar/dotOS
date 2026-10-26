#!/usr/bin/env bash

set -xeuo pipefail

git clone "https://github.com/bootc-dev/bootc.git" .

# Reuse cargo build artifacts from the cache mount when building in a container
if [ -d /var/cache/cargo-target ]; then
    ln -sT /var/cache/cargo-target target
fi

make bin install-all DESTDIR=/output

