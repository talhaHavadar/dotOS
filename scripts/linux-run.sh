#!/usr/bin/env bash
# linux-run.sh --arch ARCH [OPTIONS] -- CMD...: run CMD on native Linux/ARCH.
# On such a host CMD runs directly; anywhere else it runs in a VM from
# scripts/vm/backends/<VM_BACKEND>.sh, with the current directory and every
# --mount at the same path in the guest, so paths need no translating.
#
#   --mount DIR        also share DIR (writable) with the guest
#   --env-match REGEX  forward host variables whose names match into CMD
#   --image REF        make container image REF available to root's podman in
#                      the guest: refs with a registry (containing '/') are
#                      left for the guest to pull, others are streamed from
#                      the host with `RUNTIME save`
#   --runtime CMD      host container command for --image (default: docker)
#
# VM_BACKEND picks the backend (default: first available of $backends).
# VM_KEEP=1 keeps the VM (dotos-<arch>) for the next run instead of deleting
# it; remove it with the backend's own tooling (e.g. limactl delete).
#
# A backend defines:
#   backend_available            0 when the backend can be used on this host
#   backend_create NAME ARCH DIR...  boot NAME (or start it if it exists) with
#                                each DIR shared writable at the same path
#   backend_exec NAME DIR CMD... run CMD as the default (sudo-capable) user in
#                                DIR, passing stdin/stdout and the exit code
#   backend_destroy NAME         delete NAME; must not fail if it is gone
set -euo pipefail

backends="lima"
here=$(cd "$(dirname "$0")" && pwd)

arch='' image='' runtime=docker env_match='' mounts=("$PWD")
while [ $# -gt 0 ]; do
    case "$1" in
        --arch) arch=$2; shift 2 ;;
        --mount) mounts+=("$2"); shift 2 ;;
        --env-match) env_match=$2; shift 2 ;;
        --image) image=$2; shift 2 ;;
        --runtime) runtime=$2; shift 2 ;;
        --) shift; break ;;
        *) echo "linux-run.sh: unknown option $1" >&2; exit 2 ;;
    esac
done
if [ -z "$arch" ] || [ $# -eq 0 ]; then
    echo "usage: linux-run.sh --arch ARCH [OPTIONS] -- CMD..." >&2
    exit 2
fi

if [ -n "${DOTOS_IN_VM:-}" ] || { [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = "$arch" ]; }; then
    exec "$@"
fi

backend=
for b in ${VM_BACKEND:-$backends}; do
    f="$here/vm/backends/$b.sh"
    [ -f "$f" ] || { echo "linux-run.sh: no backend $b" >&2; exit 1; }
    # shellcheck source=/dev/null
    . "$f"
    for fn in backend_available backend_create backend_exec backend_destroy; do
        declare -F "$fn" >/dev/null || { echo "linux-run.sh: backend $b does not define $fn" >&2; exit 1; }
    done
    if backend_available; then backend=$b; break; fi
done
if [ -z "$backend" ]; then
    echo "linux-run.sh: this needs native Linux/$arch or a VM backend (${VM_BACKEND:-$backends}); install one, e.g. lima" >&2
    exit 1
fi

# Share each directory once: backends may refuse overlapping mounts
shared=()
while IFS= read -r m; do
    for s in "${shared[@]+"${shared[@]}"}"; do
        case "$m/" in "$s"/*) continue 2 ;; esac
    done
    shared+=("$m")
done < <(for m in "${mounts[@]}"; do realpath "$m"; done | sort -u)

if [ -n "${VM_KEEP:-}" ]; then
    vm="dotos-$arch"
else
    vm="dotos-$arch-$$"
    trap 'backend_destroy "$vm"' EXIT
fi

echo "linux-run.sh: running in $backend VM $vm" >&2
backend_create "$vm" "$arch" "${shared[@]}"

# Provision once per VM and again whenever provision.sh changes
sum=$(cksum <"$here/vm/provision.sh")
if ! backend_exec "$vm" / sudo sh -c "[ \"\$(cat /var/lib/dotos-provisioned 2>/dev/null)\" = '$sum' ]"; then
    backend_exec "$vm" / sudo bash -s <"$here/vm/provision.sh"
    backend_exec "$vm" / sudo sh -c "echo '$sum' >/var/lib/dotos-provisioned"
fi

if [ -n "$image" ] && [[ "$image" != */* ]]; then
    echo "linux-run.sh: copying $image into the VM" >&2
    $runtime save "$image" | backend_exec "$vm" / sudo podman load
fi

envs=(DOTOS_IN_VM=1)
if [ -n "$env_match" ]; then
    while IFS= read -r name; do
        envs+=("$name=${!name}")
    done < <(compgen -e | grep -E "$env_match" || true)
fi
backend_exec "$vm" "$PWD" env "${envs[@]}" "$@"
