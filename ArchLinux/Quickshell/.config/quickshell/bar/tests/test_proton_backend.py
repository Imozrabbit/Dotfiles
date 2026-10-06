import sys
import tempfile
import unittest
import hashlib
import shutil
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "proton"))
import backend
from proton_fixtures import configuration, installation


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="proton-test-", dir="/tmp/opencode")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = configuration(self.root)
        self.base = Path(self.config["compatibilityToolsDir"])
        self.proc = self.root / "proc"
        self.proc.mkdir()

    def test_config_paths(self):
        self.assertEqual(backend.validate_config(self.config), self.config)
        for path in ["relative", "", "/bad\0path", "/"]:
            with self.subTest(path=path), self.assertRaises(ValueError):
                backend.validate_config({**self.config, "compatibilityToolsDir": path})

    def test_inventory_filters_and_sorts(self):
        for name in ["GE-Proton11-6", "GE-Proton11-7", "GE-Proton9-20",
                     "proton-cachyos-20260928-slr-x86_64_v3",
                     "proton-cachyos-11.0-20261005-slr-x86_64_v3", "unknown"]:
            installation(self.base, name)
        (self.base / "GE-Proton11-9").mkdir()
        (self.base / "GE-Proton11-8").symlink_to(self.base / "GE-Proton11-7")
        snapshot = backend.inspect_local(self.config, self.proc)
        self.assertEqual(snapshot["geVersions"], ["GE-Proton11-7", "GE-Proton11-6", "GE-Proton9-20"])
        self.assertEqual(snapshot["currentGeVersion"], "GE-Proton11-7")
        self.assertEqual(len(snapshot["installations"]), 5)
        self.assertEqual(snapshot["installations"][3]["name"], "proton-cachyos-11.0-20261005-slr-x86_64_v3")

    def test_ge_arch_suffix_folder_and_canonical_metadata(self):
        path = installation(self.base, "GE-Proton11-7-x86_64")
        metadata = path / "compatibilitytool.vdf"
        metadata.write_text(metadata.read_text().replace("GE-Proton11-7-x86_64", "GE-Proton11-7"))
        snapshot = backend.inspect_local(self.config, self.proc)
        self.assertEqual(snapshot["geVersions"], ["GE-Proton11-7-x86_64"])
        self.assertEqual(snapshot["installations"][0]["version"], [11, 7, 0])

    def test_missing_selected_ge(self):
        snapshot = backend.inspect_local(self.config, self.proc)
        self.assertIsNone(snapshot["currentGeVersion"])
        self.assertTrue(snapshot["messages"]["selection"])

    def test_unreadable_process_state_blocks(self):
        self.assertTrue(backend.process_blockers(self.root / "missing"))
        pid = self.proc / "123"
        pid.mkdir()
        (pid / "status").write_text("Uid:\t1000\t1000\t1000\t1000\n")
        self.assertTrue(backend.process_blockers(self.proc))

    def test_game_process_not_incidental_argument(self):
        pid = self.proc / "123"
        pid.mkdir()
        (pid / "cmdline").write_bytes(b"grep\0steam\0")
        (pid / "exe").symlink_to("/usr/bin/grep")
        self.assertEqual(backend.process_blockers(self.proc), [])
        (pid / "cmdline").write_bytes(b"/usr/bin/python3\0/usr/bin/umu-run\0game.exe\0")
        self.assertTrue(backend.process_blockers(self.proc))

    def test_package_commands_unavailable(self):
        def missing(*args, **kwargs):
            raise FileNotFoundError("missing")
        self.assertEqual(backend.package_status(missing)["state"], "unavailable")

    def test_executable_evidence_detects_wine_game(self):
        pid = self.proc / "123"
        pid.mkdir()
        (pid / "cmdline").write_bytes(b"game.exe\0")
        (pid / "exe").symlink_to("/usr/bin/wine64")
        self.assertTrue(backend.process_blockers(self.proc))

    def test_other_uid_steam_blocks(self):
        pid = self.proc / "123"
        pid.mkdir()
        (pid / "cmdline").write_bytes(b"steam\0")
        from unittest.mock import patch
        with patch.object(backend.os, "getuid", return_value=987654):
            self.assertTrue(backend.process_blockers(self.proc))

    def test_unavailable_executable_evidence_blocks_relevant_uid(self):
        pid = self.proc / "123"
        pid.mkdir()
        (pid / "cmdline").write_bytes(b"game.exe\0")
        self.assertTrue(backend.process_blockers(self.proc))

    def test_foreign_package_version_not_up_to_date(self):
        def run(command, **kwargs):
            if command[:2] == ["pacman", "-Q"]:
                return backend.subprocess.CompletedProcess(command, 0, "umu-launcher 0.0-foreign\n", "")
            if command[:2] == ["pacman", "-Si"]:
                return backend.subprocess.CompletedProcess(command, 0, "Repository : extra\nName : umu-launcher\nVersion : 1.3.0-1\n", "")
            return backend.subprocess.CompletedProcess(command, 2, "", "")
        self.assertEqual(backend.package_status(run)["state"], "unavailable")

    def test_official_package_evidence_states(self):
        for installed_version, pending, expected in [("1.3.0-1", "", "upToDate"), ("1.2.0-1", "umu-launcher 1.2.0-1 -> 1.3.0-1\n", "updateAvailable"), ("0.0-foreign", "", "unavailable")]:
            def run(command, **kwargs):
                if command[:2] == ["pacman", "-Q"]:
                    return backend.subprocess.CompletedProcess(command, 0, "umu-launcher " + installed_version + "\n", "")
                if command[:2] == ["pacman", "-Si"]:
                    return backend.subprocess.CompletedProcess(command, 0, "Repository : extra\nName : umu-launcher\nVersion : 1.3.0-1\n", "")
                if command[:2] == ["pacman", "-Qm"]:
                    return backend.subprocess.CompletedProcess(command, 0, "", "")
                return backend.subprocess.CompletedProcess(command, 0 if pending else 2, pending, "")
            with self.subTest(version=installed_version):
                self.assertEqual(backend.package_status(run)["state"], expected)


