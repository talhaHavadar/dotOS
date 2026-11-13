#!/usr/bin/env bash
# Build dependencies for build.sh (Debian)
set -xeuo pipefail

rm -f /etc/apt/apt.conf.d/docker-clean
apt update -y
apt install -y --no-install-recommends bc bison build-essential ca-certificates curl \
    device-tree-compiler flex libgnutls28-dev libssl-dev patch python3 python3-libfdt \
    python3-pyelftools python3-setuptools uuid-dev
if [ "$(uname -m)" != aarch64 ]; then
    apt install -y --no-install-recommends gcc-aarch64-linux-gnu
fi
