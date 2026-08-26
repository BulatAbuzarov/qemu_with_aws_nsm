#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <nsm.ko> <initramfs.cpio.gz>" >&2
    exit 64
fi

module=$1
output=$2
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/.." && pwd)
work_dir=$(dirname -- "$output")
rootfs=$work_dir/rootfs
init_bin=$work_dir/init

[[ -f $module ]] || { echo "missing module: $module" >&2; exit 1; }
command -v cpio >/dev/null || { echo "cpio is required" >&2; exit 1; }
command -v gzip >/dev/null || { echo "gzip is required" >&2; exit 1; }

mkdir -p "$work_dir"
if command -v aarch64-linux-gnu-gcc >/dev/null; then
    aarch64-linux-gnu-gcc -static -Os -s -Wall -Wextra -o "$init_bin" "$script_dir/init.c"
elif command -v docker >/dev/null; then
    docker run --rm --platform linux/arm64 \
        -v "$repo_dir:/src" -w /src alpine:3.20 \
        sh -ec 'apk add --no-cache build-base linux-headers >/dev/null && gcc -static -Os -s -Wall -Wextra -o /src/.work/init /src/guest/init.c'
else
    echo "need aarch64-linux-gnu-gcc or Docker to build the AArch64 initramfs" >&2
    exit 1
fi

rm -rf "$rootfs"
mkdir -p "$rootfs"/{dev,proc,sys,tmp}
install -m 0755 "$init_bin" "$rootfs/init"
install -m 0644 "$module" "$rootfs/nsm.ko"
(
    cd "$rootfs"
    find . -print | cpio -o -H newc 2>/dev/null | gzip -9 > "$output"
)
