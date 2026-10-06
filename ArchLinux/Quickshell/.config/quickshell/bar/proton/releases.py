"""Official release selection and bounded, checksum-verified downloads."""
import hashlib
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

import storage

REPOS = {"ge": "GloriousEggroll/proton-ge-custom", "cachyos": "CachyOS/proton-cachyos"}
ASSET_HOSTS = {"github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "github-releases.githubusercontent.com"}


def safe_url(url, api=False):
    if not isinstance(url, str) or len(url) > 8192:
        raise ValueError("Invalid release URL")
    parsed = urllib.parse.urlsplit(url)
    hosts = {"api.github.com"} if api else ASSET_HOSTS
    if parsed.scheme != "https" or parsed.hostname not in hosts or parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError("Untrusted release/download URL")
    return url


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        safe_url(newurl)
        return super().redirect_request(request, fp, code, message, headers, newurl)


def open_url(url):
    safe_url(url, api=urllib.parse.urlsplit(url).hostname == "api.github.com")
    request = urllib.request.Request(url, headers={"User-Agent": "Quickshell-Proton-Manager", "Accept": "application/vnd.github+json" if "api.github.com" in url else "*/*"})
    return urllib.request.build_opener(SafeRedirect()).open(request, timeout=30)


def bounded(response, limit):
    data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Upstream response exceeds size limit")
    return data


def select_release(family, metadata):
    if family not in REPOS or not isinstance(metadata, dict) or metadata.get("draft") or metadata.get("prerelease"):
        raise ValueError("Invalid official release metadata")
    tag = metadata.get("tag_name")
    assets = metadata.get("assets")
    if not isinstance(tag, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", tag) or not isinstance(assets, list) or len(assets) > 1000:
        raise ValueError("Invalid release tag/assets")
    pattern = r"(GE-Proton\d+-\d+(?:-\d+)?)-x86_64\.tar\.gz" if family == "ge" else r"(proton-cachyos-(?:\d+\.\d+-)?\d{8}-slr-x86_64_v3)\.tar\.xz"
    candidates = [asset for asset in assets if isinstance(asset, dict) and isinstance(asset.get("name"), str) and re.fullmatch(pattern, asset["name"])]
    if len(candidates) != 1:
        raise ValueError("Requested Proton build unavailable or ambiguous")
    asset = candidates[0]
    name = re.fullmatch(pattern, asset["name"]).group(1)
    if family == "ge" and name != tag:
        raise ValueError("Release tag/archive version mismatch")
    archive_name = asset["name"]
    checksum_name = archive_name.removesuffix(".tar.gz").removesuffix(".tar.xz") + ".sha512sum"
    checksums = [item for item in assets if isinstance(item, dict) and item.get("name") == checksum_name]
    if len(checksums) != 1:
        raise ValueError("Published checksum unavailable or ambiguous; installation blocked.")
    prefix = f"https://github.com/{REPOS[family]}/releases/download/{tag}/"
    urls = []
    for entry in (asset, checksums[0]):
        url = safe_url(entry.get("browser_download_url"))
        if url != prefix + entry["name"]:
            raise ValueError("Asset URL does not belong to selected official release")
        urls.append(url)
    return {"family": family, "tag": tag, "name": name, "version": storage.version_info(name)[1],
            "archiveName": archive_name, "archiveUrl": urls[0], "checksumUrl": urls[1]}


def latest_release(family, fetch=None):
    if family not in REPOS:
        raise ValueError("Unsupported Proton family")
    with (fetch or open_url)(f"https://api.github.com/repos/{REPOS[family]}/releases/latest") as response:
        metadata = json.loads(bounded(response, 4 * 1024 * 1024))
    return select_release(family, metadata)


def download_verified(release, destination, emit_progress, fetch=None):
    fetch = fetch or open_url
    safe_url(release["checksumUrl"])
    safe_url(release["archiveUrl"])
    with fetch(release["checksumUrl"]) as response:
        text = bounded(response, 65536).decode("utf-8")
    matches = []
    for line in text.splitlines():
        match = re.fullmatch(r"([0-9a-fA-F]{128})\s+\*?(.+)", line.strip())
        if match and match.group(2) == release["archiveName"]:
            matches.append(match.group(1).lower())
    if len(matches) != 1:
        raise ValueError("Published checksum does not identify selected archive")
    expected = matches[0]
    path = Path(destination) / release["archiveName"]
    digest = hashlib.sha512()
    count, last_emit = 0, 0
    try:
        with fetch(release["archiveUrl"]) as response, path.open("xb") as output:
            header = getattr(response, "headers", {}).get("Content-Length", "")
            total = int(header) if str(header).isdigit() else None
            if total is not None and total > 4 * 1024**3:
                raise ValueError("Archive exceeds download-size limit")
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                count += len(chunk)
                if count > 4 * 1024**3:
                    raise ValueError("Archive exceeds download-size limit")
                digest.update(chunk)
                output.write(chunk)
                now = time.monotonic()
                if now - last_emit >= 0.25:
                    emit_progress({"stage": "Downloading " + release["name"], "fraction": min(1, count / total) if total else None, "downloadedBytes": count, "totalBytes": total})
                    last_emit = now
            if total is not None and count != total:
                raise ValueError("Incomplete archive download")
        if digest.hexdigest() != expected:
            raise ValueError("Checksum mismatch; existing installations unchanged.")
        emit_progress({"stage": "Checksum verified", "fraction": 1, "downloadedBytes": count, "totalBytes": count})
        return path
    except Exception:
        if path.exists():
            path.unlink()
        raise
