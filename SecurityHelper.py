#!/usr/bin/env python3
"""Small security boundary for untrusted shell-plugin inputs."""

from __future__ import annotations

import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile


MAX_ARTWORK_BYTES = 8 * 1024 * 1024
MAX_CLIENTS_BYTES = 1024 * 1024
PRIVATE_DIR_NAME = f"omarchy-apple-music-media-{os.getuid()}"


def _runtime_directory() -> Path:
    raw_base = os.environ.get("XDG_RUNTIME_DIR", "")
    if not raw_base or not os.path.isabs(raw_base):
        raise RuntimeError("XDG_RUNTIME_DIR is unavailable")

    base = Path(raw_base)
    base_stat = base.lstat()
    if not stat.S_ISDIR(base_stat.st_mode) or base_stat.st_uid != os.getuid():
        raise RuntimeError("XDG_RUNTIME_DIR is not private")
    if base_stat.st_mode & 0o077:
        raise RuntimeError("XDG_RUNTIME_DIR has unsafe permissions")

    private = base / PRIVATE_DIR_NAME
    try:
        private.mkdir(mode=0o700)
    except FileExistsError:
        pass

    private_stat = private.lstat()
    if (
        not stat.S_ISDIR(private_stat.st_mode)
        or private_stat.st_uid != os.getuid()
        or private_stat.st_mode & 0o077
    ):
        raise RuntimeError("artwork directory is not private")
    return private


def _copy_validated_artwork(source: str) -> str:
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
    source_fd = os.open(source, flags)
    destination_fd = -1
    destination_path = ""
    try:
        before = os.fstat(source_fd)
        if before.st_uid != os.getuid():
            raise RuntimeError("artwork owner mismatch")
        if not stat.S_ISREG(before.st_mode):
            raise RuntimeError("artwork is not a regular file")
        if before.st_mode & 0o077:
            raise RuntimeError("artwork permissions are not owner-private")
        if before.st_size <= 0 or before.st_size > MAX_ARTWORK_BYTES:
            raise RuntimeError("artwork size is out of bounds")

        private = _runtime_directory()
        destination_fd, destination_path = tempfile.mkstemp(
            prefix="art-", suffix=".img", dir=private
        )
        os.fchmod(destination_fd, 0o600)

        remaining = before.st_size
        while remaining:
            chunk = os.read(source_fd, min(64 * 1024, remaining))
            if not chunk:
                raise RuntimeError("artwork changed while being copied")
            view = memoryview(chunk)
            while view:
                written = os.write(destination_fd, view)
                view = view[written:]
            remaining -= len(chunk)

        # Never copy bytes beyond the size that was accepted by fstat.
        if os.read(source_fd, 1):
            raise RuntimeError("artwork grew while being copied")

        after = os.fstat(source_fd)
        if (
            after.st_dev != before.st_dev
            or after.st_ino != before.st_ino
            or after.st_uid != before.st_uid
            or not stat.S_ISREG(after.st_mode)
            or after.st_size != before.st_size
            or after.st_mtime_ns != before.st_mtime_ns
            or after.st_ctime_ns != before.st_ctime_ns
        ):
            raise RuntimeError("artwork changed while being copied")

        os.fsync(destination_fd)
        os.fchmod(destination_fd, 0o400)
        os.close(destination_fd)
        destination_fd = -1

        # Runtime directories disappear at logout. Keep a small bounded set
        # during long shell sessions without touching the snapshot just made.
        snapshots = sorted(
            private.glob("art-*.img"),
            key=lambda path: path.stat().st_mtime_ns,
            reverse=True,
        )
        for stale in snapshots[8:]:
            try:
                stale.unlink()
            except OSError:
                pass

        return Path(destination_path).as_uri()
    except Exception:
        if destination_fd >= 0:
            os.close(destination_fd)
        if destination_path:
            try:
                os.unlink(destination_path)
            except OSError:
                pass
        raise
    finally:
        os.close(source_fd)


def _bounded_hyprctl_clients() -> bytes:
    process = subprocess.Popen(
        ["hyprctl", "clients", "-j"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    assert process.stdout is not None
    output = process.stdout.read(MAX_CLIENTS_BYTES + 1)
    if len(output) > MAX_CLIENTS_BYTES:
        process.kill()
        process.wait()
        raise RuntimeError("hyprctl output is too large")
    if process.wait() != 0:
        raise RuntimeError("hyprctl failed")
    return output


def main(argv: list[str]) -> int:
    try:
        if len(argv) == 3 and argv[1] == "artwork":
            print(_copy_validated_artwork(argv[2]))
            return 0
        if len(argv) == 2 and argv[1] == "clients":
            sys.stdout.buffer.write(_bounded_hyprctl_clients())
            return 0
    except (OSError, RuntimeError):
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
