from __future__ import annotations

import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import unquote, urlparse


PLUGIN_DIR = Path(__file__).resolve().parent.parent
HELPER = PLUGIN_DIR / "SecurityHelper.py"


class SecurityHelperTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(
            prefix="apple-music-security-test-"
        )
        self.sandbox = Path(self.temporary.name)
        self.runtime_dir = self.sandbox / "runtime"
        self.runtime_dir.mkdir(mode=0o700)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_helper(
        self, *arguments: str, path: str | None = None
    ) -> subprocess.CompletedProcess[bytes]:
        environment = os.environ.copy()
        environment["XDG_RUNTIME_DIR"] = str(self.runtime_dir)
        if path is not None:
            environment["PATH"] = path
        return subprocess.run(
            [sys.executable, str(HELPER), *arguments],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            timeout=5,
            check=False,
        )

    def make_fake_hyprctl(self, body: str) -> Path:
        binary_dir = self.sandbox / "bin"
        binary_dir.mkdir(mode=0o700)
        executable = binary_dir / "hyprctl"
        executable.write_text(f"#!/usr/bin/python3\n{body}\n", encoding="utf-8")
        executable.chmod(0o700)
        return binary_dir

    def test_uses_descriptor_based_checks(self) -> None:
        source = HELPER.read_text(encoding="utf-8")
        self.assertIn("os.O_NOFOLLOW | os.O_NONBLOCK", source)
        self.assertIn("before = os.fstat(source_fd)", source)
        self.assertIn("before.st_uid != os.getuid()", source)
        self.assertIn("stat.S_ISREG(before.st_mode)", source)
        self.assertIn("before.st_mode & 0o077", source)
        self.assertIn("before.st_size > MAX_ARTWORK_BYTES", source)

    def test_copies_accepted_bytes_to_private_read_only_snapshot(self) -> None:
        source = self.sandbox / ".org.chromium.Chromium.Abc123"
        content = b"bounded image bytes"
        source.write_bytes(content)
        source.chmod(0o600)

        result = self.run_helper("artwork", str(source))

        self.assertEqual(result.returncode, 0, result.stderr)
        parsed = urlparse(result.stdout.decode().strip())
        snapshot = Path(unquote(parsed.path))
        metadata = snapshot.lstat()
        self.assertEqual(parsed.scheme, "file")
        self.assertNotEqual(snapshot, source)
        self.assertEqual(snapshot.parent.parent, self.runtime_dir)
        self.assertTrue(stat.S_ISREG(metadata.st_mode))
        self.assertEqual(metadata.st_uid, os.getuid())
        self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o400)
        self.assertEqual(snapshot.read_bytes(), content)

    def test_rejects_symlink_and_fifo_without_blocking(self) -> None:
        target = self.sandbox / "target"
        link = self.sandbox / ".org.chromium.Chromium.Link12"
        fifo = self.sandbox / ".org.chromium.Chromium.Fifo12"
        target.write_bytes(b"data")
        link.symlink_to(target)
        os.mkfifo(fifo)

        self.assertNotEqual(self.run_helper("artwork", str(link)).returncode, 0)
        self.assertNotEqual(self.run_helper("artwork", str(fifo)).returncode, 0)

    def test_rejects_input_larger_than_eight_mib(self) -> None:
        source = self.sandbox / ".org.chromium.Chromium.Big123"
        with source.open("wb") as stream:
            stream.truncate(8 * 1024 * 1024 + 1)
        source.chmod(0o600)

        result = self.run_helper("artwork", str(source))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")

    def test_rejects_non_private_source_permissions(self) -> None:
        source = self.sandbox / ".org.chromium.Chromium.Mode12"
        source.write_bytes(b"data")
        source.chmod(0o666)

        result = self.run_helper("artwork", str(source))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")

    def test_passes_through_bounded_hyprctl_document(self) -> None:
        document = '[{"class":"music.apple.com","pid":42}]'
        binary_dir = self.make_fake_hyprctl(
            f"import sys\nsys.stdout.write({document!r})"
        )

        result = self.run_helper("clients", path=f"{binary_dir}:/usr/bin")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.decode(), document)

    def test_emits_nothing_when_hyprctl_exceeds_one_mib(self) -> None:
        binary_dir = self.make_fake_hyprctl(
            "import sys\nsys.stdout.buffer.write(b'x' * (1024 * 1024 + 1))"
        )

        result = self.run_helper("clients", path=f"{binary_dir}:/usr/bin")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")


if __name__ == "__main__":
    unittest.main()
