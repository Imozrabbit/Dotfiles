#!/usr/bin/env python3
"""Backend for root install/update entrypoints. Never compile or configure accounts."""
import argparse
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import resource
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

# -I excludes the script directory. Import only this explicitly selected sibling.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_archive import (MAX_ARCHIVE, REQUIRED, discover_release, download, extract_release,
                             read_owned, require, runtime_member, version_key)


def run(args, *, env=None, input=None, timeout=30, interactive=False):
    try:
        process = subprocess.run(list(map(str, args)), env=env, input=input, text=True,
                                 stdout=None if interactive else subprocess.PIPE,
                                 stderr=None if interactive else subprocess.DEVNULL, timeout=timeout, check=True)
    except (subprocess.SubprocessError, OSError) as error:
        raise ValueError("Calendar command failed: " + Path(args[0]).name) from error
    output = process.stdout or ""
    require(len(output) <= 4 * 1024 * 1024, "Calendar command output exceeded its limit.")
    return output


def confirm(message):
    try:
        return input(message + " [y/N] ").strip().lower() in ("y", "yes")
    except EOFError:
        return False


def present(path):
    return os.path.lexists(path)


def directory(path, create=False):
    for ancestor in reversed((path, *path.parents)):
        if not present(ancestor):
            require(create, "Required Calendar directory is missing: " + str(ancestor))
            ancestor.mkdir(mode=0o700)
        stamp = ancestor.lstat()
        require(stat.S_ISDIR(stamp.st_mode) and stamp.st_uid in (0, os.getuid())
                and (not stamp.st_mode & 0o022 or stamp.st_mode & stat.S_ISVTX),
                "Calendar directory is linked, writable by others or not owned safely: " + str(ancestor))
    require(path.stat().st_uid == os.getuid(), "Calendar directory must belong to this user: " + str(path))


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def atomic_write(path, data, *, previous=None, mode=0o600, uid=None, gid=None):
    directory(path.parent, create=True)
    stamp = path.lstat() if present(path) else None
    require((read_owned(path, 8 * 1024 * 1024) if stamp else None) == previous, "Calendar output changed; nothing overwritten: " + str(path))
    descriptor, temporary = tempfile.mkstemp(prefix=".calendar-write-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            os.fchown(stream.fileno(), uid if uid is not None else (stamp.st_uid if stamp else os.getuid()),
                      gid if gid is not None else (stamp.st_gid if stamp else os.getgid()))
            os.fchmod(stream.fileno(), stat.S_IMODE(stamp.st_mode) if stamp else mode)
            stream.flush()
            os.fsync(stream.fileno())
        require((read_owned(path, 8 * 1024 * 1024) if present(path) else None) == previous, "Calendar output changed during publication.")
        if previous is None:
            os.link(temporary, path, follow_symlinks=False)  # Atomic create, never overwrite.
            os.unlink(temporary)
        else:
            os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        if present(Path(temporary)):
            os.unlink(temporary)


def write_json(path, value):
    previous = read_owned(path, 8 * 1024 * 1024) if present(path) else None
    atomic_write(path, (json.dumps(value, sort_keys=True, indent=2) + "\n").encode(), previous=previous)


def read_json(path):
    value = json.loads(read_owned(path, 8 * 1024 * 1024))
    require(isinstance(value, dict), "Calendar receipt is malformed.")
    return value


def move(source, destination):
    # Linux's no-replace rename closes the check/rename race without replacing an
    # empty directory somebody else created. Both paths stay on one filesystem.
    rename = ctypes.CDLL(None, use_errno=True).renameat2
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(-100, os.fsencode(source), -100, os.fsencode(destination), 1) != 0:
        raise OSError(ctypes.get_errno(), "Could not move Calendar without replacing an existing path")
    sync_directory(source.parent)
    if destination.parent != source.parent:
        sync_directory(destination.parent)


