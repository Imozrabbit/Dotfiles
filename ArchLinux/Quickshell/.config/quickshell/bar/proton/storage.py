"""Validated Proton installations and filesystem transaction primitives."""
import hashlib
import os
import re
import stat
import contextlib
import ctypes
import errno
import fcntl
import json
import posixpath
import shutil
import tarfile
import tempfile
import tomllib
import uuid
from pathlib import Path


def version_info(name):
    ge = re.fullmatch(r"GE-Proton(\d+)-(\d+)(?:-(\d+))?", name)
    if ge:
        return "ge", [int(part or 0) for part in ge.groups()]
    cachy = re.fullmatch(r"proton-cachyos-(?:(\d+)\.(\d+)-)?(\d{8})-slr-x86_64_v3", name)
    if cachy:
        major, minor, date = cachy.groups()
        return "cachyos", [int(date), int(major or 0), int(minor or 0)]
    raise ValueError("Unsupported Proton installation name")


def read_regular(path, limit=1024 * 1024):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("Expected regular file")
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError("File exceeds size limit")
        return data


def parse_vdf(text):
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}]|[^\s{}"]+', re.sub(r"//[^\n]*", "", text))
    index = 0

    def word(token):
        if token.startswith('"'):
            return token[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        return token

    def object_(nested=False, depth=0):
        nonlocal index
        if depth > 16:
            raise ValueError("VDF nesting exceeds limit")
        result = {}
        while index < len(tokens):
            token = tokens[index]
            index += 1
            if token == "}":
                if not nested:
                    raise ValueError("Invalid VDF")
                return result
            if token == "{" or index >= len(tokens):
                raise ValueError("Invalid VDF")
            key = word(token)
            value = tokens[index]
            index += 1
            if key in result or value == "}":
                raise ValueError("Ambiguous VDF")
            result[key] = object_(True, depth + 1) if value == "{" else word(value)
        if nested:
            raise ValueError("Unclosed VDF")
        return result

    return object_()


def validate_installation(path):
    path = Path(path)
    family, version = version_info(path.name)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode):
        raise ValueError("Installation must be a real directory")
    metadata = read_regular(path / "compatibilitytool.vdf")
    tools = parse_vdf(metadata.decode("utf-8"))["compatibilitytools"]["compat_tools"]
    if not isinstance(tools, dict) or len(tools) != 1:
        raise ValueError("Invalid compatibility metadata")
    tool_name, tool = next(iter(tools.items()))
    if tool_name != path.name or not isinstance(tool, dict) or tool.get("install_path") != ".":
        raise ValueError("Installation metadata/name mismatch")
    manifest = parse_vdf(read_regular(path / "toolmanifest.vdf").decode("utf-8"))
    if not isinstance(manifest.get("manifest"), dict) or "proton" not in manifest["manifest"].get("commandline", ""):
        raise ValueError("Invalid Proton manifest")
    read_regular(path / "proton", 4 * 1024 * 1024)
    if not (path / "proton").stat().st_mode & 0o111:
        raise ValueError("Proton launcher is not executable")
    return {"name": path.name, "family": family, "version": version, "path": str(path),
            "identity": {"device": info.st_dev, "inode": info.st_ino,
                         "modified": str(info.st_mtime_ns), "metadata": hashlib.sha256(metadata).hexdigest()}}


def real_directory(path):
    path = Path(path)
    if not path.is_absolute():
        raise ValueError("Expected absolute directory")
    for part in reversed([path, *path.parents]):
        if not stat.S_ISDIR(part.lstat().st_mode):
            raise ValueError("Directory path contains a symlink or non-directory")
    return path


@contextlib.contextmanager
def operation_lock(base):
    base = real_directory(base)
    fd = os.open(base / ".proton-manager.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError("Invalid operation lock")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("Another Proton operation is running.") from error
        yield
    finally:
        os.close(fd)


def rename_no_replace(source, destination):
    # Linux renameat2 preserves an existing destination even if it appears mid-operation.
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renameat2
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(-100, os.fsencode(source), -100, os.fsencode(destination), 1) != 0:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(destination))


def extract_verified(archive, staging, max_members=500000, max_bytes=30 * 1024**3):
    staging = Path(staging)
    real_directory(staging.parent)
    staging.mkdir(mode=0o700)
    with tarfile.open(archive, "r:*") as tar:
        members = {}
        total = 0
        root_name = None
        for count, member in enumerate(tar, 1):
            raw = member.name
            if count > max_members or raw.startswith("/") or ".." in raw.split("/") or "\0" in raw:
                raise ValueError("Unsafe archive path or member limit exceeded")
            name = posixpath.normpath(raw)
            if name == "." and member.isdir():
                continue
            root = name.split("/")[0]
            version_info(root)
            if root_name is not None and root != root_name:
                raise ValueError("Archive has multiple installation roots")
            root_name = root
            if name in members and not (member.isdir() and members[name].isdir()):
                raise ValueError("Archive has duplicate/conflicting paths")
            if not (member.isdir() or member.isfile() or member.issym() or member.islnk()):
                raise ValueError("Archive contains unsupported entry type")
            total += member.size
            if member.size < 0 or total > max_bytes:
                raise ValueError("Archive exceeds extracted-size limit")
            members[name] = member
        if root_name is None:
            raise ValueError("Empty archive")
        links = {name for name, member in members.items() if member.issym() or member.islnk()}
        for name, member in members.items():
            parts = name.split("/")
            if any("/".join(parts[:index]) in links for index in range(1, len(parts))):
                raise ValueError("Archive writes through a link")
            if member.issym() or member.islnk():
                if member.linkname.startswith("/") or "\0" in member.linkname:
                    raise ValueError("Absolute archive link")
                target = posixpath.normpath(posixpath.join(posixpath.dirname(name), member.linkname) if member.issym() else member.linkname)
                if target != root_name and not target.startswith(root_name + "/"):
                    raise ValueError("Archive link escapes installation")
                if member.islnk() and (target not in members or not members[target].isfile()):
                    raise ValueError("Hard link target is not a regular archive file")
        for name, member in members.items():
            destination = staging / name
            destination.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
            if member.isdir():
                destination.mkdir(exist_ok=True, mode=0o755)
            elif member.isfile():
                source = tar.extractfile(member)
                if source is None:
                    raise ValueError("Missing archive content")
                with source, destination.open("xb") as output:
                    shutil.copyfileobj(source, output, 1024 * 1024)
                if destination.stat().st_size != member.size:
                    raise ValueError("Truncated archive content")
                destination.chmod(0o755 if member.mode & 0o111 else 0o644)
        for name, member in members.items():
            destination = staging / name
            if member.issym():
                destination.symlink_to(member.linkname)
            elif member.islnk():
                os.link(staging / posixpath.normpath(member.linkname), destination, follow_symlinks=False)
        root = staging / root_name
        for name in links:
            resolved = (staging / name).resolve()
            if not resolved.is_relative_to(root):
                raise ValueError("Archive link chain escapes installation")
        validate_installation(root)
        return root


def activate(staged, base, name):
    base = real_directory(base)
    staged = Path(staged)
    real_directory(staged.parent)
    item = validate_installation(staged)
    if item["name"] != name:
        raise ValueError("Extracted installation does not match selected release")
    target = base / name
    rename_no_replace(staged, target)
    return target


def remove_installation(base, name, expected_identity):
    base = real_directory(base)
    version_info(name)
    target = base / name
    if validate_installation(target)["identity"] != expected_identity:
        raise ValueError("Installation changed; confirm removal again.")
    if not shutil.rmtree.avoids_symlink_attacks:
        raise ValueError("Safe directory removal unavailable")
    quarantine = base / (".proton-trash-" + uuid.uuid4().hex)
    rename_no_replace(target, quarantine)
    try:
        info = quarantine.lstat()
        if info.st_dev != expected_identity["device"] or info.st_ino != expected_identity["inode"]:
            raise ValueError("Installation identity changed during removal")
        shutil.rmtree(quarantine)
    except Exception:
        if quarantine.exists() and not target.exists():
            rename_no_replace(quarantine, target)
        raise


def write_umu_selection(config_path, proton_path, expected_digest):
    path = Path(config_path)
    real_directory(path.parent)
    original = read_regular(path)
    identity = path.lstat()
    if hashlib.sha256(original).hexdigest() != expected_digest:
        raise ValueError("umu configuration changed; refresh and retry.")
    text = original.decode("utf-8")
    before = tomllib.loads(text)
    if not isinstance(before.get("umu"), dict):
        raise ValueError("umu table missing; configure launcher first.")
    lines = text.splitlines(keepends=True)
    headers = [index for index, line in enumerate(lines) if re.fullmatch(r"\s*\[\s*(?:umu|\"umu\"|'umu')\s*\]\s*(?:#[^\r\n]*)?\r?\n?", line)]
    if len(headers) != 1:
        raise ValueError("Unsupported or ambiguous umu table syntax")
    start = headers[0] + 1
    end = next((index for index in range(start, len(lines)) if re.match(r"\s*\[", lines[index])), len(lines))
    matches = [index for index in range(start, end) if re.match(r"\s*(?:proton|\"proton\"|'proton')\s*=", lines[index])]
    newline = "\r\n" if "\r\n" in text else "\n"
    encoded = json.dumps(proton_path, ensure_ascii=True)
    if len(matches) == 1:
        index = matches[0]
        # Only single-line quoted strings are editable; parsed-equivalence check guards all others.
        match = re.fullmatch(r"(\s*(?:proton|\"proton\"|'proton')\s*=\s*)(\"(?:\\.|[^\"\\\r\n])*\"|'[^'\r\n]*')(\s*(?:#[^\r\n]*)?)(\r?\n)?", lines[index])
        if not match:
            raise ValueError("Unsupported proton value syntax")
        lines[index] = match.group(1) + encoded + match.group(3) + (match.group(4) or "")
    elif not matches and "proton" not in before["umu"]:
        if start and not lines[start - 1].endswith("\n"):
            lines[start - 1] += newline
        lines.insert(start, "proton = " + encoded + newline)
    else:
        raise ValueError("Unsupported or ambiguous proton key syntax")
    replacement = "".join(lines).encode("utf-8")
    after = tomllib.loads(replacement.decode())
    expected = {**before, "umu": {**before["umu"], "proton": proton_path}}
    if after != expected:
        raise ValueError("TOML update changes unrelated settings")
    fd, temporary = tempfile.mkstemp(prefix=".proton-umu-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            os.fchmod(output.fileno(), stat.S_IMODE(identity.st_mode))
            output.write(replacement)
            output.flush()
            os.fsync(output.fileno())
        now = path.lstat()
        if now.st_ino != identity.st_ino or now.st_dev != identity.st_dev or read_regular(path) != original:
            raise ValueError("umu configuration changed; refresh and retry.")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
