#!/usr/bin/env bash
# Replaces Debian's identity files with the dotOS ones from the given directory
# (base/branding). The Debian originals are kept as local dpkg diversions
# (<file>.debian), so a base-files upgrade in a derived image installs its
# versions there instead of overwriting the dotOS files.
#
# Usage: branding.sh <branding-dir>

set -xeuo pipefail

src="$1"

for file in /usr/lib/os-release /etc/issue /etc/issue.net; do
    dpkg-divert --local --rename --divert "$file.debian" --add "$file"
done

install -m 0644 "$src/os-release" /usr/lib/os-release
install -m 0644 "$src/issue" /etc/issue
install -m 0644 "$src/issue.net" /etc/issue.net
# Not owned by a package: base-files only copies it in when it is missing
install -m 0644 "$src/motd" /etc/motd

# Debian's codename (e.g. forky) stays, third-party apt repos and install
# scripts key on it
codename="$(. /usr/lib/os-release.debian && echo "${VERSION_CODENAME:-}")"
if [ -n "$codename" ]; then
    echo "VERSION_CODENAME=$codename" >> /usr/lib/os-release
fi