def lock(path, is_directory=False):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW) if is_directory else os.open(
        path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        stamp = os.fstat(descriptor)
        expected = path.lstat()
        require((stat.S_ISDIR(stamp.st_mode) if is_directory else stat.S_ISREG(stamp.st_mode) and stamp.st_nlink == 1)
                and stamp.st_uid == os.getuid() and not stamp.st_mode & 0o022
                and (stamp.st_dev, stamp.st_ino) == (expected.st_dev, expected.st_ino), "Calendar lock path is unsafe.")
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


class Paths:
    def __init__(self):
        home = os.environ.get("HOME", "")
        require(home, "HOME is required.")
        raw = {"HOME": Path(home)}
        for key, fallback in (("XDG_CONFIG_HOME", ".config"), ("XDG_DATA_HOME", ".local/share"),
                              ("XDG_STATE_HOME", ".local/state"), ("XDG_CACHE_HOME", ".cache")):
            raw[key] = Path(os.environ.get(key) or str(raw["HOME"] / fallback))
        if os.environ.get("XDG_RUNTIME_DIR"):
            raw["XDG_RUNTIME_DIR"] = Path(os.environ["XDG_RUNTIME_DIR"])
        for path in raw.values():
            require(path.is_absolute() and str(path) == os.path.normpath(path) and not re.search(r'[\x00-\x1f\x7f"\\%]', str(path)),
                    "Calendar paths must be absolute without traversal, controls, quotes, backslashes or systemd specifiers.")
        self.raw = raw
        self.roots = {key: path.resolve() for key, path in raw.items()}
        self.home = self.roots["HOME"]
        self.config = self.roots["XDG_CONFIG_HOME"]
        self.data = self.roots["XDG_DATA_HOME"] / "calendars"
        self.state_root = self.roots["XDG_STATE_HOME"] / "quickshell-calendar"
        self.state = self.state_root / "installer"
        self.units = self.config / "systemd/user"
        self.alias = raw["HOME"] / ".config/quickshell"
        self.parent = self.alias.resolve()
        self.target = self.parent / "calendar"
        self.launch_path = self.alias / "calendar"
        self.installed = self.state / "installed.json"
        self.pending = self.state / "pending.json"
        self.shared_lock = self.roots.get("XDG_RUNTIME_DIR", self.state_root) / "calendar-pimsync.lock"
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("CALENDAR_")}
        self.env.update({key: str(path) for key, path in self.roots.items()})
        # Native helpers deliberately use HOME/.config/quickshell for module paths.
        self.env["HOME"] = str(raw["HOME"])
        self.parent_identity = None

    def prepare(self):
        directory(self.parent, create=True)
        directory(self.state, create=True)
        self.parent_identity = (self.parent.stat().st_dev, self.parent.stat().st_ino)
        self.recheck()

    def recheck(self):
        require(self.alias.resolve() == self.parent and all(path.resolve() == self.roots[key] for key, path in self.raw.items()),
                "Calendar parent/XDG routing changed; preserve files for review.")
        directory(self.parent)
        require(self.parent_identity == (self.parent.stat().st_dev, self.parent.stat().st_ino), "Calendar parent directory changed.")
        require(not self.target.is_symlink(), "Calendar module itself must not be a symlink.")

    def routes(self):
        return {**{key: str(value) for key, value in self.roots.items()}, "target": str(self.target), "launchPath": str(self.launch_path)}

    def git(self, path, *, establish=False):
        marker = next((parent / ".git" for parent in (self.parent, *self.parent.parents) if present(parent / ".git")), None)
        if marker is None:
            return
        require(shutil.which("git"), "Git is required to verify this checkout safely.")
        env = {key: value for key, value in self.env.items() if not key.startswith("GIT_")}
        env["GIT_OPTIONAL_LOCKS"] = "0"
        base = ["git", "-c", "core.fsmonitor=false", "-C", str(self.parent)]
        literal = [base[0], "--literal-pathspecs", *base[1:]]
        top = Path(run(base + ["rev-parse", "--show-toplevel"], env=env).strip()).resolve()
        run(base + ["rev-parse", "--verify", "HEAD"], env=env)
        require(not run(literal + ["ls-files", "-z", "--", str(path)], env=env)
                and not run(literal + ["ls-tree", "-r", "-z", "--name-only", "HEAD", "--", str(path)], env=env),
                "Calendar refuses Git-tracked paths or pending tracking changes; no files were untracked.")
        if present(path):
            for parent, directories, files in os.walk(path, followlinks=False):
                require(".git" not in directories + files, "Calendar refuses nested Git repositories.")
        try:
            run(base + ["check-ignore", "--no-index", "-q", "--", str(path) + "/"], env=env)
            return
        except (ValueError, subprocess.CalledProcessError) as error:
            cause = error.__cause__ or error
            require(isinstance(cause, subprocess.CalledProcessError) and cause.returncode == 1,
                    "Could not verify Calendar Git exclusion safely.")
        require(establish, "Calendar path is not effectively Git-ignored: " + str(path))
        relative = self.parent.relative_to(top).as_posix()
        prefix = "" if relative == "." else relative + "/"
        rules = "".join("/" + prefix + suffix + "\n" for suffix in ("calendar/", ".calendar-install.*/", "calendar.update-rollback-*/"))
        require(confirm("Add narrowly scoped checkout-local Git excludes for Calendar, staging and rollback?"), "Calendar Git exclusion was not approved.")
        exclude = Path(run(base + ["rev-parse", "--path-format=absolute", "--git-path", "info/exclude"], env=env).strip())
        directory(exclude.parent, create=True)
        previous = read_owned(exclude, 1024 * 1024) if present(exclude) else None
        data = previous or b""
        data += (b"\n" if data and not data.endswith(b"\n") else b"") + rules.encode()
        atomic_write(exclude, data, previous=previous, mode=0o644)
        self.git(path)  # Higher-precedence negations may make local excludes ineffective.

    def storage(self, establish=False):
        self.recheck()
        for path in (self.target, self.parent / ".calendar-install.updater-check", self.parent / "calendar.update-rollback-updater-check"):
            self.git(path, establish=establish)


def inventory(module):
    directory(module)
    files, directories = {}, {}
    for parent, child_dirs, child_files in os.walk(module, followlinks=False):
        path = Path(parent)
        directory(path)
        stamp = path.stat()
        directories[path.relative_to(module).as_posix()] = {"mode": stat.S_IMODE(stamp.st_mode), "uid": stamp.st_uid, "gid": stamp.st_gid}
        require(".git" not in child_dirs + child_files, "Installed Calendar contains a Git repository.")
        for child in child_dirs:
            directory(path / child)
        for child in child_files:
            file = path / child
            name = file.relative_to(module).as_posix()
            require(runtime_member(name), "Installed Calendar contains custom/non-runtime files; review before updating.")
            data = read_owned(file, 48 * 1024 * 1024)
            stamp = file.stat()
            files[name] = {"sha256": hashlib.sha256(data).hexdigest(), "mode": stat.S_IMODE(stamp.st_mode), "uid": stamp.st_uid, "gid": stamp.st_gid}
    return {"files": files, "directories": directories}


def missing_dependencies():
    packages = set()
    for command, package in (("quickshell", "quickshell"), ("hyprctl", "hyprland"), ("pimsync", "pimsync"),
                             ("notify-send", "libnotify"), ("curl", "curl"), ("systemctl", "systemd"),
                             ("busctl", "systemd"), ("flock", "util-linux"), ("realpath", "coreutils"),
                             ("stat", "coreutils"), ("sync", "coreutils"), ("yes", "coreutils")):
        if not shutil.which(command):
            packages.add(package)
    for library, package in (("libical.so.4.0", "libical"), ("libQt6Core.so.6", "qt6-base"), ("libQt6Network.so.6", "qt6-base")):
        try:
            ctypes.CDLL(library)
        except OSError:
            packages.add(package)
    return sorted(packages)


