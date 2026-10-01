"""Key storage regressions: dummy credentials only, no network or game writes."""

import io
import os
from pathlib import Path
import runpy
import socket
import stat
import tempfile
import unittest
from unittest.mock import patch


original_getaddrinfo = socket.getaddrinfo
helper = runpy.run_path(str(Path(__file__).resolve().parents[1] / "bin" / "wowaddons"))
socket.getaddrinfo = original_getaddrinfo
write_key = helper["write_key_file"]
key_globals = write_key.__globals__


class KeyStorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key = self.root / "config" / "curseforge-key"
        self.globals_patch = patch.dict(key_globals, KEY_FILE=self.key)
        self.globals_patch.start()
        self.addCleanup(self.globals_patch.stop)

    def assert_private_key(self, value):
        self.assertFalse(self.key.is_symlink())
        self.assertEqual(self.key.read_text(), value)
        self.assertEqual(stat.S_IMODE(self.key.stat().st_mode), 0o600)
        self.assertEqual(list(self.key.parent.glob("curseforge-key.*.tmp")), [])

    def test_create_and_replace_under_permissive_umask(self):
        old_umask = os.umask(0)
        try:
            write_key("dummy-first\n")
            self.assert_private_key("dummy-first\n")
            self.key.chmod(0o666)
            write_key("dummy-second\n")
            self.assert_private_key("dummy-second\n")
        finally:
            os.umask(old_umask)

    def test_predictable_temporary_symlink_is_untouched(self):
        self.key.parent.mkdir()
        victim = self.root / "victim"
        victim.write_text("unchanged")
        old_tmp = self.key.with_suffix(".tmp")
        old_tmp.symlink_to(victim)
        write_key("dummy-key\n")
        self.assert_private_key("dummy-key\n")
        self.assertTrue(old_tmp.is_symlink())
        self.assertEqual(victim.read_text(), "unchanged")

    def test_predictable_permissive_temporary_file_is_untouched(self):
        self.key.parent.mkdir()
        old_tmp = self.key.with_suffix(".tmp")
        old_tmp.write_text("unchanged")
        old_tmp.chmod(0o666)
        write_key("dummy-key\n")
        self.assert_private_key("dummy-key\n")
        self.assertEqual(old_tmp.read_text(), "unchanged")

    def test_destination_symlink_is_replaced_without_writing_target(self):
        self.key.parent.mkdir()
        victim = self.root / "victim"
        victim.write_text("unchanged")
        self.key.symlink_to(victim)
        write_key("dummy-key\n")
        self.assert_private_key("dummy-key\n")
        self.assertEqual(victim.read_text(), "unchanged")

    def test_replace_failure_preserves_old_key_and_cleans_temporary_file(self):
        write_key("dummy-old\n")
        with patch.object(os, "replace", side_effect=OSError("replacement failed")):
            with self.assertRaises(OSError):
                write_key("dummy-new\n")
        self.assert_private_key("dummy-old\n")

    def test_mode_is_enforced_before_secret_write(self):
        with patch.object(os, "fchmod", side_effect=OSError("permission repair failed")):
            with self.assertRaises(OSError):
                write_key("dummy-key\n")
        self.assertFalse(self.key.exists())
        self.assertEqual(list(self.key.parent.iterdir()), [])

    def test_rejected_key_restores_previous_key_privately(self):
        write_key("dummy-previous-credential\n")
        failure = helper["Failure"]("Rejected", code="http_403")
        with patch.dict(key_globals, api=lambda *args: (_ for _ in ()).throw(failure)):
            with patch.object(helper["sys"], "stdin", io.StringIO("dummy-replacement-credential\n")):
                with self.assertRaises(helper["Failure"]) as result:
                    helper["cmd_key"]({}, ["set"])
        self.assertEqual(result.exception.extra["code"], "key_rejected")
        self.assert_private_key("dummy-previous-credential\n")


if __name__ == "__main__":
    unittest.main()
