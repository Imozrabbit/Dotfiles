import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "proton"))
import releases


def metadata(family="ge"):
    if family == "ge":
        repo, tag = "GloriousEggroll/proton-ge-custom", "GE-Proton11-8"
        names = [tag + "-aarch64.tar.gz", tag + "-x86_64.tar.gz", tag + "-x86_64.sha512sum"]
    else:
        repo, tag = "CachyOS/proton-cachyos", "cachyos-11.0-20261005-slr"
        names = ["proton-cachyos-11.0-20261005-slr-" + arch + ext for arch, ext in
                 [("arm64", ".tar.xz"), ("x86_64", ".tar.xz"), ("x86_64_v3", ".tar.xz"), ("x86_64_v3", ".sha512sum")]]
    return {"tag_name": tag, "assets": [{"name": name, "browser_download_url": f"https://github.com/{repo}/releases/download/{tag}/{name}"} for name in names]}


class ReleaseTests(unittest.TestCase):
    def test_exact_build_selection(self):
        self.assertEqual(releases.select_release("ge", metadata())["name"], "GE-Proton11-8")
        self.assertEqual(releases.select_release("cachyos", metadata("cachyos"))["name"], "proton-cachyos-11.0-20261005-slr-x86_64_v3")

    def test_missing_ambiguous_checksum_blocks(self):
        for assets in [metadata()["assets"][:-1], metadata()["assets"] + [metadata()["assets"][-1]]]:
            with self.assertRaises(ValueError):
                releases.select_release("ge", {"tag_name": "GE-Proton11-8", "assets": assets})

    def test_unsafe_url_and_metadata_rejected(self):
        data = metadata()
        for url in ["http://github.com/bad", "https://localhost/bad", "https://github.com/other/archive", "https://github.com@127.0.0.1/a"]:
            data["assets"][1]["browser_download_url"] = url
            with self.subTest(url=url), self.assertRaises(ValueError):
                releases.select_release("ge", data)

    def test_checksum_filename_mismatch(self):
        release = releases.select_release("ge", metadata())
        with tempfile.TemporaryDirectory(dir="/tmp/opencode") as directory:
            def fetch(url):
                return io.BytesIO(("a" * 128 + "  wrong.tar.gz\n").encode())
            with self.assertRaises(ValueError):
                releases.download_verified(release, Path(directory), lambda data: None, fetch)

    def test_checksum_mismatch_leaves_no_verified_archive(self):
        self.download(b"wrong", valid=False)

    def test_verified_download_streams_progress(self):
        self.download(b"tiny archive", valid=True)

    def download(self, content, valid):
        release = releases.select_release("ge", metadata())
        checksum = hashlib.sha512(b"tiny archive").hexdigest()
        def fetch(url):
            return io.BytesIO((checksum + "  " + release["archiveName"] + "\n").encode() if url.endswith("sha512sum") else content)
        with tempfile.TemporaryDirectory(dir="/tmp/opencode") as directory:
            events = []
            if valid:
                result = releases.download_verified(release, Path(directory), events.append, fetch)
                self.assertEqual(result.read_bytes(), content)
                self.assertEqual(events[-1]["fraction"], 1)
            else:
                with self.assertRaises(ValueError):
                    releases.download_verified(release, Path(directory), events.append, fetch)
                self.assertFalse((Path(directory) / release["archiveName"]).exists())

    def test_metadata_response_bounded_and_invalid_json(self):
        for raw in [b"not json", b"{}", b"x" * (4 * 1024 * 1024 + 1)]:
            with self.assertRaises(ValueError):
                releases.latest_release("ge", lambda url: io.BytesIO(raw))


if __name__ == "__main__":
    unittest.main()
