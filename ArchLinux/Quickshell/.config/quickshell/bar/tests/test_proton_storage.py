import hashlib
import io
import os
import sys
import tarfile
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "proton"))
import storage
from proton_fixtures import installation


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="proton-storage-", dir="/tmp/opencode")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / "tools"
        self.base.mkdir()

    def archive(self, entries):
        path = self.root / "archive.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            for name, kind, value in entries:
                member = tarfile.TarInfo(name)
                member.type = kind
                if kind == tarfile.REGTYPE:
                    content = value.encode()
                    member.size = len(content)
                    member.mode = 0o755 if name.endswith("/proton") else 0o644
                    archive.addfile(member, io.BytesIO(content))
                else:
                    member.linkname = value
                    archive.addfile(member)
        return path

    def valid_entries(self):
        return [("GE-Proton11-8/proton", tarfile.REGTYPE, "#!/bin/sh\n"),
                ("GE-Proton11-8/compatibilitytool.vdf", tarfile.REGTYPE, '"compatibilitytools" { "compat_tools" { "GE-Proton11-8" { "install_path" "." } } }'),
                ("GE-Proton11-8/toolmanifest.vdf", tarfile.REGTYPE, '"manifest" { "commandline" "/proton run" }')]

    def test_extract_contained_links(self):
        archive = self.archive(self.valid_entries() + [("GE-Proton11-8/link", tarfile.SYMTYPE, "proton")])
        result = storage.extract_verified(archive, self.root / "stage")
        self.assertEqual((result / "link").read_bytes(), (result / "proton").read_bytes())
        self.assertEqual(storage.validate_installation(result)["name"], "GE-Proton11-8")

    def test_unsafe_archives_rejected(self):
        for name, kind, value in [("../escape", tarfile.REGTYPE, "bad"),
                                  ("/escape", tarfile.REGTYPE, "bad"),
                                  ("GE-Proton11-8/link", tarfile.SYMTYPE, "../../outside"),
                                  ("GE-Proton11-8/link", tarfile.LNKTYPE, "../outside"),
                                  ("GE-Proton11-8/device", tarfile.CHRTYPE, ""),
                                  ("other/proton", tarfile.REGTYPE, "bad"),
                                  ("GE-Proton11-8/proton", tarfile.REGTYPE, "duplicate")]:
            with self.subTest(name=name, kind=kind), self.assertRaises(ValueError):
                storage.extract_verified(self.archive(self.valid_entries() + [(name, kind, value)]), self.root / ("stage" + str(kind) + name.replace("/", "_")))

    def test_symlink_parent_rejected(self):
        entries = self.valid_entries() + [("GE-Proton11-8/dir", tarfile.SYMTYPE, "."), ("GE-Proton11-8/dir/file", tarfile.REGTYPE, "bad")]
        with self.assertRaises(ValueError):
            storage.extract_verified(self.archive(entries), self.root / "stage")

    def test_atomic_activation_preserves_existing(self):
        old = installation(self.base, "GE-Proton11-8")
        staging = self.root / "stage"
        staging.mkdir()
        new = installation(staging, "GE-Proton11-8")
        with self.assertRaises((ValueError, FileExistsError)):
            storage.activate(new, self.base, new.name)
        self.assertTrue((old / "proton").is_file())
        self.assertTrue(new.is_dir())

    def test_lock_excludes_second_worker(self):
        with storage.operation_lock(self.base):
            with self.assertRaises(ValueError):
                with storage.operation_lock(self.base):
                    self.fail("second lock succeeded")

    def test_removal_rejects_changed_identity_or_symlink(self):
        target = installation(self.base, "GE-Proton11-6")
        identity = storage.validate_installation(target)["identity"]
        (target / "compatibilitytool.vdf").write_text("changed")
        with self.assertRaises((ValueError, KeyError)):
            storage.remove_installation(self.base, target.name, identity)
        self.assertTrue(target.is_dir())

    def test_toml_preserves_unrelated_values_and_comments(self):
        config = self.root / "umu.toml"
        content = b'# keep\r\n["umu"]\r\nproton = "old" # note\r\nexe = "game"\r\n[extra]\r\nx = 3\r\n'
        config.write_bytes(content)
        config.chmod(0o640)
        storage.write_umu_selection(config, '/sandbox/GE-Proton11-8', hashlib.sha256(content).hexdigest())
        result = config.read_bytes()
        self.assertIn(b"# note\r\n", result)
        self.assertIn(b"[extra]\r\nx = 3\r\n", result)
        self.assertEqual(config.stat().st_mode & 0o777, 0o640)
        self.assertEqual(tomllib.loads(result.decode())["umu"]["proton"], "/sandbox/GE-Proton11-8")

    def test_config_concurrent_change_preserved(self):
        config = self.root / "umu.toml"
        config.write_text('[umu]\nproton="old"\n')
        digest = hashlib.sha256(config.read_bytes()).hexdigest()
        config.write_text('[umu]\nproton="changed"\n')
        with self.assertRaises(ValueError):
            storage.write_umu_selection(config, "new", digest)
        self.assertIn("changed", config.read_text())

    def test_unsupported_toml_does_not_change_bytes(self):
        for content in ['umu.proton="old"\n', '[umu]\nproton="""old"""\n', '[umu]\nproton=\n', '[other]\nx=2\n']:
            config = self.root / "umu.toml"
            config.write_text(content)
            with self.subTest(content=content), self.assertRaises(ValueError):
                storage.write_umu_selection(config, "new", hashlib.sha256(config.read_bytes()).hexdigest())
            self.assertEqual(config.read_text(), content)

    def test_missing_key_added_to_existing_table(self):
        config = self.root / "umu.toml"
        config.write_text('[umu]\nexe="game"\n[other]\nx=1\n')
        storage.write_umu_selection(config, '/a/quote"\\path', hashlib.sha256(config.read_bytes()).hexdigest())
        self.assertEqual(tomllib.loads(config.read_text())["umu"]["proton"], '/a/quote"\\path')

    def test_archive_limits(self):
        with self.assertRaises(ValueError):
            storage.extract_verified(self.archive(self.valid_entries()), self.root / "stage", max_members=2)

    def test_identity_survives_qml_json_precision(self):
        item = storage.validate_installation(installation(self.base, "GE-Proton11-7"))
        self.assertIsInstance(item["identity"]["modified"], str)


if __name__ == "__main__":
    unittest.main()
