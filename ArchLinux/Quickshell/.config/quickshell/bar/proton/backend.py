"""On-demand Proton/umu helper. stdout is reserved for NDJSON events."""
import os
import re
import subprocess
import tempfile
import tomllib
import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

import storage
import releases

CONFIG_KEYS = ("compatibilityToolsDir", "umuConfigPath", "sandboxCompatibilityToolsDir")


def message(text, severity="error"):
    return {"severity": severity, "text": str(text)[:1000]}


def validate_config(value):
    if not isinstance(value, dict) or set(value) != set(CONFIG_KEYS):
        raise ValueError("Invalid Proton configuration fields")
    for path in value.values():
        if not isinstance(path, str) or len(path) > 4096 or not path.startswith("/") or path == "/" or "\0" in path or ".." in path.split("/"):
            raise ValueError("Proton paths must be absolute, non-root paths")
    return dict(value)


def installation_identity(path):
    return storage.validate_installation(path)["identity"]


def systemd_user_session(pid, args, uid):
    """Recognize the user manager and its direct PAM helper when exe access is denied."""
    try:
        comm = (pid / "comm").read_text().strip()
        parent = re.search(r"^PPid:\s*(\d+)\s*$", (pid / "status").read_text(), re.M)
        if parent is None:
            return False
        manager_args = ["/usr/lib/systemd/systemd", "--user"]
        if args[:2] == manager_args:
            return (comm == "systemd" and parent.group(1) == "1"
                    and (len(args) == 2 or len(args) == 3 and re.fullmatch(r"--deserialize=\d+", args[2]) is not None))
        if args == ["(sd-pam)"] and comm == "(sd-pam)":
            manager = pid.parent / parent.group(1)
            parent_args = [part.decode("utf-8", "replace") for part in (manager / "cmdline").read_bytes()[:65536].split(b"\0") if part]
            return (manager.stat().st_uid == uid and parent_args[:2] == manager_args
                    and systemd_user_session(manager, parent_args, uid))
    except (OSError, UnicodeError):
        pass
    return False


def process_blockers(proc_root=Path("/proc"), relevant_uids=None):
    blockers = []
    relevant_uids = {os.getuid(), *(relevant_uids or [])}
    try:
        pids = list(Path(proc_root).iterdir())
    except OSError:
        return ["Running-process state unavailable; operations blocked."]
    names = {"steam", "steamwebhelper", "umu-run", "umu-launcher", "proton", "wine", "wine64", "wine-preloader", "wine64-preloader", "wineserver"}
    for pid in pids:
        if not pid.name.isdigit():
            continue
        try:
            uid = pid.stat().st_uid
            argv = (pid / "cmdline").read_bytes()[:65536].split(b"\0")
            args = [argument.decode("utf-8", "replace") for argument in argv if argument]
            if not args:
                continue
            executable = Path(args[0]).name
            script = Path(args[1]).name if len(args) > 1 and re.fullmatch(r"python(?:\d+(?:\.\d+)?)?|(?:ba|z|da)?sh", executable) else ""
            if executable in names or script in names or executable.startswith("python") and args[1:3] == ["-m", "umu"]:
                blockers.append(f"{executable if executable in names else script or 'umu'} is running; close it to continue.")
                continue
            try:
                actual = Path(os.readlink(pid / "exe")).name.removesuffix(" (deleted)")
                if actual in names:
                    blockers.append(f"{actual} is running; close it to continue.")
            except OSError as error:
                if uid in relevant_uids and pid.exists():
                    # systemd's protected user/PAM processes are not active games.
                    # Keep failing closed for unknown processes and non-permission errors.
                    if isinstance(error, PermissionError) and systemd_user_session(pid, args, uid):
                        continue
                    blockers.append("Relevant executable state unavailable; operations blocked.")
        except FileNotFoundError:
            if pid.exists():
                blockers.append("Running-process state incomplete; operations blocked.")
        except OSError:
            blockers.append("Running-process state unavailable; operations blocked.")
    return sorted(set(blockers))


