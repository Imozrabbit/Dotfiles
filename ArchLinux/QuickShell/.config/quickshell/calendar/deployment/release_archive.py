"""Calendar's runtime-release format and bounded GitHub transport (stdlib only)."""
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile
import time
import urllib.error
import urllib.parse
import urllib.request

REPOSITORY = "Imozrabbit/Dotfiles"
MAX_ARCHIVE = 64 * 1024 * 1024
MAX_UNPACKED = 128 * 1024 * 1024
MAX_FILE = 48 * 1024 * 1024
NATIVE = {"parse/convert", "parse/calendar-sync-helper"}
ROOT_FILES = {"VERSION", "shell.qml", "install.sh", "update.sh", "release-files.txt"}
REQUIRED = ROOT_FILES | NATIVE | {"parse/conflict-broker.sh", "deployment/deploy.py", "deployment/release_archive.py"}
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*))?(?:-beta\.(?:0|[1-9][0-9]*))?"
HOSTS = {"api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version_key(version):
    require(isinstance(version, str) and re.fullmatch(VERSION, version), "Unsupported Calendar release version.")
    base, beta_marker, beta = version.partition("-beta.")
    return (*((list(map(int, base.split("."))) + [0])[:3]), 0 if beta_marker else 1, int(beta) if beta_marker else 0)


def read_owned(path, limit):
    """Read one owned bounded regular file, rejecting links and changed snapshots."""
    before = path.lstat()
    require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid() and before.st_nlink == 1
            and not before.st_mode & 0o022 and 0 <= before.st_size <= limit,
            "Input must be an owned, bounded, unlinked regular file: " + str(path))
    def identity(stamp):
        return (stamp.st_dev, stamp.st_ino, stamp.st_mode, stamp.st_uid, stamp.st_gid,
                stamp.st_nlink, stamp.st_size, stamp.st_mtime_ns, stamp.st_ctime_ns)
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
        require(identity(os.fstat(stream.fileno())) == identity(before), "Input changed while opening it.")
        data = stream.read(limit + 1)
        require(len(data) <= limit and identity(os.fstat(stream.fileno())) == identity(before)
                and identity(path.lstat()) == identity(before), "Input changed while reading it.")
    return data


def safe_url(url):
    require(isinstance(url, str) and not re.search(r"[\x00-\x20\x7f\\]", url), "Unsafe release URL.")
    parsed = urllib.parse.urlsplit(url)
    require(parsed.scheme == "https" and parsed.hostname in HOSTS and parsed.port in (None, 443)
            and not parsed.username and not parsed.password and not parsed.fragment, "Release URLs must stay on approved HTTPS hosts.")


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    max_repeats = 1
    max_redirections = 5

    def redirect_request(self, request, fp, code, message, headers, newurl):
        safe_url(newurl)
        return super().redirect_request(request, fp, code, message, headers, newurl)


def download(url, limit):
    safe_url(url)
    request = urllib.request.Request(url, headers={"User-Agent": "quickshell-calendar-installer/1",
                                                 "Accept": "application/vnd.github+json" if "api.github.com/" in url else "application/octet-stream"})
    started = time.monotonic()
    try:
        with urllib.request.build_opener(HTTPSRedirect()).open(request, timeout=20) as response:
            safe_url(response.geturl())
            require(response.headers.get("Content-Encoding", "identity") == "identity", "Unexpected release content encoding.")
            length = response.headers.get("Content-Length")
            require(length is None or (re.fullmatch(r"[0-9]+", length) and int(length) <= limit), "Release download exceeds its limit.")
            data = bytearray()
            while True:
                require(time.monotonic() - started < 120, "Release download exceeded its time limit.")
                block = response.read(min(65536, limit + 1 - len(data)))
                if not block:
                    break
                data.extend(block)
                require(len(data) <= limit, "Release download exceeds its limit.")
            require(length is None or len(data) == int(length), "Release download was truncated.")
            return bytes(data)
    except (urllib.error.URLError, TimeoutError) as error:
        raise ValueError("Could not download Calendar release; check connectivity or GitHub API rate limits.") from error


def discover_release(fetch=download):
    versions = {}
    for page in range(1, 11):
        data = json.loads(fetch(f"https://api.github.com/repos/{REPOSITORY}/releases?per_page=100&page={page}", 8 * 1024 * 1024))
        require(isinstance(data, list) and len(data) <= 100, "GitHub release listing is malformed.")
        for item in data:
            require(isinstance(item, dict), "GitHub release listing is malformed.")
            tag = item.get("tag_name", "")
            match = re.fullmatch("calendar-v(" + VERSION + ")", tag) if isinstance(tag, str) else None
            if not match:
                continue
            require(type(item.get("draft")) is bool and type(item.get("prerelease")) is bool, "Calendar release flags are missing.")
            if item["draft"] or item["prerelease"] or "-beta." in match[1]:
                continue
            version = match[1]
            key = version_key(version)
            require(key not in versions, "Calendar release versions are ambiguous or duplicated.")
            versions[key] = (version, item)
        if len(data) < 100:
            break
    else:
        raise ValueError("Too many repository releases to discover Calendar safely.")
    require(versions, "No stable calendar-v<version> release is published.")
    version, item = versions[max(versions)]
    filename = f"calendar-v{version}-linux-x86_64.tar.gz"
    assets = item.get("assets")
    require(isinstance(assets, list), "Calendar release assets are missing.")
    selected = []
    for name in (filename, filename + ".sha256"):
        matches = [asset for asset in assets if isinstance(asset, dict) and asset.get("name") == name]
        require(len(matches) == 1, "Latest Calendar release is missing an unambiguous runtime archive/checksum pair.")
        asset = matches[0]
        require(asset.get("browser_download_url") == f"https://github.com/{REPOSITORY}/releases/download/calendar-v{version}/{name}",
                "Calendar release asset points outside its repository/tag.")
        selected.append(asset)
    return version, *selected


