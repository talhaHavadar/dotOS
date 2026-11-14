mod bcvk 'bcvk.just'

image_name := env("BUILD_IMAGE_NAME", "")
image_tag := env("BUILD_IMAGE_TAG", "latest")
base_dir := env("BUILD_BASE_DIR", ".")
filesystem := env("BUILD_FILESYSTEM", "ext4")
selinux := env("BUILD_SELINUX", "true")
# Stamped into os-release (VERSION_ID, BUILD_ID) and the image labels
version := env("BUILD_VERSION", `date -u +%Y%m%d`)
commit := env("BUILD_COMMIT", `git rev-parse --short HEAD 2>/dev/null || true`)

options := if selinux == "true" { "-v /var/lib/containers:/var/lib/containers:Z -v /etc/containers:/etc/containers:Z -v /sys/fs/selinux:/sys/fs/selinux --security-opt label=type:unconfined_t" } else { "-v /var/lib/containers:/var/lib/containers -v /etc/containers:/etc/containers" }
container_runtime := env("CONTAINER_RUNTIME", `command -v podman >/dev/null 2>&1 && echo podman || echo docker`)
sudo_prefix := if env("NOSUDO", "") == "" { "sudo " } else { "" }

# Build image and run an ephemeral VM for boot testing
test IMAGE=image_name:
    just bcvk build-and-test {{IMAGE}}

# Extra ARGS are passed to the container build (e.g. --cache-from/--cache-to in CI).
# Images with a firmware/ directory get its version from git history.
build $image_name=image_name *ARGS:
    fw_version=$(scripts/firmware-version.sh {{image_name}}/firmware) && \
    {{sudo_prefix}}{{container_runtime}} build --build-arg "DOTOS_VERSION={{version}}" --build-arg "DOTOS_COMMIT={{commit}}" --build-arg "FIRMWARE_LOCALVERSION=$fw_version" {{ARGS}} -f {{image_name}}/Containerfile -t "${image_name}-bootc:latest" .

bootc $image_name=image_name $image_tag=image_tag *ARGS:
    sudo {{container_runtime}} run \
        --rm --privileged --pid=host \
        -it \
        {{options}} \
        -v /dev:/dev \
        -e RUST_LOG=debug \
        -v "{{base_dir}}:/data" \
        {{ if image_name =~ '/' { if image_name =~ ':[^/]+$' { image_name } else { image_name + ":" + image_tag } } else { image_name + "-bootc:" + image_tag } }} bootc {{ARGS}}

disk-image $image_name=image_name $image_tag=image_tag $base_dir=base_dir $filesystem=filesystem *ARGS:
    #!/usr/bin/env bash
    if [ ! -e "${base_dir}/bootable.img" ] ; then
        fallocate -l 20G "${base_dir}/bootable.img"
    fi
    just bootc $image_name $image_tag install to-disk --composefs-backend --via-loopback /data/bootable.img --filesystem "${filesystem}" --wipe --bootloader systemd {{ARGS}}

# Disk image for boards that boot firmware from raw sectors: a GPT whose first
# partition (the ESP) starts after a reserved area (A/B firmware slots), then
# `bootc install to-filesystem`, then the image's own `dotos-firmware install`
# if it ships one. Must run on the image's architecture: under qemu-user bootc
# install fails (setns, fs-verity ioctls), so off native Linux/aarch64 it runs
# in a VM (scripts/linux-run.sh; VM_BACKEND, VM_KEEP). Writes
# <base_dir>/<name>-embedded.img.zst; ARGS go to `bootc install` (e.g.
# --target-imgref, --root-ssh-authorized-keys).
# Tunables: EMBEDDED_RESERVED_MIB (16), EMBEDDED_ESP_MIB (1024), EMBEDDED_SIZE (8G)
disk-image-embedded $image_name=image_name $image_tag=image_tag $base_dir=base_dir $filesystem=filesystem *ARGS:
    scripts/linux-run.sh --arch aarch64 --mount "$base_dir" --env-match '^EMBEDDED_' \
        --image "{{ if image_name =~ '/' { if image_name =~ ':[^/]+$' { image_name } else { image_name + ":" + image_tag } } else { image_name + "-bootc:" + image_tag } }}" \
        --runtime "{{sudo_prefix}}{{container_runtime}}" \
        -- just _disk-image-embedded "$image_name" "$image_tag" "$base_dir" "$filesystem" {{ARGS}}

