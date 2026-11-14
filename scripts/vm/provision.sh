#!/usr/bin/env bash
# provision.sh: tools linux-run.sh guests need, run as root in a Fedora guest
set -euo pipefail

dnf install -y --setopt=install_weak_deps=False \
    just podman util-linux systemd-udev e2fsprogs btrfs-progs dosfstools zstd