def package_status(run=subprocess.run):
    result = {"state": "unavailable", "installedVersion": None, "availableVersion": None, "messages": []}
    try:
        environment = {**os.environ, "LC_ALL": "C"}
        installed = run(["pacman", "-Q", "umu-launcher"], env=environment, capture_output=True, text=True, timeout=15)
        official = run(["pacman", "-Si", "umu-launcher"], env=environment, capture_output=True, text=True, timeout=15)
        if official.returncode != 0:
            raise ValueError("Official Arch umu-launcher package metadata unavailable.")
        version = re.search(r"^Version\s*:\s*(\S+)\s*$", official.stdout, re.M)
        if not version:
            raise ValueError("Invalid official package metadata.")
        if not re.search(r"^Repository\s*:\s*(?:core|extra|multilib)\s*$", official.stdout, re.M) or not re.search(r"^Name\s*:\s*umu-launcher\s*$", official.stdout, re.M):
            raise ValueError("Official Arch package identity unavailable.")
        if installed.returncode == 1 and "was not found" in installed.stderr:
            result.update(state="notInstalled", availableVersion=version.group(1))
            return result
        fields = installed.stdout.split()
        if installed.returncode != 0 or len(fields) != 2 or fields[0] != "umu-launcher":
            raise ValueError("Installed umu-launcher status unavailable.")
        result["installedVersion"] = fields[1]
        foreign = run(["pacman", "-Qm", "umu-launcher"], env=environment, capture_output=True, text=True, timeout=15)
        if foreign.returncode not in (0, 1) or foreign.stdout.strip() or foreign.stderr.strip():
            raise ValueError("Installed package provenance unavailable or foreign.")
        with tempfile.TemporaryDirectory(prefix="proton-checkupdates-") as db:
            checked = run(["checkupdates"], env={**os.environ, "LC_ALL": "C", "CHECKUPDATES_DB": db}, capture_output=True, text=True, timeout=90)
        if checked.returncode not in (0, 2) or len(checked.stdout) > 8 * 1024 * 1024:
            raise ValueError("Update status unavailable: checkupdates failed.")
        pending = [line.split() for line in checked.stdout.splitlines() if line.split()[:1] == ["umu-launcher"]]
        if pending:
            if len(pending) != 1 or len(pending[0]) != 4 or pending[0][2] != "->" or pending[0][1] != fields[1]:
                raise ValueError("Invalid umu-launcher update evidence.")
            result.update(state="updateAvailable", availableVersion=pending[0][3])
        else:
            if fields[1] != version.group(1):
                raise ValueError("Installed and official package versions disagree; status unavailable.")
            result.update(state="upToDate", availableVersion=fields[1])
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        result["messages"] = [message(error)]
    return result


def inspect_local(config, proc_root=Path("/proc")):
    config = validate_config(config)
    base = Path(config["compatibilityToolsDir"])
    messages = {area: [] for area in ("updates", "installed", "package", "selection")}
    installations = []
    try:
        if base.is_symlink():
            raise ValueError("Compatibility directory must not be a symlink.")
        for path in base.iterdir():
            try:
                installations.append(storage.validate_installation(path))
            except (OSError, ValueError, KeyError, UnicodeError):
                continue
    except (OSError, ValueError) as error:
        messages["installed"].append(message(f"Installation directory unavailable: {error}"))
    installations.sort(key=lambda item: (item["family"] != "ge", tuple(-part for part in item["version"])))
    current = None
    selected_name = None
    try:
        data = tomllib.loads(storage.read_regular(config["umuConfigPath"]).decode("utf-8"))
        selected = data.get("umu", {}).get("proton")
        if not isinstance(selected, str):
            raise ValueError("[umu].proton is missing or not a string.")
        choices = {normalize_selection(str(Path(config["sandboxCompatibilityToolsDir"]) / item["name"])): item for item in installations}
        selected_item = choices.get(normalize_selection(selected))
        selected_name = selected_item["name"] if selected_item else None
        current = selected_name if selected_item and selected_item["family"] == "ge" else None
        if current is None:
            messages["selection"].append(message(f"Selected Proton missing or not managed GE: {selected}"))
    except (OSError, ValueError, UnicodeError, AttributeError) as error:
        messages["selection"].append(message(f"umu configuration unavailable: {error}"))
    for item in installations:
        item["umuSelected"] = item["name"] == selected_name
    ge = [item["name"] for item in installations if item["family"] == "ge"]
    if not ge:
        messages["selection"].append(message("No installed GE versions available.", "info"))
    return {"installations": installations, "geVersions": ge, "currentGeVersion": current,
            "releases": {}, "package": {"state": "unavailable", "installedVersion": None, "availableVersion": None, "messages": []},
            "blockers": process_blockers(proc_root, relevant_uids(config)), "locations": config, "messages": messages}


class Blocked(ValueError):
    pass


def relevant_uids(config):
    return {Path(config[key]).stat().st_uid for key in ("compatibilityToolsDir", "umuConfigPath") if Path(config[key]).exists()}


def ensure_idle(proc_root=Path("/proc"), config=None):
    blockers = process_blockers(proc_root, relevant_uids(config) if config else None)
    if blockers:
        raise Blocked("\n".join(blockers))


