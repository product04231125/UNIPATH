"""Release gates: avoid publishing the wrong build or unsafe Production configuration."""

import contextlib
import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_app import package_bundle, validate_api_url  # noqa: E402
from publish_app import main as publish  # noqa: E402


class ReleaseTests(unittest.TestCase):
    def test_product_rejects_http_and_loopback(self):
        for url in ["http://unipath.duckdns.org", "https://127.0.0.1", "https://localhost"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                validate_api_url(url, "product", False)

    def test_origin_rejects_credentials_path_and_bad_port(self):
        for url in [
            "https://user:secret@example.org",
            "https://example.org/api/v1",
            "https://example.org?token=secret",
            "https://example.org#fragment",
            "https://example.org:bad",
            "https://example.org:99999",
            "https://example.org&whoami",
            "file:///tmp/config",
        ]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                validate_api_url(url, "develop", True)

    def test_product_https_and_explicit_ip_preview(self):
        self.assertEqual(
            validate_api_url("https://unipath.duckdns.org/", "product", False),
            "https://unipath.duckdns.org",
        )
        self.assertEqual(
            validate_api_url("http://127.0.0.1:8010", "product", True),
            "http://127.0.0.1:8010",
        )

    def create_asset(self, directory, target="web", commit="a" * 40):
        bundle = directory / "bundle"
        bundle.mkdir(exist_ok=True)
        manifest = {
            "channel": "develop",
            "preview": True,
            "target": target,
            "version": "0.1.0",
            "build_number": 1,
            "commit": commit,
            "api_base_url": "https://staging-unipath.duckdns.org",
        }
        encoded = json.dumps(manifest)
        (bundle / "build-info.json").write_text(encoded)
        archive = directory / f"test-{target}.zip"
        package_bundle(bundle, archive)
        archive.with_suffix(".json").write_text(encoded)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_suffix(".zip.sha256").write_text(f"{digest}  {archive.name}\n")
        return archive

    def assert_publish_rejected(self, directory, *extra):
        args = ["publish_app.py", "--assets-dir", str(directory), "--tag", "dev-test", *extra]
        with (
            patch.object(sys, "argv", args),
            patch("publish_app.gh") as github,
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit) as error,
        ):
            publish()
        self.assertEqual(error.exception.code, 2)
        github.assert_not_called()

    def test_missing_windows_requires_explicit_partial_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.create_asset(directory)
            self.assert_publish_rejected(directory)

    def test_corrupt_zip_cannot_be_published(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            archive = self.create_asset(directory)
            archive.write_bytes(archive.read_bytes() + b"corruption")
            self.assert_publish_rejected(directory, "--allow-web-only")

    def test_platforms_from_different_commits_cannot_be_combined(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.create_asset(directory, "web", "a" * 40)
            self.create_asset(directory, "windows", "b" * 40)
            self.assert_publish_rejected(directory)

    def test_archive_and_external_manifest_must_agree(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            archive = self.create_asset(directory)
            external = json.loads(archive.with_suffix(".json").read_text())
            external["api_base_url"] = "https://wrong.example.org"
            archive.with_suffix(".json").write_text(json.dumps(external))
            self.assert_publish_rejected(directory, "--allow-web-only")


if __name__ == "__main__":
    unittest.main()
