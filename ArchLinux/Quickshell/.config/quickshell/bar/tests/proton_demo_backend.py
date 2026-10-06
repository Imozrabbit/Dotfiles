"""Fixture adapter: same production transactions, no network/package/real proc calls."""
import argparse
import io
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "proton"))
import backend
import releases
import storage


def fixture_dependencies(config):
    config = backend.validate_config(config)
    root = Path(config["compatibilityToolsDir"]).parent
    approved = Path("/tmp/opencode").resolve()
    storage.real_directory(root)
    if not root.resolve().is_relative_to(approved) or not root.name.startswith("proton-demo-"):
        raise ValueError("Demo refuses non-fixture paths")
    marker = json.loads(storage.read_regular(root / ".proton-fixture.json"))
    if marker != {"schema": 1, "config": config} or any(not Path(path).resolve().is_relative_to(root.resolve()) for path in config.values()):
        raise ValueError("Demo configuration/marker mismatch")
    scenario = json.loads(storage.read_regular(root / "scenario.json"))
    if not isinstance(scenario, dict):
        raise ValueError("Invalid fixture scenario")
    proc = root / "proc"
    blocker = proc / "99999"
    if scenario.get("blocked"):
        blocker.mkdir(exist_ok=True)
        (blocker / "cmdline").write_bytes(b"steam\0")
    elif blocker.exists():
        (blocker / "cmdline").unlink(missing_ok=True)
        blocker.rmdir()

    def latest(family):
        if family not in releases.REPOS:
            raise ValueError("Unsupported fixture family")
        return releases.select_release(family, json.loads(storage.read_regular(root / (family + "-release.json"))))

    def download(release, destination, progress):
        def fetch(url):
            filename = release["archiveName"] if url == release["archiveUrl"] else release["checksumUrl"].rsplit("/", 1)[1]
            content = storage.read_regular(root / "archives" / filename, 4 * 1024 * 1024)
            if scenario.get("badChecksum") and url == release["archiveUrl"]:
                content += b"corrupted fixture"
            return io.BytesIO(content)
        return releases.download_verified(release, destination, progress, fetch)

    def package():
        return {"state": "unavailable" if scenario.get("packageUnavailable") else "notInstalled", "installedVersion": None,
                "availableVersion": None if scenario.get("packageUnavailable") else "1.3.0-1",
                "messages": [backend.message("Fixture package check unavailable.")] if scenario.get("packageUnavailable") else []}

    return {"proc_root": proc, "latest_release": latest, "download_verified": download, "package_status": package}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    args = parser.parse_args()
    emit = lambda event: print(json.dumps(event, separators=(",", ":")), flush=True)
    try:
        if len(args.request) > 512 * 1024:
            raise ValueError("Fixture request too large")
        request = json.loads(args.request)
        dependencies = fixture_dependencies(request["config"])
    except Exception as error:
        emit({"id": "invalid", "type": "result", "data": {"status": "error", "area": "updates", "messages": [backend.message(error)], "snapshot": None}})
        sys.exit(1)
    backend.dispatch(request, emit, dependencies)
