#!/bin/bash
# Adapts Debian's ignition dracut module to a bootc composefs root:
# - runs Ignition whenever ignition.platform.id is on the kernel command line,
#   but only until it has succeeded once (marker in the persistent /var)
# - every stage runs after bootc-root-setup has mounted the deployment's
#   /etc and /var, so users and files land in persistent state
# - disks/kargs/remount-sysroot are masked: they run before the root is set up
#   and the composefs root must stay read-only
# - SELinux relabeling (always on in Debian's build) becomes a no-op

check() {
    return 255
}

depends() {
    echo ignition bootc
}

install() {
    inst_multiple mkdir touch

    # Replace the upstream generator (inst_simple would skip an existing file);
    # `command` because this function shadows install(1)
    command install -D -m 0755 "$moddir/ignition-generator" \
        "${initdir}${systemdutildir}/system-generators/ignition-generator"

    local unit
    for unit in ignition-disks.service ignition-kargs.service ignition-remount-sysroot.service; do
        rm -f "${initdir}${systemdsystemunitdir}"/*.requires/"$unit"
        ln -sf /dev/null "${initdir}${systemdsystemunitdir}/$unit"
    done

    for unit in fetch-offline fetch mount files; do
        inst_simple "$moddir/ignition-gate.conf" \
            "${systemdsystemunitdir}/ignition-$unit.service.d/10-dotos-gate.conf"
    done

    inst_simple "$moddir/ignition-mount-order.conf" \
        "${systemdsystemunitdir}/ignition-mount.service.d/20-dotos-order.conf"

    inst_simple "$moddir/ignition-files-homedir.conf" \
        "${systemdsystemunitdir}/ignition-files.service.d/20-dotos-homedir.conf"

    if ! command -v setfiles >/dev/null; then
        inst_simple "$moddir/setfiles-stub" /usr/sbin/setfiles
        inst_simple "$moddir/ignition-files-selinux.conf" \
            "${systemdsystemunitdir}/ignition-files.service.d/30-dotos-selinux.conf"
    fi

    inst_simple "$moddir/dotos-ignition-done.service" \
        "${systemdsystemunitdir}/dotos-ignition-done.service"
    mkdir -p "${initdir}${systemdsystemunitdir}/ignition-complete.target.requires"
    ln_r "${systemdsystemunitdir}/dotos-ignition-done.service" \
        "${systemdsystemunitdir}/ignition-complete.target.requires/dotos-ignition-done.service"
}