class TransactionTests(unittest.TestCase):
    def setUp(self):
        InventoryTests.setUp(self)
        installation(self.base, "GE-Proton11-7")
        installation(self.base, "GE-Proton11-6")
        self.events = []
        self.release = {"family": "ge", "tag": "GE-Proton11-8", "name": "GE-Proton11-8", "version": [11, 8, 0],
                        "archiveName": "GE-Proton11-8-x86_64.tar.gz", "archiveUrl": "fixture", "checksumUrl": "fixture"}
        self.dependencies = {"proc_root": self.proc, "latest_release": lambda family: self.release,
                             "download_verified": self.download, "package_status": lambda: {"state": "notInstalled", "installedVersion": None, "availableVersion": "1.3", "messages": []}}

    def download(self, release, directory, progress):
        source = directory / "source"
        source.mkdir()
        installation(source, release["name"])
        return Path(shutil.make_archive(str(directory / "archive"), "gztar", root_dir=source))

    def request(self, action, payload=None):
        self.events = []
        backend.dispatch({"id": "test", "action": action, "config": self.config, "payload": payload or {}}, self.events.append, self.dependencies)
        terminals = [event for event in self.events if event["type"] == "result"]
        self.assertEqual(len(terminals), 1)
        return terminals[0]["data"]

    def prepare(self, action="prepareInstall", payload=None):
        result = self.request(action, payload or {"family": "ge"})
        self.assertEqual(result["status"], "success", result)
        return next(event["data"] for event in self.events if event["type"] == "confirmation")

    def test_prepare_does_not_mutate(self):
        before = Path(self.config["umuConfigPath"]).read_bytes()
        self.prepare()
        self.assertEqual(before, Path(self.config["umuConfigPath"]).read_bytes())
        self.assertFalse((self.base / self.release["name"]).exists())

    def test_install_activates_then_updates_umu_then_cleans(self):
        descriptor = self.prepare()
        result = self.request("install", descriptor)
        self.assertEqual(result["status"], "success", result)
        self.assertTrue((self.base / "GE-Proton11-8").exists())
        self.assertFalse((self.base / "GE-Proton11-7").exists())
        self.assertFalse((self.base / "GE-Proton11-6").exists())
        self.assertEqual(result["snapshot"]["currentGeVersion"], "GE-Proton11-8")

    def test_stale_confirmation_refused(self):
        descriptor = self.prepare()
        installation(self.base, "GE-Proton11-5")
        result = self.request("install", descriptor)
        self.assertEqual(result["status"], "error")
        self.assertFalse((self.base / "GE-Proton11-8").exists())

    def test_umu_failure_retains_new_and_old_ge(self):
        Path(self.config["umuConfigPath"]).write_text('umu.proton="/sandbox/GE-Proton11-7"\n')
        descriptor = self.prepare()
        result = self.request("install", descriptor)
        self.assertEqual(result["status"], "partial", result)
        self.assertTrue(all((self.base / name).exists() for name in ["GE-Proton11-6", "GE-Proton11-7", "GE-Proton11-8"]))

    def test_selected_ge_never_removed(self):
        result = self.request("prepareRemove", {"name": "GE-Proton11-7"})
        self.assertEqual(result["status"], "blocked")
        self.assertTrue((self.base / "GE-Proton11-7").exists())

    def test_equivalent_selected_paths_protected(self):
        for path in ["/sandbox/GE-Proton11-7/", "/sandbox/./GE-Proton11-7", "/sandbox/other/../GE-Proton11-7"]:
            Path(self.config["umuConfigPath"]).write_text(f'[umu]\nproton="{path}"\n')
            self.assertEqual(self.request("prepareRemove", {"name": "GE-Proton11-7"})["status"], "blocked")
            self.assertEqual(backend.inspect_local(self.config, self.proc)["currentGeVersion"], "GE-Proton11-7")

    def test_replaced_existing_target_invalidates_confirmation(self):
        target = installation(self.base, "GE-Proton11-8")
        descriptor = self.prepare()
        target.rename(self.base / "retained-original")
        installation(self.base, "GE-Proton11-8")
        self.assertEqual(self.request("install", descriptor)["status"], "error")
        self.assertTrue((self.base / "GE-Proton11-7").exists())

    def test_select_and_sync_rescan_ge(self):
        self.assertEqual(self.request("selectGe", {"name": "GE-Proton11-6"})["snapshot"]["currentGeVersion"], "GE-Proton11-6")
        installation(self.base, "GE-Proton11-9")
        result = self.request("syncGe")
        self.assertEqual(result["status"], "success", result)
        self.assertEqual(result["snapshot"]["currentGeVersion"], "GE-Proton11-9")
        self.assertIn("GE-Proton11-9", result["snapshot"]["geVersions"])

    def test_process_starts_before_commit(self):
        descriptor = self.prepare()
        original = self.download
        def download(*args):
            result = original(*args)
            pid = self.proc / "123"
            pid.mkdir()
            (pid / "cmdline").write_bytes(b"steam\0")
            return result
        self.dependencies["download_verified"] = download
        self.assertEqual(self.request("install", descriptor)["status"], "blocked")
        self.assertFalse((self.base / "GE-Proton11-8").exists())
        self.assertTrue((self.base / "GE-Proton11-7").exists())

    def test_cleanup_never_deletes_newer_or_unknown(self):
        installation(self.base, "GE-Proton11-9")
        installation(self.base, "unknown")
        descriptor = self.prepare()
        result = self.request("install", descriptor)
        self.assertEqual(result["status"], "success", result)
        self.assertTrue((self.base / "GE-Proton11-9").exists())
        self.assertTrue((self.base / "unknown").exists())

    def test_interrupted_staging_not_inventory(self):
        (self.base / ".proton-stage-interrupted").mkdir()
        self.assertNotIn(".proton-stage-interrupted", [item["name"] for item in backend.inspect_local(self.config, self.proc)["installations"]])

    def test_remove_confirmed_version(self):
        descriptor = self.prepare("prepareRemove", {"name": "GE-Proton11-6"})
        self.assertEqual(self.request("remove", descriptor)["status"], "success")
        self.assertFalse((self.base / "GE-Proton11-6").exists())

    def test_protocol_has_one_terminal_result(self):
        self.assertEqual(self.request("invalid")["status"], "error")

    def test_cachyos_does_not_change_umu(self):
        self.release = {**self.release, "family": "cachyos", "name": "proton-cachyos-11.0-20261005-slr-x86_64_v3", "version": [20261005, 11, 0]}
        before = Path(self.config["umuConfigPath"]).read_bytes()
        descriptor = self.prepare(payload={"family": "cachyos"})
        self.assertEqual(self.request("install", descriptor)["status"], "success")
        self.assertEqual(Path(self.config["umuConfigPath"]).read_bytes(), before)
        self.assertTrue((self.base / "GE-Proton11-7").exists())

    def test_process_starts_before_each_removal(self):
        descriptor = self.prepare()
        original = backend.storage.remove_installation
        def remove(*args):
            original(*args)
            pid = self.proc / "123"
            pid.mkdir()
            (pid / "cmdline").write_bytes(b"wine\0")
        from unittest.mock import patch
        with patch.object(backend.storage, "remove_installation", remove):
            result = self.request("install", descriptor)
        self.assertEqual(result["status"], "partial")
        self.assertTrue((self.base / "GE-Proton11-6").exists())
        self.assertTrue((self.base / "GE-Proton11-8").exists())

    def test_cleanup_failure_preserves_success(self):
        descriptor = self.prepare()
        from unittest.mock import patch
        with patch.object(backend.storage, "remove_installation", side_effect=PermissionError("denied")):
            result = self.request("install", descriptor)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["snapshot"]["currentGeVersion"], "GE-Proton11-8")
        self.assertTrue((self.base / "GE-Proton11-7").exists())

    def test_lock_serializes_mutations(self):
        descriptor = self.prepare()
        with backend.storage.operation_lock(self.base):
            self.assertEqual(self.request("install", descriptor)["status"], "error")
        self.assertFalse((self.base / "GE-Proton11-8").exists())

    def test_cachyos_selected_by_umu_cannot_be_removed(self):
        name = "proton-cachyos-11.0-20261005-slr-x86_64_v3"
        installation(self.base, name)
        Path(self.config["umuConfigPath"]).write_text(f'[umu]\nproton="/sandbox/{name}"\n')
        self.assertEqual(self.request("prepareRemove", {"name": name})["status"], "blocked")


if __name__ == "__main__":
    unittest.main()