def dependencies():
    missing = missing_dependencies()
    if missing:
        print("Missing Arch runtime packages: " + " ".join(missing))
        require(confirm("Install these packages with sudo pacman -S --needed?"), "Install missing runtime packages manually before continuing.")
        run(["sudo", "pacman", "-S", "--needed", *missing], timeout=1800, interactive=True)
        require(not missing_dependencies(), "Runtime dependencies are still missing; install them manually.")


def probe_helpers(module, work):
    sandbox = work / "probe"
    sandbox.mkdir(mode=0o700)
    env = dict(os.environ, QML_DISABLE_DISK_CACHE="1", PYTHONDONTWRITEBYTECODE="1", TZ="UTC")
    for key in ("HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR", "TMPDIR"):
        path = sandbox / key
        path.mkdir(mode=0o700)
        env[key] = str(path)
    source, output = sandbox / "fixture.ics", sandbox / "fixture.json"
    source.write_text("BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Calendar Deployment Check//EN\nBEGIN:VEVENT\nUID:deployment@example.invalid\nDTSTART:20300102T100000Z\nDTEND:20300102T110000Z\nSUMMARY:Fixture\nEND:VEVENT\nEND:VCALENDAR\n")
    run([module / "parse/convert", "prepare", source, output, "deployment"], env=env)
    events = json.loads(read_owned(output, 65536)).get("events")
    require(isinstance(events, list) and len(events) == 1, "New converter failed its isolated compatibility check.")
    result = json.loads(run([module / "parse/calendar-sync-helper", "expand"], env=env,
                           input=json.dumps(dict(requestId="deployment", rangeStartMs=1893574800000,
                                                 rangeEndMs=1893585600000, events=events)) + "\n"))
    require(result.get("requestId") == "deployment" and len(result.get("occurrences", [])) == 1
            and result.get("warnings") == [], "New helper failed its isolated compatibility check.")


def stage_release(paths, stage, local_archive=None):
    if local_archive:
        source = Path(local_archive).absolute()
        data = read_owned(source, MAX_ARCHIVE)
        checksum = read_owned(source.with_name(source.name + ".sha256"), 512)
        version = None
        filename = source.name
    else:
        version, archive, sidecar = discover_release()
        filename = archive["name"]
        checksum = download(sidecar["browser_download_url"], 512)
        data = download(archive["browser_download_url"], MAX_ARCHIVE)
    path = stage / filename
    path.write_bytes(data)
    result = extract_release(path, checksum, stage / "runtime", version)
    module = stage / "runtime/calendar"
    probe_helpers(module, stage)
    return result, module


def remove_stage(paths, stage):
    paths.recheck()
    require(stage.parent == paths.parent and stage.name.startswith(".calendar-install."), "Unowned Calendar staging path.")
    directory(stage)
    if not any(stage.iterdir()):
        stage.rmdir()  # No files can be tracked inside an empty directory.
        sync_directory(stage.parent)
        return
    paths.git(stage)
    # Only disposable private staging is recursive-cleaned, never application data.
    for parent, directories, files in os.walk(stage, followlinks=False):
        directory(Path(parent))
        require(".git" not in directories + files, "Staging contains a nested repository; preserve it.")
        for name in directories:
            directory(Path(parent) / name)
        for name in files:
            stamp = (Path(parent) / name).lstat()
            require(stat.S_ISREG(stamp.st_mode) and stamp.st_uid == os.getuid() and stamp.st_nlink == 1, "Staging changed; preserve it for review.")
    shutil.rmtree(stage)
    sync_directory(stage.parent)


def fresh_install(paths, archive):
    require(not present(paths.target) and not present(paths.installed), "Calendar already exists; use its updater or review legacy migration separately.")
    pimsync = paths.config / "pimsync"
    if present(pimsync):
        directory(pimsync)
    if present(paths.data):
        directory(paths.data)
        require(not any(paths.data.iterdir()), "Existing calendar data needs separate reviewed migration; nothing was reset.")
    dependencies()
    paths.storage(establish=True)
    stage = Path(tempfile.mkdtemp(prefix=".calendar-install.", dir=paths.parent))
    published = False
    registry_created = False
    try:
        paths.git(stage)
        result, module = stage_release(paths, stage, archive)
        paths.storage()
        require(not present(paths.target) and (not present(paths.data) or not any(paths.data.iterdir())), "Calendar installation target/data changed.")
        directory(paths.data, create=True)
        registry = paths.data / "profiles.json"
        atomic_write(registry, b'{"version":1,"profiles":[]}\n')
        registry_created = True
        move(module, paths.target)
        published = True
        receipt = {**result, **inventory(paths.target), "schema": 1, "dataSchema": 1, "routes": paths.routes()}
        write_json(paths.installed, receipt)
        print("Installed calendar-v" + result["version"] + "; empty registry, no services or Calendar instance started.")
    except BaseException:
        if published and not present(paths.installed):
            paths.storage()
            move(paths.target, stage / "runtime/calendar")
        if registry_created and not present(paths.installed):
            registry = paths.data / "profiles.json"
            if read_owned(registry, 65536) == b'{"version":1,"profiles":[]}\n':
                registry.unlink()
                sync_directory(paths.data)
        raise
    finally:
        try:
            remove_stage(paths, stage)
        except (OSError, ValueError) as error:
            print("Preserved Calendar staging for review: " + str(stage) + " (" + str(error) + ")", file=sys.stderr)


