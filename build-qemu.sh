#!/usr/bin/env bash
# Build a QEMU that contains the NSM device and the request-dump tap.
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work_dir=${WORK_DIR:-"$repo_dir/.work"}
source_dir=$work_dir/qemu
patch_file=$repo_dir/qemu-nsm-dump.patch
device_patch_file=$repo_dir/qemu-aarch64-nsm.patch

for tool in git meson ninja pkg-config; do
    command -v "$tool" >/dev/null || { echo "required build tool not found: $tool" >&2; exit 1; }
done
if ! pkg-config --exists libcbor; then
    echo "libcbor development files are required (for example: brew install libcbor)." >&2
    exit 1
fi

mkdir -p "$work_dir"
if [[ ! -d $source_dir/.git ]]; then
    git clone --depth 1 --branch v11.1.0 https://github.com/qemu/qemu.git "$source_dir"
fi
if rg -q 'nsm_dump_request' "$source_dir/hw/virtio/virtio-nsm.c"; then
    echo "QEMU patch already applied"
else
    git -C "$source_dir" apply --check "$patch_file"
    git -C "$source_dir" apply "$patch_file"
fi
if git -C "$source_dir" apply --reverse --check "$device_patch_file"; then
    echo "AArch64 NSM device selection already applied"
else
    git -C "$source_dir" apply --check "$device_patch_file"
    git -C "$source_dir" apply "$device_patch_file"
fi
(
    cd "$source_dir"
    ./configure --target-list=aarch64-softmmu --enable-hvf
)
ninja -C "$source_dir/build" qemu-system-aarch64
echo "built: $source_dir/build/qemu-system-aarch64"
