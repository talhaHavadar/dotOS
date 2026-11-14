# dotOS

## Make a bootable Image

Following commands allows you to create a `bootable.img` file which you can easily flash it into an installation medium and use it to boot into customized bootc image.

```shell
# crates bootable.img file using bootc container for dotos-dev variant
just disk-image ghcr.io/talhahavadar/dotos-dev
# use rpi-imager to flash it into the block device
# use lsblk to identify the medium
rpi-imager --cli bootable.img <block device>
```

### Boards with firmware on the boot disk (ROCK Pi E)

Some boards boot their firmware from raw sectors at the start of the disk, so
the first partition has to start later. `just disk-image-embedded` leaves the
first 16 MiB free (`EMBEDDED_RESERVED_MIB`), installs with
`bootc install to-filesystem`, and then runs the image's own
`dotos-firmware install` to write the A/B firmware slots.

```shell
# bootc install does not work under qemu-user, so anywhere but arm64 Linux
# (e.g. macOS) this runs in a Lima VM; VM_KEEP=1 keeps it for the next run.
# The recipe uses sudo for its root steps itself.
just disk-image-embedded ghcr.io/talhahavadar/dotos-rockpie latest .
# writes ./dotos-rockpie-embedded.img.zst; flash it with e.g.
# zstdcat dotos-rockpie-embedded.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync
```

CI builds the same recipe for every `rockpie` build and uploads
`dotos-rockpie-<date>-arm64.img.zst` as a workflow artifact.

On the board, `dotos-firmware status` shows both slots; after an image update
that ships new firmware, `dotos-firmware update` writes slot A, and after the
next good boot `dotos-firmware-commit.service` copies it to slot B.

Firmware versions look like `2026.04-dotos.7.g1a2b3c4`: the U-Boot release,
the number of commits that changed `rockpie/firmware/` (where every firmware
input lives), and the last of them (`.dirty` for uncommitted changes).
`just build` derives it with `scripts/firmware-version.sh`, so it only changes
when the firmware does, and `dotos-firmware` refuses to install an older one.
Builds need the full git history.

## How to build?

`dev` images currently uses the published `base` images in github container registry. If you want to use locally build base image please change the Containerfile accordingly and then you can build as usual shown below.

Published images are multi-arch (amd64 and arm64): CI builds each architecture natively and pushes a manifest per tag (`latest`, the date, release tags), with the per-architecture images also available as `<tag>-amd64` and `<tag>-arm64`.

### Building

```shell
just build dev
# if not in an SELINUX system set BUILD_SELINUX to false
# To build for QEMU which allows ignition customization
# use ignition.platform.id=metal for default metal config or omit the ignition.platform.id completely
BUILD_SELINUX=false just disk-image dev latest . ext4 --karg ignition.platform.id=qemu --karg console=ttyS0

# run the image in qemu to test
# see test.ign below to see how to create a user
qemu-system-x86_64 -machine q35 -accel kvm -cpu host -m 4G -smp 4 \
   -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
   -drive file=bootable.img,format=raw,if=virtio \
   -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
   -fw_cfg name=opt/com.coreos/config,file=$PWD/test.ign \
   -nographic

# Do you have qemu from nix?
FW=$(dirname $(dirname $(readlink -f $(which qemu-system-x86_64))))/share/qemu/edk2-x86_64-code.fd
# boot with default metal config
qemu-system-x86_64 -machine q35 -accel kvm -cpu host -m 4G -smp 4 \
    -drive if=pflash,format=raw,readonly=on,file="$FW" \
    -drive file=bootable.img,format=raw,if=virtio \
    -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
    -nographic
```

### Ignition customization

This file is given to QEMU to create the initial user.

```json
{
  "ignition": {
    "version": "3.3.0"
  },
  "passwd": {
    "users": [
      {
        "name": "test",
        "passwordHash": "$6$DhpBkGjmkht3fdXZ$TsBvR.cijRa4fCpN.elZG9pwmfj6NAJ6KIQEyS3VUdJX83UeRVxwyJtWXmku77c.YG31qCFTz/jqGmJyuk8Do/",
        "groups": ["sudo", "nix-users"]
      }
    ]
  }
}
```