UNIT_FILE = re.compile(r"(?:pimsync\.service(?:\.d/calendar-(?:group-recovery|caldav)\.conf)?|quickshell-calendar-import\.(?:service|path)|quickshell-calendar-caldav@\.service|quickshell-calendar-caldav-[a-z0-9][a-z0-9_-]{0,127}\.timer)")
UNIT_NAME = re.compile(r"(?:pimsync\.service|quickshell-calendar-import\.(?:service|path)|quickshell-calendar-caldav(?:-[a-z0-9][a-z0-9_-]{0,127}\.timer|@[a-z0-9][a-z0-9_-]{0,127}\.service))")


def expected_units(files):
    require(not files or {"pimsync.service", "pimsync.service.d/calendar-group-recovery.conf"} <= files.keys(), "Managed runtime lacks its shared daemon/guard.")
    require(("quickshell-calendar-import.service" in files) == ("quickshell-calendar-import.path" in files), "Managed import runtime is incomplete.")
    units = {name for name in files if "/" not in name and "@" not in name}
    timers = {name for name in units if name.endswith(".timer")}
    require(("quickshell-calendar-caldav@.service" in files) == bool(timers)
            and ("pimsync.service.d/calendar-caldav.conf" in files) == bool(timers), "Managed CalDAV runtime is incomplete.")
    units.update("quickshell-calendar-caldav@" + name[len("quickshell-calendar-caldav-"):-len(".timer")] + ".service" for name in timers)
    return units


def validate_receipt(paths, receipt):
    require(type(receipt.get("schema")) is int and type(receipt.get("dataSchema")) is int
            and receipt.get("schema") == 1 and receipt.get("dataSchema") == 1 and receipt.get("routes") == paths.routes(),
            "Unknown Calendar layout/schema/routing; migration requires separate review.")
    version_key(receipt.get("version"))
    require(isinstance(receipt.get("sha256"), str) and re.fullmatch(r"[a-f0-9]{64}", receipt["sha256"]), "Calendar archive receipt is invalid.")
    require(isinstance(receipt.get("files"), dict) and isinstance(receipt.get("directories"), dict), "Calendar inventory receipt is invalid.")
    require(REQUIRED <= receipt["files"].keys() and len(receipt["files"]) <= 512
            and all(runtime_member(name) for name in receipt["files"]), "Calendar receipt inventory is unsafe.")
    expected_dirs = {"."}
    for name, value in receipt["files"].items():
        expected_dirs.update(parent.as_posix() for parent in Path(name).parents)
        require(isinstance(value, dict) and isinstance(value.get("sha256"), str)
                and re.fullmatch(r"[a-f0-9]{64}", value["sha256"]), "Calendar file receipt is invalid.")
    require(set(receipt["directories"]) == expected_dirs, "Calendar directory receipt is unsafe.")
    for value in [*receipt["files"].values(), *receipt["directories"].values()]:
        require(isinstance(value, dict) and type(value.get("mode")) is int and 0 <= value["mode"] <= 0o777
                and not value["mode"] & 0o022 and value.get("uid") == os.getuid()
                and type(value.get("gid")) is int and value["gid"] >= 0, "Calendar ownership/mode receipt is invalid.")


def verify_module(paths, receipt, module):
    validate_receipt(paths, receipt)
    require(inventory(module) == {key: receipt[key] for key in ("files", "directories")},
            "Installed Calendar has changed/custom files or permissions; preserve it for review.")
    require(read_owned(module / "VERSION", 128).decode().strip() == receipt["version"], "Installed Calendar version differs from its receipt.")


def recovery_check(paths):
    for relative in ("group-recovery", "group-resolution.json", "subscriptions/change.json"):
        require(not present(paths.state_root / relative), "Calendar recovery is pending; resolve it before deployment.")
    caldav = paths.state_root / "caldav"
    if present(caldav):
        directory(caldav)
        require(not any(path.name.startswith(("conversion-", "attachment-", "remote-delete-")) for path in caldav.iterdir()),
                "Calendar conversion/attachment/deletion recovery is pending.")
    if present(paths.data):
        directory(paths.data)
        for path in paths.data.iterdir():
            require(not path.name.startswith(".calendar-"), "Calendar operation staging needs review before deployment.")
            if path.name == ".imports":
                directory(path)
                require(not any(child.name != ".calendar-sync.lock" for child in path.iterdir()), "Calendar import is pending; finish it before deployment.")
            elif path.is_dir():
                directory(path)
                require(not any(child.name.startswith(".calendar-series-") for child in path.iterdir()), "Calendar series recovery is pending.")


def config_snapshot(paths):
    pimsync = paths.config / "pimsync"
    if present(pimsync):
        directory(pimsync)
    return {str(path): hashlib.sha256(read_owned(path, 1024 * 1024)).hexdigest() if present(path) else None
            for path in (paths.data / "profiles.json", pimsync / "pimsync.conf")}


def native_plan(paths, module, verify=False):
    value = json.loads(run([module / "parse/calendar-sync-helper", "deployment-verify" if verify else "deployment-plan"], env=paths.env))
    require(isinstance(value, dict) and value.get("ok") is True and type(value.get("schema")) is int
            and type(value.get("dataSchema")) is int and value.get("schema") == value.get("dataSchema") == 1,
            "Native deployment/data schema is unsupported; migration requires separate review.")
    files, units = value.get("files"), value.get("units")
    require(isinstance(files, dict) and len(files) <= 256 and all(isinstance(name, str) and UNIT_FILE.fullmatch(name)
            and isinstance(text, str) and len(text.encode()) <= 1024 * 1024 for name, text in files.items()), "Native deployment unit files are invalid.")
    require(isinstance(units, list) and len(units) <= 512 and all(isinstance(name, str) and UNIT_NAME.fullmatch(name) for name in units)
            and len(units) == len(set(units)), "Native deployment unit names are invalid.")
    require(set(units) == expected_units(files), "Native deployment schedule differs from its canonical unit files.")
    return value


