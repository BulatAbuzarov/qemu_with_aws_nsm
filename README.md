# AArch64 QEMU NSM request-dump POC

This local-only POC boots AWS's AArch64 enclave kernel under QEMU, loads the
matching NSM module, sends `DescribeNSM` and `Attestation` through `/dev/nsm`,
and copies the resulting raw CBOR requests from QEMU to `nsm_dump.py`.

```sh
python3 -m pip install cbor2
./build-qemu.sh       # once; requires libcbor, Meson, Ninja, and QEMU build deps
./run.sh
```

`run.sh` downloads and caches `Image`, `cmdline`, and `nsm.ko` in `.work/`.
It builds the tiny AArch64 initramfs using `aarch64-linux-gnu-gcc`, or an
`linux/arm64` Alpine Docker container when a cross compiler is unavailable.

Expected host output includes:

```text
[NSM] command=DescribeNSM
[NSM] command=Attestation
```

The QEMU patch intentionally uses a best-effort `/tmp/nsm-dump.sock` tap.
Connection or write failures are ignored so they cannot alter the guest NSM
response path. This is not AWS attestation and does not produce an
AWS-signed attestation document.

`qemu-aarch64-nsm.patch` also enables `CONFIG_VIRTIO_NSM` for the AArch64
target. QEMU enables it by default only through its x86 Nitro machine, so
having libcbor installed alone is insufficient.
