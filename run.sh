#!/usr/bin/env bash
# Launch the macOS/AArch64 NSM tap POC.  See README.md for the one-time QEMU build.
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work_dir=${WORK_DIR:-"$repo_dir/.work"}
qemu=${QEMU_SYSTEM_AARCH64:-"$work_dir/qemu/build/qemu-system-aarch64"}
socket_path=${NSM_DUMP_SOCKET:-/tmp/nsm-dump.sock}
blob_url=https://raw.githubusercontent.com/aws/aws-nitro-enclaves-cli/main/blobs/aarch64
backend_pid=

cleanup() {
    [[ -n $backend_pid ]] && kill "$backend_pid" 2>/dev/null || true
    [[ -n $backend_pid ]] && wait "$backend_pid" 2>/dev/null || true
    [[ -S $socket_path ]] && rm -f -- "$socket_path"
}
trap cleanup EXIT INT TERM

for tool in curl python3; do
    command -v "$tool" >/dev/null || { echo "required tool not found: $tool" >&2; exit 1; }
done
python3 -c 'import cbor2' 2>/dev/null || {
    echo "missing Python dependency: install it with 'python3 -m pip install cbor2'" >&2
    exit 1
}
[[ -x $qemu ]] || {
    echo "patched QEMU not found: $qemu" >&2
    echo "Run ./build-qemu.sh once, or set QEMU_SYSTEM_AARCH64." >&2
    exit 1
}
if ! "$qemu" -device help 2>&1 | grep -q 'virtio-nsm-device'; then
    echo "$qemu does not include virtio-nsm-device (build QEMU with libcbor support)." >&2
    exit 1
fi

mkdir -p "$work_dir"
for blob in Image cmdline nsm.ko; do
    if [[ ! -s $work_dir/$blob ]]; then
        curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 10 \
            --max-time 300 -o "$work_dir/$blob.part" "$blob_url/$blob"
        mv "$work_dir/$blob.part" "$work_dir/$blob"
    fi
done

if [[ ! -s $work_dir/initramfs.cpio.gz || $repo_dir/guest/init.c -nt $work_dir/initramfs.cpio.gz || $work_dir/nsm.ko -nt $work_dir/initramfs.cpio.gz ]]; then
    "$repo_dir/guest/build-initramfs.sh" "$work_dir/nsm.ko" "$work_dir/initramfs.cpio.gz"
fi

if [[ -e $socket_path || -L $socket_path ]]; then
    [[ -S $socket_path ]] || {
        echo "refusing to remove non-socket path: $socket_path" >&2
        exit 1
    }
    rm -f -- "$socket_path"
fi
NSM_DUMP_SOCKET="$socket_path" python3 "$repo_dir/nsm_dump.py" &
backend_pid=$!
for _ in {1..50}; do
    [[ -S $socket_path ]] && break
    sleep 0.1
done
[[ -S $socket_path ]] || { echo "NSM dump backend did not start" >&2; exit 1; }

cmdline=$(tr '\n' ' ' < "$work_dir/cmdline")
case $(uname -s) in
    Darwin) accel=(-accel hvf -cpu host) ;;
    Linux)  [[ -e /dev/kvm ]] && accel=(-accel kvm -cpu host) || accel=(-accel tcg -cpu max) ;;
    *)      accel=(-accel tcg -cpu max) ;;
esac

"$qemu" \
    -machine virt -nographic -m "${MEMORY:-1024}" -smp "${SMP:-2}" \
    "${accel[@]}" \
    -kernel "$work_dir/Image" -initrd "$work_dir/initramfs.cpio.gz" \
    -append "$cmdline console=ttyAMA0" \
    -device virtio-nsm-device