def checked_unit_state(result):
    require(isinstance(result, dict) and set(result) == {"LoadState", "ActiveState", "UnitFileState", "FragmentPath", "DropInPaths"}
            and all(isinstance(value, str) and len(value) <= 16384 for value in result.values())
            and result["LoadState"] in ("loaded", "not-found") and result["ActiveState"] in ("active", "inactive", "failed")
            and result["UnitFileState"] in ("enabled", "enabled-runtime", "disabled", "static", "indirect", ""), "Managed calendar service is busy, masked or has an unknown state.")
    return result


def unit_state(paths, name):
    output = run(["systemctl", "--user", "show", "--property=LoadState,ActiveState,UnitFileState,FragmentPath,DropInPaths", name], env=paths.env)
    return checked_unit_state(dict(line.split("=", 1) for line in output.splitlines() if "=" in line))


def check_runtime_snapshot(runtime, files):
    require(isinstance(runtime, dict) and set(runtime) == {"units", "calendarPid"}
            and isinstance(runtime["units"], dict) and set(runtime["units"]) == expected_units(files)
            and (runtime["calendarPid"] is None or (type(runtime["calendarPid"]) is int and runtime["calendarPid"] > 0)),
            "Calendar runtime recovery snapshot is incomplete or unsafe.")
    for state in runtime["units"].values():
        checked_unit_state(state)


def verify_unit_routing(paths, name, state, files):
    fragment = re.sub(r"@[^@]+\.service$", "@.service", name)
    dropins = sorted(str(paths.units / file) for file in files if file.startswith(fragment + ".d/"))
    require(state["LoadState"] == "not-found" or (Path(state["FragmentPath"]).resolve() == (paths.units / fragment).resolve()
            and state["DropInPaths"] == " ".join(dropins)), "Effective Calendar service uses custom routing/drop-ins.")


def unit_snapshot(paths, plan):
    files, states = {}, {}
    if present(paths.units):
        directory(paths.units)
        allowed = set(plan["files"]) | {str(Path(name).parent) for name in plan["files"]}
        for path in paths.units.iterdir():
            if path.name.startswith("quickshell-calendar-"):
                require(path.name in allowed, "Unrecognized Calendar service/drop-in needs review.")
    for name, expected in plan["files"].items():
        path = paths.units / name
        directory(path.parent)
        data = read_owned(path, 1024 * 1024)
        text = data.decode("utf-8")
        unmarked = expected.split("\n", 1)[1] if expected.startswith("# quickshell-calendar ") else expected
        require(text in (expected, unmarked), "Calendar service has custom settings; it was not overwritten: " + name)
        stamp = path.stat()
        files[name] = {"text": text, "mode": stat.S_IMODE(stamp.st_mode), "uid": stamp.st_uid, "gid": stamp.st_gid}
    for name in plan["units"]:
        state = unit_state(paths, name)
        verify_unit_routing(paths, name, state, plan["files"])
        states[name] = state
    return files, states


def instances(paths):
    paths.recheck()
    allowed = {str(paths.target / "shell.qml"), str(paths.launch_path / "shell.qml")}
    def selected(extra):
        text = run(["quickshell", "list", "--path", paths.launch_path, "--json", *extra], env=dict(paths.env, NO_COLOR="1"))
        if any(text == f'No running instances for "{path}"\nUse --all to list all instances.\n' for path in allowed):
            return []
        value = json.loads(text)
        require(isinstance(value, list) and len(value) <= 1 and all(isinstance(item, dict) and item.get("config_path") in allowed
                and type(item.get("pid")) is int and item["pid"] > 0 for item in value), "Could not identify one Calendar instance safely.")
        return value
    current, all_displays = selected([]), selected(["--any-display"])
    require(current == all_displays, "Calendar is running on another display; stop it before updating.")
    return current[0]["pid"] if current else None


def stop_runtime(paths, runtime, expected_pid=None, check_pid=False, config_missing=False):
    # The fsynced paused journal precedes the two module renames. During recovery
    # between those renames, selected-path IPC cannot resolve the absent config;
    # Calendar had already been stopped before the old module could move.
    pid = None if config_missing else instances(paths)
    require(not check_pid or pid == expected_pid, "Calendar instance changed during deployment.")
    if pid:
        run(["quickshell", "kill", "--pid", str(pid)], env=paths.env)
        for attempt in range(50):
            if instances(paths) is None:
                break
            time.sleep(0.1)
        else:
            raise ValueError("Calendar did not stop; preserve the deployment journal.")
    # Stop triggers before workers, including previously inactive workers which a
    # watcher could have queued after the state snapshot.
    names = sorted(runtime["units"], key=lambda name: (not name.endswith((".path", ".timer")), name))
    for name in names:
        if runtime["units"][name]["LoadState"] == "loaded":
            paths.recheck()
            run(["systemctl", "--user", "stop", name], env=paths.env)


def resume_runtime(paths, runtime):
    names = [name for name, state in runtime["units"].items() if state["ActiveState"] == "active"]
    if "quickshell-calendar-import.path" in names and "quickshell-calendar-import.service" not in names:
        names.insert(0, "quickshell-calendar-import.service")
    for name in names:
        # Cache/sync workers take the lifecycle lock. Queue, never wait for them
        # while the updater still owns that same lock.
        paths.recheck()
        run(["systemctl", "--user", "start", "--no-block", name], env=paths.env)
    if runtime["calendarPid"] is not None:
        paths.recheck()
        run(["quickshell", "--path", paths.launch_path, "--daemonize", "--no-duplicate"], env=paths.env)


