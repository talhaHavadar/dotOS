#!/usr/bin/env bash
# Builds the two-slot U-Boot firmware for the Radxa ROCK Pi E into /output:
#   idbloader-a.img  TPL+SPL loading u-boot.itb from sector 0x4000 (slot A)
#   idbloader-b.img  TPL+SPL loading u-boot.itb from sector 0x6000 (slot B)
#   u-boot.itb       BL31 + U-Boot + DT, identical for both slots
#   VERSION          U-Boot release string, e.g. 2026.04-dotos.7.g1a2b3c4
# Usage: build.sh <localversion>, from scripts/firmware-version.sh (`just build`
# passes it). Every firmware input lives next to this script: sources (pinned
# tarballs), patches/, deps.sh.
set -xeuo pipefail

localversion=${1:-}
if [ -z "$localversion" ]; then
    echo "build.sh: no localversion; build with \`just build rockpie\`" >&2
    exit 1
fi
here=$(dirname "$(realpath "$0")")
out=/output
mkdir -p "$out"

# shellcheck source=sources
. "$here/sources"
src=/src uboot=/src/u-boot tfa=/src/tf-a
mkdir -p "$uboot" "$tfa"
curl -fsSL -o "$src/u-boot.tar.gz" "https://github.com/u-boot/u-boot/archive/refs/tags/${UBOOT_VERSION}.tar.gz"
curl -fsSL -o "$src/tf-a.tar.gz" "https://github.com/ARM-software/arm-trusted-firmware/archive/refs/tags/${TFA_VERSION}.tar.gz"
printf '%s  %s\n' "$UBOOT_SHA256" "$src/u-boot.tar.gz" "$TFA_SHA256" "$src/tf-a.tar.gz" | sha256sum -c
tar xzf "$src/u-boot.tar.gz" --strip-components=1 -C "$uboot"
tar xzf "$src/tf-a.tar.gz" --strip-components=1 -C "$tfa"
for p in "$here"/patches/u-boot/*.patch; do patch -d "$uboot" -p1 < "$p"; done

# Native on arm64; cross-compile elsewhere (local builds on x86)
if [ "$(uname -m)" != aarch64 ]; then
    export CROSS_COMPILE=aarch64-linux-gnu-
fi

# TF-A picks up CC from the environment, so point every tool at the
# (cross) toolchain explicitly
make -C "$tfa" -j"$(nproc)" PLAT=rk3328 \
    CC="${CROSS_COMPILE:-}gcc" LD="${CROSS_COMPILE:-}ld" AS="${CROSS_COMPILE:-}gcc" \
    OC="${CROSS_COMPILE:-}objcopy" OD="${CROSS_COMPILE:-}objdump" AR="${CROSS_COMPILE:-}ar" \
    bl31
bl31=$(realpath "$tfa/build/rk3328/release/bl31/bl31.elf")

# U-Boot's own pylibfdt wrapper does not build with Debian unstable's
# swig/Python (PyInt_AsLong). NO_PYTHON=1 skips it while keeping U-Boot's
# bundled dtc (Debian's dtc rejects U-Boot's -Wno-graph_child_address);
# binman then uses python3-libfdt from the distribution.
export NO_PYTHON=1

# Reproducible: the FIT and version banners embed the build time. Use the
# release's own timestamp (git archive sets file mtimes to the commit time),
# so both slot builds produce the same u-boot.itb.
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(stat -c %Y "$uboot/Makefile")}
export SOURCE_DATE_EPOCH

for slot in a:0x4000 b:0x6000; do
    name=${slot%%:*} sector=${slot#*:} obj=/tmp/uboot-$name
    make -C "$uboot" O="$obj" rock-pi-e-rk3328_defconfig
    "$uboot/scripts/config" --file "$obj/.config" \
        --set-str LOCALVERSION "$localversion" \
        --disable LOCALVERSION_AUTO \
        --set-val SYS_MMCSD_RAW_MODE_U_BOOT_SECTOR "$sector"
    make -C "$uboot" O="$obj" olddefconfig
    # LOCALVERSION= (set but empty) keeps setlocalversion from appending "+"
    make -C "$uboot" O="$obj" -j"$(nproc)" BL31="$bl31" LOCALVERSION=
    cp "$obj/idbloader.img" "$out/idbloader-$name.img"
done

# Same FIT for both slots; only SPL differs in where it looks for it
cmp /tmp/uboot-a/u-boot.itb /tmp/uboot-b/u-boot.itb
cp /tmp/uboot-a/u-boot.itb "$out/u-boot.itb"
cp /tmp/uboot-a/include/config/uboot.release "$out/VERSION"
(cd "$out" && sha256sum idbloader-a.img idbloader-b.img u-boot.itb > SHA256SUMS)
cat "$out/VERSION"
