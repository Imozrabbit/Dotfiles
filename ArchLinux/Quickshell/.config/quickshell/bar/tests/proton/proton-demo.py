"""Create retained, private dummy gaming files for manual UI/backend testing."""
import hashlib
import json
import shutil
import sys
import tarfile
import tempfile
from pathlib import Path

from proton_fixtures import configuration, installation


def create_fixture():
    root = Path(tempfile.mkdtemp(prefix="proton-demo-", dir="/tmp/opencode"))
    config = configuration(root)
    config["sandboxCompatibilityToolsDir"] = str(root / "sandbox" / "compatibilitytools.d")
    Path(config["umuConfigPath"]).write_text(f'# Dummy configuration, not your launcher\n[umu]\nproton = "{config["sandboxCompatibilityToolsDir"]}/GE-Proton11-7"\nexe = "dummy-game.exe"\n[keep]\nvalue = 42\n')
    base = Path(config["compatibilityToolsDir"])
    for name in ["GE-Proton11-7", "GE-Proton11-6", "proton-cachyos-20260928-slr-x86_64_v3", "unknown-folder"]:
        installation(base, name)
    (root / "proc").mkdir()
    (root / "archives").mkdir()
    for family, name, suffix, repo, tag in [
        ("ge", "GE-Proton11-8", "-x86_64.tar.gz", "GloriousEggroll/proton-ge-custom", "GE-Proton11-8"),
        ("cachyos", "proton-cachyos-11.0-20261005-slr-x86_64_v3", ".tar.xz", "CachyOS/proton-cachyos", "cachyos-11.0-20261005-slr")
    ]:
        with tempfile.TemporaryDirectory(prefix="proton-build-", dir=root) as build:
            tool = installation(build, name)
            archive_name = name + suffix
            archive_path = root / "archives" / archive_name
            with tarfile.open(archive_path, "w:gz" if family == "ge" else "w:xz") as archive:
                archive.add(tool, arcname=name)
        checksum_name = archive_name.removesuffix(".tar.gz").removesuffix(".tar.xz") + ".sha512sum"
        (root / "archives" / checksum_name).write_text(hashlib.sha512(archive_path.read_bytes()).hexdigest() + "  " + archive_name + "\n")
        metadata = {"tag_name": tag, "assets": [{"name": asset, "browser_download_url": f"https://github.com/{repo}/releases/download/{tag}/{asset}"} for asset in (archive_name, checksum_name)]}
        (root / (family + "-release.json")).write_text(json.dumps(metadata))
    (root / "config.json").write_text(json.dumps(config, indent=2))
    (root / ".proton-fixture.json").write_text(json.dumps({"schema": 1, "config": config}))
    (root / "scenario.json").write_text(json.dumps({"blocked": False, "badChecksum": False, "packageUnavailable": False}, indent=2))
    # Quickshell rejects imports outside its config root; stage real files, not symlinks.
    tests = Path(__file__).resolve().parent
    demo = root / "demo"
    demo.mkdir()
    shutil.copyfile(tests / "proton-demo" / "shell.qml", demo / "shell.qml")
    (demo / "core").mkdir()
    shutil.copyfile(tests.parent.parent / "core" / "Theme.qml", demo / "core" / "Theme.qml")
    shutil.copytree(tests.parent.parent / "proton", demo / "proton", ignore=shutil.ignore_patterns("__pycache__"))
    (demo / "tests" / "proton").mkdir(parents=True)
    shutil.copyfile(tests / "proton_demo_backend.py", demo / "tests" / "proton" / "proton_demo_backend.py")
    return root


if __name__ == "__main__":
    root = create_fixture()
    demo = root / "demo"
    print(f"Dummy files: {root}\n")
    print(f"PROTON_FIXTURE_ROOT='{root}' quickshell -p '{demo}'")
    print("\nOnly dummy files change. Escape closes demo. Run this script again for fresh fixtures.")
