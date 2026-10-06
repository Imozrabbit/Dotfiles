import importlib.util
import json
import os
import shutil
import subprocess
import unittest
from pathlib import Path


class DemoTests(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).parent / "proton-demo.py"
        spec = importlib.util.spec_from_file_location("proton_demo", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.root = module.create_fixture()
        self.addCleanup(shutil.rmtree, self.root)
        self.config = json.loads((self.root / "config.json").read_text())

    def request(self, action, payload=None):
        request = {"id": "fixture", "action": action, "config": self.config, "payload": payload or {}}
        result = subprocess.run(["python3", str(Path(__file__).parent / "proton_demo_backend.py"), "--request", json.dumps(request)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        events = [json.loads(line) for line in result.stdout.splitlines()]
        return events, next(event["data"] for event in events if event["type"] == "result")

    def test_dummy_install_uses_real_checksum_and_transactions(self):
        events, result = self.request("prepareInstall", {"family": "ge"})
        descriptor = next(event["data"] for event in events if event["type"] == "confirmation")
        _, result = self.request("install", descriptor)
        self.assertEqual(result["status"], "success", result)
        base = Path(self.config["compatibilityToolsDir"])
        self.assertTrue((base / "GE-Proton11-8" / "proton").exists())
        self.assertFalse((base / "GE-Proton11-6").exists())
        self.assertTrue((base / "unknown-folder").exists())
        self.assertIn("value = 42", Path(self.config["umuConfigPath"]).read_text())

    def test_dummy_scenarios(self):
        scenario = self.root / "scenario.json"
        scenario.write_text('{"badChecksum":true}')
        events, _ = self.request("prepareInstall", {"family": "ge"})
        descriptor = next(event["data"] for event in events if event["type"] == "confirmation")
        _, result = self.request("install", descriptor)
        self.assertEqual(result["status"], "error")
        self.assertFalse((Path(self.config["compatibilityToolsDir"]) / "GE-Proton11-8").exists())
        scenario.write_text('{"blocked":true,"packageUnavailable":true}')
        _, result = self.request("refresh")
        self.assertTrue(result["snapshot"]["blockers"])
        self.assertEqual(result["snapshot"]["package"]["state"], "unavailable")

    def test_fixture_refuses_non_fixture_configuration(self):
        self.config["umuConfigPath"] = "/not-a-fixture/umu.toml"
        request = {"id": "fixture", "action": "syncGe", "config": self.config, "payload": {}}
        result = subprocess.run(["python3", str(Path(__file__).parent / "proton_demo_backend.py"), "--request", json.dumps(request)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn("mismatch", result.stdout)

    def test_quickshell_demo_imports_and_fixture_helper(self):
        demo = self.root / "demo"
        demo.mkdir(exist_ok=True)
        shell = demo / "shell.qml"
        if not shell.exists():
            shutil.copyfile(Path(__file__).parent / "proton-demo" / "shell.qml", shell)
        manager = demo / "proton" / "Manager.qml"
        if manager.exists():
            # Offscreen Quickshell has no layer-shell backend; keep real UI, replace window only.
            source = manager.read_text().replace('PanelWindow {', 'Rectangle {')
            source = source.replace('    focusable: true', '    property var screen: null')
            source = source.replace('    anchors { top: true; bottom: true; left: true; right: true }', '')
            source = '\n'.join(line for line in source.split('\n') if not line.strip().startswith('WlrLayershell.'))
            manager.write_text(source)
        source = shell.read_text().replace('    property var config: null', '''
    Component.onCompleted: {
        const manager = Qt.createComponent(Quickshell.shellPath("proton/Manager.qml"));
        if (manager.status !== Component.Ready) {
            console.error("DEMO FAIL", manager.errorString()); Qt.exit(1);
        }
    }
    Connections {
        target: serviceLoader
        function onItemChanged() {
            if (serviceLoader.item) Qt.callLater(function() { serviceLoader.item.refresh(); });
        }
    }
    Connections {
        target: serviceLoader.item
        function onBusyChanged() {
            const service = serviceLoader.item;
            if (service.busy) return;
            if (!service.snapshot || service.snapshot.currentGeVersion !== "GE-Proton11-7"
                || service.snapshot.package.state !== "notInstalled"
                || service.snapshot.releases.ge.name !== "GE-Proton11-8") {
                console.error("DEMO FAIL fixture helper", JSON.stringify(service.messages)); Qt.exit(1); return;
            }
            console.log("DEMO PASS imports and fixture helper"); Qt.quit();
        }
    }
    Timer { interval: 5000; running: true; onTriggered: Qt.exit(1) }
    property var config: null''')
        shell.write_text(source)
        runtime = self.root / "runtime"
        runtime.mkdir(mode=0o700)
        result = subprocess.run(["quickshell", "-p", str(demo), "--no-color"], capture_output=True, text=True, timeout=10,
            env={**os.environ, "PROTON_FIXTURE_ROOT": str(self.root), "QT_QPA_PLATFORM": "offscreen",
                 "QT_QUICK_BACKEND": "software", "XDG_RUNTIME_DIR": str(runtime),
                 "XDG_CACHE_HOME": str(self.root / "cache"), "XDG_STATE_HOME": str(self.root / "state")})
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertNotIn("outside of the config folder", output)
        self.assertNotIn("Failed to load", output)
        self.assertIn("DEMO PASS imports and fixture helper", output)


if __name__ == "__main__":
    unittest.main()
