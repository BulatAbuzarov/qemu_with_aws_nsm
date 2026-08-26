#!/usr/bin/env python3
"""Best-effort Unix-socket tap for QEMU's virtio-nsm device."""

import os
import socket
import stat
import struct
import sys

try:
    import cbor2
except ImportError:
    cbor2 = None


SOCKET_PATH = os.environ.get("NSM_DUMP_SOCKET", "/tmp/nsm-dump.sock")
MAX_REQUEST_SIZE = 0x1000  # NSM_REQUEST_MAX_SIZE


def recv_exact(conn: socket.socket, size: int) -> bytes:
    data = bytearray()
    while len(data) < size:
        chunk = conn.recv(size - len(data))
        if not chunk:
            raise EOFError
        data.extend(chunk)
    return bytes(data)


def command_name(value: object) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, dict) and len(value) == 1:
        key = next(iter(value))
        return key if isinstance(key, str) else "UNKNOWN"
    return "UNKNOWN"


def remove_stale_socket() -> None:
    try:
        mode = os.lstat(SOCKET_PATH).st_mode
    except FileNotFoundError:
        return
    if not stat.S_ISSOCK(mode):
        raise RuntimeError(f"refusing to remove non-socket path: {SOCKET_PATH}")
    os.unlink(SOCKET_PATH)


def handle_connection(conn: socket.socket) -> None:
    while True:
        size = struct.unpack(">I", recv_exact(conn, 4))[0]
        if size > MAX_REQUEST_SIZE:
            raise ValueError(f"invalid NSM request size {size}")
        raw = recv_exact(conn, size)
        print(f"[NSM] raw={raw.hex()}", flush=True)

        if cbor2 is None:
            print("[NSM] CBOR decoder unavailable; install with: python3 -m pip install cbor2", flush=True)
            continue
        try:
            decoded = cbor2.loads(raw)
            print(f"[NSM] cbor={decoded!r}", flush=True)
            print(f"[NSM] command={command_name(decoded)}", flush=True)
        except Exception as exc:  # The raw dump remains useful on malformed CBOR.
            print(f"[NSM] decode error: {exc}", flush=True)


def main() -> int:
    remove_stale_socket()
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        server.bind(SOCKET_PATH)
        os.chmod(SOCKET_PATH, 0o600)
        server.listen(8)
        print(f"[NSM] listening on {SOCKET_PATH}", flush=True)
        while True:
            conn, _ = server.accept()
            with conn:
                try:
                    handle_connection(conn)
                except EOFError:
                    pass
                except Exception as exc:
                    print(f"[NSM] connection error: {exc}", file=sys.stderr, flush=True)
    finally:
        server.close()
        try:
            os.unlink(SOCKET_PATH)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