def config_digest(config):
    try:
        return hashlib.sha256(storage.read_regular(config["umuConfigPath"])).hexdigest()
    except FileNotFoundError:
        return None


def selected_path(config):
    data = tomllib.loads(storage.read_regular(config["umuConfigPath"]).decode("utf-8"))
    value = data.get("umu", {}).get("proton")
    if not isinstance(value, str):
        raise ValueError("umu selection unavailable; cannot safely remove versions.")
    return normalize_selection(value)


def normalize_selection(value):
    if not isinstance(value, str) or not value.startswith("/") or "\0" in value:
        raise ValueError("umu selection must be an absolute path for safe management.")
    return "/" + os.path.normpath(value).lstrip("/")


def prepare_confirmation(config, action, target, snapshot):
    storage.real_directory(config["compatibilityToolsDir"])
    if action == "install":
        release = snapshot["releases"].get(target)
        if not isinstance(release, dict):
            raise ValueError("Release unavailable; refresh first.")
        cleanup = [item for item in snapshot["installations"] if item["family"] == target and item["version"] < release["version"]]
        chosen = release
    elif action == "remove":
        chosen = next((item for item in snapshot["installations"] if item["name"] == target), None)
        if chosen is None:
            raise ValueError("Selected installation unavailable.")
        if selected_path(config) == normalize_selection(str(Path(config["sandboxCompatibilityToolsDir"]) / target)):
            raise Blocked("Cannot remove selected umu Proton; choose another version first.")
        cleanup = []
    else:
        raise ValueError("Unsupported confirmation action")
    descriptor = {"action": action, "target": chosen, "cleanupCandidates": cleanup}
    base = Path(config["compatibilityToolsDir"]).stat()
    existing = next((item for item in snapshot["installations"] if item["name"] == chosen["name"]), None) if action == "install" else None
    evidence = {"descriptor": descriptor, "config": config, "umuDigest": config_digest(config), "existingTarget": existing,
                "base": [base.st_dev, base.st_ino]}
    descriptor["fingerprint"] = hashlib.sha256(json.dumps(evidence, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return descriptor


def dispatch(request, emit, dependencies=None):
    dependencies = dependencies or {}
    identifier = request.get("id", "invalid") if isinstance(request, dict) else "invalid"
    if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,100}", identifier):
        identifier = "invalid"
    proc_root = dependencies.get("proc_root", Path("/proc"))
    latest = dependencies.get("latest_release", releases.latest_release)
    download = dependencies.get("download_verified", releases.download_verified)
    snapshot = None
    status, area, messages = "success", "updates", []
    activated = False
    config = None

    def event(kind, data):
        emit({"id": identifier, "type": kind, "data": data})

    def local():
        fresh = inspect_local(config, proc_root)
        if snapshot:
            fresh["releases"] = snapshot["releases"]
            fresh["package"] = snapshot["package"]
            fresh["messages"]["updates"] = snapshot["messages"]["updates"]
        return fresh

    def refresh_release(family):
        snapshot["releases"][family] = latest(family)

    def idle():
        ensure_idle(proc_root, config)

    def progress(stage):
        event("progress", {"stage": stage, "fraction": None, "downloadedBytes": 0, "totalBytes": None})

    try:
        if not isinstance(request, dict) or set(request) != {"id", "action", "config", "payload"} or identifier != request["id"]:
            raise ValueError("Invalid helper request")
        config = validate_config(request["config"])
        action, payload = request["action"], request["payload"]
        if not isinstance(payload, dict) or len(json.dumps(request)) > 512 * 1024:
            raise ValueError("Invalid operation payload")
        if action not in {"inspect", "refresh", "prepareInstall", "prepareRemove", "install", "remove", "selectGe", "syncGe"}:
            raise ValueError("Unsupported operation")
        area = "installed" if action in {"prepareRemove", "remove"} else "selection" if action in {"selectGe", "syncGe"} else "updates"
        snapshot = local()
        event("snapshot", snapshot)
        if action == "refresh":
            progress("Checking releases")
            for family in ("ge", "cachyos"):
                try:
                    refresh_release(family)
                except Exception as error:
                    snapshot["messages"]["updates"].append(message(f"{family}: {error}"))
            snapshot["package"] = dependencies.get("package_status", package_status)()
        elif action in {"prepareInstall", "prepareRemove"}:
            idle()
            if action == "prepareInstall":
                family = payload.get("family")
                if family not in releases.REPOS:
                    raise ValueError("Unsupported family")
                refresh_release(family)
                descriptor = prepare_confirmation(config, "install", family, snapshot)
            else:
                descriptor = prepare_confirmation(config, "remove", payload.get("name"), snapshot)
            event("confirmation", descriptor)
        elif action in {"install", "remove", "selectGe", "syncGe"}:
            with storage.operation_lock(Path(config["compatibilityToolsDir"])):
                idle()
                snapshot = local()
                if action in {"install", "remove"}:
                    if payload.get("action") != action or not isinstance(payload.get("target"), dict):
                        raise ValueError("Invalid confirmed operation")
                    target = payload["target"]
                    if action == "install":
                        family = target.get("family")
                        refresh_release(family)
                        expected = prepare_confirmation(config, action, family, snapshot)
                    else:
                        expected = prepare_confirmation(config, action, target.get("name"), snapshot)
                    if payload != expected:
                        raise ValueError("Release, installation or configuration changed; confirm again.")
                if action in {"selectGe", "syncGe"}:
                    name = snapshot["geVersions"][0] if action == "syncGe" and snapshot["geVersions"] else payload.get("name")
                    if name not in snapshot["geVersions"]:
                        raise ValueError("No valid selected GE installation available.")
                    digest = config_digest(config)
                    progress("Updating umu")
                    idle()
                    storage.validate_installation(Path(config["compatibilityToolsDir"]) / name)
                    storage.write_umu_selection(Path(config["umuConfigPath"]), str(Path(config["sandboxCompatibilityToolsDir"]) / name), digest)
                    messages = [message("umu Proton path updated to " + name + ".", "success")]
                elif action == "remove":
                    idle()
                    if selected_path(config) == normalize_selection(str(Path(config["sandboxCompatibilityToolsDir"]) / target["name"])):
                        raise Blocked("Selected umu Proton cannot be removed.")
                    storage.remove_installation(Path(config["compatibilityToolsDir"]), target["name"], target["identity"])
                    messages = [message("Removed " + target["name"] + ".", "success")]
                else:
                    base = Path(config["compatibilityToolsDir"])
                    digest = config_digest(config)
                    existing = next((item for item in snapshot["installations"] if item["name"] == target["name"]), None)
                    if existing is None:
                        stage = Path(tempfile.mkdtemp(prefix=".proton-stage-", dir=base))
                        try:
                            archive = download(target, stage, lambda data: event("progress", data))
                            progress("Extracting archive")
                            staged = storage.extract_verified(archive, stage / "extracted")
                            archive_family, archive_version = storage.version_info(staged.name)
                            if archive_family != target["family"] or archive_version != target["version"]:
                                raise ValueError("Archive root does not match selected release version")
                            if staged.name != target["name"]:
                                normalized = staged.parent / target["name"]
                                if normalized.exists():
                                    raise ValueError("Normalized archive root already exists")
                                staged.rename(normalized)
                                staged = normalized
                            # Revalidate original confirmation after slow download/extraction.
                            refreshed = local()
                            if prepare_confirmation(config, "install", target["family"], refreshed) != expected:
                                raise ValueError("State changed during download; confirm again.")
                            idle()
                            progress("Installing " + target["name"])
                            storage.activate(staged, base, target["name"])
                            activated = True
                        finally:
                            shutil.rmtree(stage)
                    else:
                        activated = True
                    if target["family"] == "ge":
                        progress("Updating umu")
                        idle()
                        storage.write_umu_selection(Path(config["umuConfigPath"]), str(Path(config["sandboxCompatibilityToolsDir"]) / target["name"]), digest)
                    progress("Cleaning old versions")
                    removed = 0
                    for candidate in expected["cleanupCandidates"]:
                        idle()
                        if selected_path(config) == normalize_selection(str(Path(config["sandboxCompatibilityToolsDir"]) / candidate["name"])):
                            raise Blocked("Cleanup would remove selected umu Proton; older versions retained.")
                        storage.remove_installation(base, candidate["name"], candidate["identity"])
                        removed += 1
                    messages = [message(f"Complete: {target['name']} installed. Removed {removed} older versions.", "success")]
        snapshot = local()
    except Exception as error:
        status = "partial" if activated else "blocked" if isinstance(error, Blocked) else "error"
        messages = [message(("Partial success: installation retained; " if activated else "") + str(error), "warning" if status in {"partial", "blocked"} else "error")]
        if config is not None:
            try:
                snapshot = local()
            except Exception:
                pass
    if snapshot is not None:
        event("snapshot", snapshot)
    event("result", {"status": status, "area": area, "messages": messages, "snapshot": snapshot})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    args = parser.parse_args()
    try:
        if len(args.request) > 512 * 1024:
            raise ValueError("Request exceeds size limit")
        request = json.loads(args.request)
    except ValueError as error:
        request = None
    dispatch(request, lambda event: print(json.dumps(event, separators=(",", ":")), flush=True))


if __name__ == "__main__":
    main()