[private]
_disk-image-embedded $image_name $image_tag $base_dir $filesystem *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    image="{{ if image_name =~ '/' { if image_name =~ ':[^/]+$' { image_name } else { image_name + ":" + image_tag } } else { image_name + "-bootc:" + image_tag } }}"
    name="${image_name##*/}"; name="${name%%:*}"
    out="$(realpath "${base_dir}")/${name}-embedded.img"
    reserved_mib="${EMBEDDED_RESERVED_MIB:-16}"
    esp_mib="${EMBEDDED_ESP_MIB:-1024}"
    size="${EMBEDDED_SIZE:-8G}"
    sudo="{{sudo_prefix}}"
    case "$(uname -m)" in
        aarch64) root_type=b921b045-1df0-41c3-af44-4c6f280d3fae ;;
        x86_64)  root_type=4f68bce3-e8cd-4db1-96e7-fbcaf984b709 ;;
        *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
    esac
    case "${filesystem}" in
        ext4)  mkfs=(mkfs.ext4 -q -O verity -L root) ;;
        btrfs) mkfs=(mkfs.btrfs -q -L root) ;;
        *) echo "composefs needs fs-verity: use ext4 or btrfs, not ${filesystem}" >&2; exit 1 ;;
    esac

    mnt=$(mktemp -d)
    loop=
    cleanup() {
        set +e
        mountpoint -q "$mnt" && $sudo umount -R "$mnt"
        [ -n "$loop" ] && $sudo losetup -d "$loop"
        rmdir "$mnt"
    }
    trap cleanup EXIT

    rm -f "$out"
    truncate -s "$size" "$out"
    printf 'label: gpt\nfirst-lba: %s\nstart=%sMiB, size=%sMiB, type=uefi, name=EFI-SYSTEM\ntype=%s, name=root\n' \
        "$((reserved_mib * 2048))" "$reserved_mib" "$esp_mib" "$root_type" | sfdisk -q "$out"
    loop=$($sudo losetup -Pf --show "$out")
    $sudo udevadm settle || true
    $sudo mkfs.vfat -F32 -n EFI-SYSTEM "${loop}p1"
    $sudo "${mkfs[@]}" "${loop}p2"
    $sudo mount "${loop}p2" "$mnt"
    $sudo mkdir -p "$mnt/boot"
    $sudo mount "${loop}p1" "$mnt/boot"

    $sudo {{container_runtime}} run --rm --privileged --pid=host \
        {{options}} \
        -v /dev:/dev \
        -v "$mnt:/target" \
        "$image" bootc install to-filesystem --composefs-backend --bootloader systemd --generic-image {{ARGS}} /target
    $sudo umount -R "$mnt"

    # Raw-sector firmware (A/B slots) comes from the image itself. Unlabeled:
    # SELinux keeps a confined container from even loading the image's libc,
    # and only `test` saying no (1) means the image has no firmware.
    rc=0
    $sudo {{container_runtime}} run --rm --security-opt label=disable "$image" test -x /usr/bin/dotos-firmware || rc=$?
    case $rc in
        0) $sudo {{container_runtime}} run --rm --privileged -v /dev:/dev "$image" dotos-firmware install "$loop" ;;
        1) ;;
        *) echo "could not check $image for dotos-firmware (exit $rc)" >&2; exit 1 ;;
    esac

    $sudo losetup -d "$loop"; loop=
    $sudo chown "$(id -u):$(id -g)" "$out"
    zstd -q -T0 -10 --rm -f "$out"
    echo "$out.zst"

rechunk $image_name=image_name:
    #!/usr/bin/env bash
    export CHUNKAH_CONFIG_STR="$(podman inspect "${image_name}-bootc")"
    podman run --rm "--mount=type=image,src=${image_name}-bootc,target=/chunkah" -e CHUNKAH_CONFIG_STR quay.io/coreos/chunkah build --label ostree.bootable=1 --label containers.bootc=1 --compressed --max-layers 128 | \
        podman load | \
        sort -n | \
        head -n1 | \
        cut -d, -f2 | \
        cut -d: -f3 | \
        xargs -I{} podman tag {} "${image_name}-bootc"
