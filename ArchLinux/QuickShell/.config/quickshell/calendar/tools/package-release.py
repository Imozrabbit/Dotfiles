#!/usr/bin/env python3
"""Build a local runtime release candidate; never install or publish it.

Run from the Calendar source root: python3 -I -B tools/package-release.py
Requires Linux x86_64, Python 3.11+, Make, g++, binutils/readelf, pkg-config,
libical and Qt6Core/Qt6Network development files. Uses the existing Makefile
in private staging, not the live parse directory. Tests and source stay local.
"""
import argparse
import gzip
import hashlib
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "deployment"))
from release_archive import NATIVE, REQUIRED, VERSION as RELEASE_VERSION, extract_release, runtime_member

SOURCE_DIRS = {"common": ".js", "services": ".qml", "ui": ".qml"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def checked_directory(path):
    stamp = path.lstat()
    require(stat.S_ISDIR(stamp.st_mode) and stamp.st_uid == os.getuid(),
            "Packaging requires owned real directories, not symlinks or special paths.")


def checked_file(path, limit=16 * 1024 * 1024):
    stamp = path.lstat()
    require(stat.S_ISREG(stamp.st_mode) and stamp.st_uid == os.getuid()
            and stamp.st_nlink == 1 and stamp.st_size <= limit,
            "Packaging input is missing, linked, oversized, special or not owned by this user.")
    return stamp


def signature(stamp):
    return (stamp.st_dev, stamp.st_ino, stamp.st_mode, stamp.st_nlink,
            stamp.st_size, stamp.st_mtime_ns, stamp.st_ctime_ns)


def read_input(relative, limit=16 * 1024 * 1024):
    path = ROOT / relative
    for parent in path.parents:
        if parent == ROOT:
            break
        checked_directory(parent)
    before = checked_file(path, limit)
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
        require(signature(os.fstat(stream.fileno())) == signature(before), "Packaging input changed while opening it.")
        data = stream.read(limit + 1)
        require(len(data) <= limit and signature(os.fstat(stream.fileno())) == signature(before)
                and signature(path.lstat()) == signature(before), "Packaging input changed during snapshot.")
    return data, signature(before)


def release_inputs():
    version_data, version_stamp = read_input("VERSION", 128)
    require(re.fullmatch(RELEASE_VERSION.encode("ascii") + rb"\n?", version_data), "VERSION must contain one numeric stable or beta.N release version.")
    version = version_data.decode("ascii").strip()
    manifest, manifest_stamp = read_input("release-files.txt", 65536)
    names = manifest.decode("utf-8").splitlines()
    require(names and all(runtime_member(name) for name in names) and len(names) == len(set(names)),
            "Runtime manifest contains unsafe, duplicate or non-runtime members.")
    require(REQUIRED <= set(names), "Runtime manifest is missing a required entrypoint, script, helper or version.")
    for directory, suffix in SOURCE_DIRS.items():
        checked_directory(ROOT / directory)
        present = {str(path.relative_to(ROOT)) for path in (ROOT / directory).rglob("*" + suffix)}
        require(present == {name for name in names if name.startswith(directory + "/")},
                "Runtime QML/JS files differ from the explicit release manifest; review the manifest first.")
    checked_directory(ROOT / "parse")
    checked_directory(ROOT / "parse/src")
    native_sources = {str(path.relative_to(ROOT)) for path in (ROOT / "parse/src").iterdir() if path.suffix in {".cpp", ".h"}}
    require(native_sources, "Native source files are missing.")
    return version, sorted(names), native_sources, {"VERSION": version_stamp, "release-files.txt": manifest_stamp}


def output_directory():
    path = ROOT
    for component in ("dist", "releases"):
        path /= component
        path.mkdir(mode=0o700, exist_ok=True)
        checked_directory(path)
        require(not path.stat().st_mode & 0o022, "Release output must not be writable by other users.")
    if shutil.which("git"):
        env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
            env.pop(key, None)
        base = ["git", "-c", "core.fsmonitor=false", "-C", str(ROOT)]
        probe = subprocess.run(base + ["rev-parse", "--is-inside-work-tree"], env=env, capture_output=True)
        if probe.returncode == 0:
            ignored = subprocess.run(base + ["check-ignore", "--no-index", "-q", "--", str(path / "release-candidate")], env=env, capture_output=True)
            require(ignored.returncode == 0, "Release output is not Git-ignored; no candidate was built.")
    return path


def private_environment(stage):
    env = dict(os.environ, LC_ALL="C", QML_DISABLE_DISK_CACHE="1", PYTHONDONTWRITEBYTECODE="1")
    # Release compilation uses the existing Makefile defaults, not inherited
    # make targets, compiler wrappers or CPU-specific flag overrides.
    for key in ("MAKEFLAGS", "GNUMAKEFLAGS", "MFLAGS", "MAKEFILES", "CXX", "CXXFLAGS", "CPPFLAGS", "LDFLAGS"):
        env.pop(key, None)
    for key in ("HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR", "TMPDIR"):
        path = stage / "isolation" / key
        path.mkdir(mode=0o700, parents=True)
        env[key] = str(path)
    return env


def build_helpers(build, stage):
    env = private_environment(stage)
    with (stage / "build.log").open("wb") as log:
        process = subprocess.Popen(["make", "--no-print-directory", "-C", str(build), "convert", "calendar-sync-helper"],
                                   env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait()
        except BaseException:
            # All build output is disposable. Stop the entire owned group,
            # including children that ignore SIGTERM, before deleting staging.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise
    require(code == 0, "Native staging build failed:\n" + (stage / "build.log").read_text(errors="replace")[-8000:])
    for relative in sorted(NATIVE):
        path = build / Path(relative).name
        stamp = checked_file(path, 128 * 1024 * 1024)
        require(stamp.st_mode & 0o111, "Native staging build did not produce executable helpers.")
        header = subprocess.run(["readelf", "--file-header", "--wide", str(path)], env=env, capture_output=True, text=True, check=True).stdout
        require(re.search(r"^\s*Class:\s+ELF64\s*$", header, re.M)
                and re.search(r"^\s*Machine:\s+Advanced Micro Devices X86-64\s*$", header, re.M),
                "Native helper architecture differs from the Linux x86_64 release target.")


def write_archive(payload, names, destination):
    directories = {"calendar"}
    for name in names:
        directories.update(str(parent) for parent in PurePosixPath("calendar", name).parents if str(parent) != ".")
    with destination.open("xb") as output, gzip.GzipFile(filename="", fileobj=output, mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
            for name in sorted(directories):
                info = tarfile.TarInfo(name)
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                archive.addfile(info)
            for name in names:
                path = payload / name
                stamp = checked_file(path, 128 * 1024 * 1024)
                info = tarfile.TarInfo("calendar/" + name)
                info.mode = 0o755 if name.endswith(".sh") or name in NATIVE else 0o644
                info.size = stamp.st_size
                with path.open("rb") as stream:
                    archive.addfile(info, stream)


def main():
    argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter).parse_args()
    require(sys.version_info >= (3, 11), "Packaging requires Python 3.11+.")
    require(platform.system() == "Linux" and platform.machine() == "x86_64", "This release target is Linux x86_64 only.")
    os.umask(0o077)
    version, names, native_sources, snapshots = release_inputs()
    output = output_directory()
    with tempfile.TemporaryDirectory(prefix=".release-build-", dir=output) as temporary:
        stage = Path(temporary)
        payload, build = stage / "runtime/calendar", stage / "build/parse"
        payload.mkdir(parents=True)
        build.mkdir(parents=True)
        for relative in sorted((set(names) - NATIVE) | native_sources | {"parse/Makefile"}):
            data, stamp = read_input(relative)
            require(relative not in snapshots or snapshots[relative] == stamp, "Version changed during packaging snapshot.")
            snapshots[relative] = stamp
            target = stage / "build" / relative if relative in native_sources or relative == "parse/Makefile" else payload / relative
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            target.write_bytes(data)
        for relative, stamp in snapshots.items():
            require(signature(checked_file(ROOT / relative)) == stamp, "Source inputs changed during packaging snapshot; retry.")
        print("Building fresh helpers in private staging; live helpers are not modified.", flush=True)
        build_helpers(build, stage)
        for relative in NATIVE:
            shutil.copyfile(build / Path(relative).name, payload / relative)
        artifacts = stage / "artifacts"
        artifacts.mkdir()
        filename = f"calendar-v{version}-linux-x86_64.tar.gz"
        archive = artifacts / filename
        write_archive(payload, names, archive)
        with archive.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        checksum = f"{digest}  {filename}\n".encode("ascii")
        (artifacts / (filename + ".sha256")).write_bytes(checksum)
        extract_release(archive, checksum, stage / "client-validation", version)
        destination = Path(tempfile.mkdtemp(prefix=f"calendar-v{version}-linux-x86_64-", dir=output))
        try:
            artifacts.replace(destination)
        except BaseException:
            destination.rmdir()  # Refuses removal if something unexpected appeared.
            raise
    print("Local candidate: " + str(destination / filename))
    print("Checksum: " + str(destination / (filename + ".sha256")))
    print("Packaging does not install, publish, or verify client runtime compatibility.")


def interrupted(_signal, _frame):
    raise KeyboardInterrupt


if __name__ == "__main__":
    for signum in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    try:
        main()
    except (OSError, ValueError, UnicodeError, subprocess.CalledProcessError, KeyboardInterrupt) as error:
        print(str(error) if isinstance(error, ValueError) else "Packaging stopped; no completed candidate was published.", file=sys.stderr)
        sys.exit(1)
