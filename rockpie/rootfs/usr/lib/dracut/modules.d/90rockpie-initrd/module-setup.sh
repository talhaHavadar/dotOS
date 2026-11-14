#!/bin/bash
# ROCK Pi E initramfs tweaks (enabled from 40-rockpie-initrd.conf).

check() {
    return 255
}

depends() {
    echo systemd-udevd
}

install() {
    inst_simple "$moddir/udev-trigger-devices-only.conf" \
        "$systemdsystemunitdir/systemd-udev-trigger.service.d/50-rockpie-devices-only.conf"
}