def verify_runtime(paths, runtime):
    for name, before in runtime["units"].items():
        state = unit_state(paths, name)
        require(state["UnitFileState"] == before["UnitFileState"], "Calendar service enablement changed; inspect before recovery.")
        if before["ActiveState"] == "active" and name != "quickshell-calendar-import.service" and "@" not in name:
            for attempt in range(50):
                if state["ActiveState"] == "active":
                    break
                require(state["ActiveState"] != "failed", "Resumed Calendar service failed.")
                time.sleep(0.1)
                state = unit_state(paths, name)
            else:
                raise ValueError("Calendar service did not resume.")
    if runtime["calendarPid"] is not None:
        for attempt in range(50):
            pid = instances(paths)
            if pid:
                try:
                    if "target calendar" in run(["quickshell", "ipc", "--pid", str(pid), "show"], env=paths.env).splitlines():
                        return
                except ValueError:
                    pass
            time.sleep(0.1)
        raise ValueError("Calendar IPC did not become ready.")
    require(instances(paths) is None, "An unexpected Calendar instance started during deployment.")


def verify_units_unchanged(paths, files):
    for name, value in files.items():
        path = paths.units / name
        stamp = path.lstat()
        require(read_owned(path, 1024 * 1024).decode() == value["text"] and stat.S_IMODE(stamp.st_mode) == value["mode"]
                and stamp.st_uid == value["uid"] and stamp.st_gid == value["gid"], "Calendar unit changed during deployment; preserve it.")


def pending_receipt(paths):
    value = read_json(paths.pending)
    require(type(value.get("schema")) is int and value.get("schema") == 1 and value.get("routes") == paths.routes()
            and value.get("phase") in ("preparing", "paused", "applying", "activated", "resuming", "ready", "restoring", "rolled-back", "confirming"), "Calendar recovery receipt is unsupported.")
    for role, prefix in (("rollback", "calendar.update-rollback-"), ("stage", ".calendar-install.")):
        require(isinstance(value.get(role), str), "Calendar recovery path is invalid.")
        path = Path(value[role])
        require(path.parent == paths.parent and re.fullmatch(re.escape(prefix) + r"[a-z0-9_]{8}", path.name), "Calendar recovery path is unsafe.")
        if present(path):
            directory(path)
    for role in ("old", "new"):
        require(isinstance(value.get(role), dict), "Calendar version recovery receipt is invalid.")
        validate_receipt(paths, value[role])
    require(isinstance(value.get("files"), dict) and all(UNIT_FILE.fullmatch(name) for name in value["files"])
            and isinstance(value.get("runtime"), dict) and isinstance(value["runtime"].get("units"), dict)
            and all(UNIT_NAME.fullmatch(name) for name in value["runtime"]["units"]), "Calendar runtime recovery receipt is unsafe.")
    require(isinstance(value.get("newUnits"), dict) and set(value["newUnits"]) == set(value["files"])
            and all(isinstance(text, str) and len(text.encode()) <= 1024 * 1024 for text in value["newUnits"].values()),
            "Calendar replacement unit receipt is invalid.")
    for file in value["files"].values():
        require(isinstance(file, dict) and isinstance(file.get("text"), str) and len(file["text"].encode()) <= 1024 * 1024
                and type(file.get("mode")) is int and 0 <= file["mode"] <= 0o777 and not file["mode"] & 0o022
                and file.get("uid") == os.getuid() and type(file.get("gid")) is int and file["gid"] >= 0,
                "Calendar original unit receipt is invalid.")
    check_runtime_snapshot(value["runtime"], value["files"])
    if "restoreRuntime" in value:
        check_runtime_snapshot(value["restoreRuntime"], value["files"])
    return value


def verify_recovery_units(paths, pending):
    for name, value in pending["files"].items():
        path = paths.units / name
        directory(path.parent)
        actual = read_owned(path, 1024 * 1024).decode()
        stamp = path.stat()
        require(actual in (value["text"], pending["newUnits"][name]) and stat.S_IMODE(stamp.st_mode) == value["mode"]
                and stamp.st_uid == value["uid"] and stamp.st_gid == value["gid"], "Calendar unit changed after deployment; no overwrite or pause.")
    for name in pending["runtime"]["units"]:
        verify_unit_routing(paths, name, unit_state(paths, name), pending["files"])


def set_permissions(module, receipt):
    for name, old in receipt["directories"].items():
        path = module if name == "." else module / name
        if path.is_dir():
            os.chown(path, old["uid"], old["gid"], follow_symlinks=False)
            path.chmod(old["mode"])
    for name, old in receipt["files"].items():
        path = module / name
        if path.is_file():
            os.chown(path, old["uid"], old["gid"], follow_symlinks=False)