def runtime_member(name):
    if not isinstance(name, str):
        return False
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or str(path) != name:
        return False
    if name in REQUIRED:
        return True
    suffix = {"common": ".js", "services": ".qml", "ui": ".qml"}
    return (len(path.parts) == 2 and path.parts[0] in suffix
            and re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*" + re.escape(suffix[path.parts[0]]), path.name) is not None)


def file_mode(name):
    return 0o755 if name.endswith(".sh") or name in NATIVE else 0o644


def extract_release(archive, checksum, destination, expected_version=None):
    match = re.fullmatch("calendar-v(" + VERSION + r")-linux-x86_64\.tar\.gz", archive.name)
    require(match, "Unsupported Calendar archive filename/platform.")
    version = match[1]
    require(expected_version is None or expected_version == version, "Calendar archive version differs from its release.")
    expected = re.fullmatch(rb"([0-9a-f]{64})  " + re.escape(archive.name.encode("ascii")) + rb"\n?", checksum)
    require(expected, "Calendar checksum sidecar is malformed or names another archive.")
    data = read_owned(archive, MAX_ARCHIVE)
    digest = hashlib.sha256(data).hexdigest()
    require(digest == expected[1].decode("ascii"), "Calendar archive SHA-256 checksum does not match.")
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
            unpacked = stream.read(MAX_UNPACKED + 1)
        require(len(unpacked) <= MAX_UNPACKED, "Calendar archive expands beyond its limit.")
        with tarfile.open(fileobj=io.BytesIO(unpacked), mode="r:") as stream:
            members, files, directories = {}, {}, set()
            for member in stream:
                name = member.name
                require(len(members) < 512 and name not in members, "Calendar archive has duplicate or too many entries.")
                members[name] = member
                path = PurePosixPath(name)
                require(str(path) == name and not path.is_absolute() and ".." not in path.parts
                        and path.parts[0] == "calendar" and not member.pax_headers,
                        "Calendar archive contains an unsafe/noncanonical path or header.")
                require(member.uid == member.gid == member.mtime == 0 and not member.uname and not member.gname,
                        "Calendar archive metadata is not normalized.")
                if member.isdir():
                    require(member.mode == 0o755 and member.size == 0, "Unsafe Calendar directory metadata.")
                    directories.add(name)
                    continue
                relative = str(PurePosixPath(*path.parts[1:]))
                require(member.isfile() and runtime_member(relative) and 0 <= member.size <= MAX_FILE
                        and member.mode == file_mode(relative), "Calendar archive contains a link, special file or non-runtime member.")
                files[relative] = member
            require(REQUIRED <= files.keys(), "Calendar archive is missing required runtime files.")
            manifest_data = stream.extractfile(files["release-files.txt"]).read(65537)
            require(len(manifest_data) <= 65536, "Calendar runtime manifest is oversized.")
            manifest = manifest_data.decode("utf-8").splitlines()
            require(len(manifest) == len(set(manifest)) and set(manifest) == files.keys(), "Calendar archive differs from its explicit runtime manifest.")
            require(all(runtime_member(name) for name in manifest), "Calendar runtime manifest is unsafe.")
            expected_dirs = {"calendar"}
            for name in files:
                expected_dirs.update(str(parent) for parent in PurePosixPath("calendar", name).parents if str(parent) != ".")
            require(directories == expected_dirs, "Calendar archive has unexpected/missing directories.")
            require(stream.extractfile(files["VERSION"]).read(129) in (version.encode("ascii"), (version + "\n").encode("ascii")), "Calendar VERSION differs from archive/tag.")
            for name in NATIVE:
                header = stream.extractfile(files[name]).read(64)
                require(len(header) == 64 and header[:7] == b"\x7fELF\x02\x01\x01"
                        and header[16:18] in (b"\x02\x00", b"\x03\x00") and header[18:24] == b"\x3e\x00\x01\x00\x00\x00",
                        "Calendar helper is not a Linux x86_64 ELF executable.")
            # Everything is validated before publishing any archive member. Never
            # let tar metadata create links, owners, devices or implicit parents.
            destination.mkdir(mode=0o700)
            for name in sorted(directories, key=lambda value: (value.count("/"), value)):
                (destination / name).mkdir(mode=0o700)
            inventory = {}
            for name, member in files.items():
                contents = stream.extractfile(member).read(MAX_FILE + 1)
                require(len(contents) == member.size, "Calendar runtime member is truncated.")
                path = destination / "calendar" / name
                with path.open("xb") as output:
                    output.write(contents)
                path.chmod(file_mode(name))
                inventory[name] = {"sha256": hashlib.sha256(contents).hexdigest(), "mode": file_mode(name)}
    except (gzip.BadGzipFile, EOFError, tarfile.TarError, UnicodeError) as error:
        raise ValueError("Calendar runtime archive is malformed.") from error
    return {"version": version, "sha256": digest, "files": inventory}
