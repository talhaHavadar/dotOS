# Lima backend for linux-run.sh: a Fedora VM from Lima's own template

backend_available() {
    command -v limactl >/dev/null
}

backend_create() {
    local name=$1 arch=$2; shift 2
    local mounts=() m
    for m in "$@"; do mounts+=(--mount-only "$m:w"); done
    if ! limactl list --quiet 2>/dev/null | grep -qx "$name"; then
        limactl start --tty=false --name "$name" --arch "$arch" \
            --containerd none "${mounts[@]}" template:fedora
        return
    fi
    # A kept VM may have been made for other directories: remount them
    local want have
    want=$(printf '%s\n' "$@" | sort)
    have=$(limactl list --format '{{range .Config.Mounts}}{{.Location}}{{"\n"}}{{end}}' "$name" | sed '/^$/d' | sort)
    if [ "$want" != "$have" ]; then
        limactl stop "$name" >/dev/null 2>&1 || true
        limactl edit --tty=false "${mounts[@]}" "$name"
    fi
    [ "$(limactl list --format '{{.Status}}' "$name")" = Running ] ||
        limactl start --tty=false "$name"
}

backend_exec() {
    local name=$1 dir=$2; shift 2
    limactl shell --workdir "$dir" "$name" "$@"
}

backend_destroy() {
    limactl delete --force "$1" >/dev/null 2>&1 || true
}