def rollback_update(paths, pending, *, automatic=False):
    paths.storage()
    rollback, stage = Path(pending["rollback"]), Path(pending["stage"])
    paths.git(rollback)
    old_module = rollback / "module"
    old = pending["old"]
    new = pending["new"]
    if present(old_module):
        verify_module(paths, old, old_module)
        require(set(rollback.iterdir()) == {old_module}, "Rollback directory has unexpected files; preserve it.")
    config_missing = not present(paths.target)
    require(not config_missing or (present(old_module) and pending["phase"] in ("paused", "applying", "activated", "resuming", "ready", "restoring")),
            "Calendar config is missing outside a verified module-move recovery stage.")
    require(not present(paths.target) or inventory(paths.target) in ({key: receipt[key] for key in ("files", "directories")} for receipt in (old, new)),
            "Calendar code changed since deployment; no automatic overwrite.")
    require(config_snapshot(paths) == pending["configuration"], "Calendar settings changed since deployment; rollback needs separate review.")
    recovery_check(paths)
    verify_recovery_units(paths, pending)
    runtime = pending.get("restoreRuntime", pending["runtime"])
    if not automatic and pending["phase"] == "ready" and "restoreRuntime" not in pending and not config_missing:
        runtime = {"calendarPid": instances(paths), "units": {name: unit_state(paths, name) for name in runtime["units"]}}
    pending["restoreRuntime"] = runtime
    pending["phase"] = "restoring"
    write_json(paths.pending, pending)
    # If resumed jobs acquired the lease already, stop our verified runtime first,
    # then acquire it. Never unlink the persistent shared lock.
    stop_runtime(paths, runtime, config_missing=config_missing)
    own_lock = lock(paths.shared_lock)
    try:
        recovery_check(paths)
        paths.storage()
        require(config_snapshot(paths) == pending["configuration"], "Calendar settings changed while pausing rollback.")
        verify_recovery_units(paths, pending)
        if present(old_module):
            if present(paths.target):
                verify_module(paths, new, paths.target)
                if not present(stage):
                    stage = Path(tempfile.mkdtemp(prefix=".calendar-install.", dir=paths.parent))
                    pending["stage"] = str(stage)
                    write_json(paths.pending, pending)
                paths.git(stage)
                move(paths.target, stage / "failed-module")
            move(old_module, paths.target)
        verify_module(paths, old, paths.target)
        for name, value in pending["files"].items():
            path = paths.units / name
            actual = read_owned(path, 1024 * 1024)
            if actual != value["text"].encode():
                atomic_write(path, value["text"].encode(), previous=actual, mode=value["mode"], uid=value["uid"], gid=value["gid"])
        if pending["files"]:
            run(["systemctl", "--user", "daemon-reload"], env=paths.env)
        native_plan(paths, paths.target, verify=True)
        write_json(paths.installed, old)
        resume_runtime(paths, runtime)
    finally:
        os.close(own_lock)
    verify_runtime(paths, runtime)
    pending["phase"] = "rolled-back"
    write_json(paths.pending, pending)
    paths.storage()
    paths.git(rollback)
    if present(rollback):
        require(not any(rollback.iterdir()), "Rollback directory is not empty after restoration.")
        rollback.rmdir()
    paths.pending.unlink()
    sync_directory(paths.state)
    if present(stage):
        remove_stage(paths, stage)
    print("Previous Calendar code/units/runtime restored; calendar data was not rolled back.")


def update(paths, archive):
    paths.storage()
    require(present(paths.installed), "Calendar has no runtime-release receipt; legacy migration requires separate review.")
    old = read_json(paths.installed)
    verify_module(paths, old, paths.target)
    recovery_check(paths)
    dependencies()
    stage = Path(tempfile.mkdtemp(prefix=".calendar-install.", dir=paths.parent))
    descriptor, pending, rollback = None, None, None
    try:
        paths.git(stage)
        result, module = stage_release(paths, stage, archive)
        if version_key(result["version"]) == version_key(old["version"]):
            require(result["version"] == old["version"] and result["sha256"] == old["sha256"], "Published Calendar version was replaced; review release integrity.")
            print("Already running calendar-v" + old["version"] + "; no replacement.")
            return
        require(version_key(result["version"]) > version_key(old["version"]), "Calendar refuses a downgrade; use reviewed rollback instead.")
        directory(paths.shared_lock.parent)
        descriptor = lock(paths.shared_lock)
        paths.storage()
        verify_module(paths, old, paths.target)
        recovery_check(paths)
        configuration = config_snapshot(paths)
        before = native_plan(paths, paths.target, verify=True)
        after = native_plan(paths, module)
        require(set(before["files"]) == set(after["files"]) and set(before["units"]) == set(after["units"]),
                "Calendar runtime layout migration requires separate review/approval.")
        files, states = unit_snapshot(paths, before)
        pid = instances(paths)
        if any(value["text"] != after["files"][name] for name, value in files.items()):
            require(confirm("Refresh changed Calendar-owned service definitions while preserving their permissions/enablement?"), "Calendar service refresh was not approved.")
        set_permissions(module, old)
        new = {**result, **inventory(module), "schema": 1, "dataSchema": 1, "routes": paths.routes()}
        rollback = Path(tempfile.mkdtemp(prefix="calendar.update-rollback-", dir=paths.parent))
        paths.git(rollback)
        pending = {"schema": 1, "routes": paths.routes(), "phase": "preparing", "rollback": str(rollback), "stage": str(stage),
                   "old": old, "new": new, "files": files, "newUnits": after["files"], "configuration": configuration,
                   "runtime": {"calendarPid": pid, "units": states}}
        write_json(paths.pending, pending)
        stop_runtime(paths, pending["runtime"], expected_pid=pid, check_pid=True)
        recovery_check(paths)
        paths.storage()
        paths.git(stage)
        paths.git(rollback)
        verify_module(paths, old, paths.target)
        verify_units_unchanged(paths, files)
        require(config_snapshot(paths) == configuration, "Calendar configuration changed during deployment.")
        pending["phase"] = "paused"
        write_json(paths.pending, pending)
        move(paths.target, rollback / "module")
        move(module, paths.target)
        pending["phase"] = "activated"
        write_json(paths.pending, pending)
        for name, value in files.items():
            if value["text"] != after["files"][name]:
                atomic_write(paths.units / name, after["files"][name].encode(), previous=value["text"].encode(),
                             mode=value["mode"], uid=value["uid"], gid=value["gid"])
        if files:
            run(["systemctl", "--user", "daemon-reload"], env=paths.env)
        native_plan(paths, paths.target, verify=True)
        write_json(paths.installed, new)
        pending["phase"] = "resuming"
        write_json(paths.pending, pending)
        resume_runtime(paths, pending["runtime"])
        os.close(descriptor)
        descriptor = None
        verify_runtime(paths, pending["runtime"])
        paths.storage()
        pending["phase"] = "ready"
        write_json(paths.pending, pending)
        print("Updated to calendar-v" + new["version"] + "; rollback retained. Verify manually, then run update.sh --confirm.")
    except BaseException:
        if descriptor is not None:
            os.close(descriptor)
            descriptor = None
        if pending is not None and present(paths.pending):
            try:
                rollback_update(paths, pending, automatic=True)
            except (OSError, ValueError, KeyboardInterrupt) as error:
                print("Calendar recovery needs review; preserve " + str(paths.pending) + " and " + pending["rollback"] + ": " + str(error), file=sys.stderr)
        raise
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if rollback is not None and present(rollback) and not present(paths.pending):
            try:
                rollback.rmdir()  # Only an empty, pre-journal reservation is disposable.
                sync_directory(paths.parent)
            except OSError:
                print("Preserved nonempty Calendar rollback reservation: " + str(rollback), file=sys.stderr)
        if present(stage) and (not present(paths.pending) or (pending is not None and pending["phase"] == "ready")):
            try:
                remove_stage(paths, stage)
            except (OSError, ValueError) as error:
                print("Preserved Calendar staging for review: " + str(stage) + ": " + str(error), file=sys.stderr)


