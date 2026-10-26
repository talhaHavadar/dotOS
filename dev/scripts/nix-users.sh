#!/usr/bin/env bash
# Pre-create the Nix users and groups with fixed IDs (matching
# /usr/lib/sysusers.d/nix.conf) before nix-setup-systemd's postinst, which only
# creates them when missing. nix-users must already be in /etc/group because
# Ignition adds users to it before systemd-sysusers runs. IDs are in the system
# range so they don't move where useradd starts numbering real users (1000).

set -xeuo pipefail

groupadd -g 900 nixbld
groupadd -g 901 nix-users

for n in $(seq 1 10); do
    useradd -u $((900 + n)) -g nixbld -G nixbld -M -d /var/empty \
        -s /usr/sbin/nologin -c "Nix build user $n" "nixbld$n"
done
