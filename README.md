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

## How to build?

`dev` images currently uses the published `base` images in github container registry. If you want to use locally build base image please change the Containerfile accordingly and then you can build as usual shown below.

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
