#!/usr/bin/env bash
# Runs after the Nix packages are installed.

set -xeuo pipefail

# Empty mount point; nix.mount binds /var/lib/nix here at boot (the postinst's
# tmpfiles run created the daemon dirs in the image, they belong in /var)
rm -rf /nix
mkdir /nix

printf 'experimental-features = nix-command flakes\n' >> /etc/nix/nix.conf

systemctl enable nix.mount nix-daemon.socket