def verify_rollback_cleanup(paths, pending):
    rollback = Path(pending["rollback"])
    if not present(rollback):
        require(pending["phase"] == "confirming", "Calendar rollback directory is missing unexpectedly.")
        return
    module = rollback / "module"
    require(set(rollback.iterdir()) <= {module}, "Rollback directory contains unexpected files.")
    if pending["phase"] != "confirming":
        verify_module(paths, pending["old"], module)
    elif present(module):
        # A crash can interrupt already-approved recursive cleanup. Every remaining
        # file/directory must still be an unchanged subset of that old inventory.
        remaining = inventory(module)
        require(all(name in pending["old"][kind] and value == pending["old"][kind][name]
                    for kind in ("files", "directories") for name, value in remaining[kind].items()),
                "Rollback cleanup found changed/unknown files; preserve them.")


def confirm_update(paths):
    pending = pending_receipt(paths)
    require(pending["phase"] in ("ready", "confirming"), "Update did not finish runtime verification; retain rollback and inspect recovery.")
    paths.storage()
    recovery_check(paths)
    verify_module(paths, pending["new"], paths.target)
    require(read_json(paths.installed) == pending["new"], "Current Calendar receipt changed; preserve rollback.")
    rollback = Path(pending["rollback"])
    paths.git(rollback)
    verify_rollback_cleanup(paths, pending)
    require(confirm("Calendar works correctly? Permanently remove previous code and rollback receipt?"), "Calendar rollback retained.")
    pending["phase"] = "confirming"
    write_json(paths.pending, pending)
    paths.storage()
    paths.git(rollback)
    if present(rollback):
        verify_rollback_cleanup(paths, pending)
        shutil.rmtree(rollback)
        sync_directory(paths.parent)
    paths.pending.unlink()
    sync_directory(paths.state)
    print("Calendar update confirmed; previous code removed. Data/settings were not cleanup targets.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--update", action="store_true")
    modes.add_argument("--confirm-update", action="store_true")
    modes.add_argument("--rollback", action="store_true")
    parser.add_argument("--archive", metavar="PATH", help="use a local runtime archive and adjacent .sha256 sidecar")
    args = parser.parse_args(argv)
    require(not args.archive or not (args.confirm_update or args.rollback), "--archive cannot be combined with confirmation/rollback.")
    require(sys.version_info >= (3, 11), "Calendar deployment requires Python 3.11+.")
    require(platform.system() == "Linux" and platform.machine() == "x86_64", "Calendar releases support Linux x86_64 only.")
    require(os.getuid() != 0 and os.getuid() == os.geteuid(), "Run Calendar installer as your desktop user, not root/sudo.")
    os.umask(0o077)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    paths = Paths()
    paths.prepare()
    descriptor = lock(paths.state, is_directory=True)
    try:
        require(not present(paths.state / "update-previous"), "Legacy update recovery receipt exists; inspect it before migration.")
        require(all(path.name in ("installed.json", "pending.json") for path in paths.state.iterdir()),
                "Unknown/legacy Calendar installer state exists; inspect it before migration.")
        if args.confirm_update or args.rollback:
            require(present(paths.pending), "No Calendar deployment awaits confirmation/recovery.")
            if args.confirm_update:
                directory(paths.shared_lock.parent)
                shared = lock(paths.shared_lock)
                try:
                    confirm_update(paths)
                finally:
                    os.close(shared)
            else:
                pending = pending_receipt(paths)
                require(confirm("Restore previous Calendar code/units without rolling back calendar data?"), "Calendar rollback was not approved.")
                rollback_update(paths, pending)
        else:
            require(not present(paths.pending), "Previous Calendar deployment awaits confirmation/recovery.")
            if args.update:
                update(paths, args.archive)
            else:
                fresh_install(paths, args.archive)
    finally:
        os.close(descriptor)


def interrupted(_signum, _frame):
    raise KeyboardInterrupt


if __name__ == "__main__":
    for signum in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    try:
        main()
    except (OSError, ValueError, KeyboardInterrupt) as error:
        print(str(error) if not isinstance(error, KeyboardInterrupt) else "Calendar deployment interrupted; inspect any retained recovery receipt.", file=sys.stderr)
        sys.exit(1)
