"""Verify that server deployments cannot rebuild or follow shared image tags."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
API_IMAGE = "sha256:" + "1" * 64
WEB_IMAGE = "sha256:" + "2" * 64


@unittest.skipUnless(shutil.which("docker"), "Docker Compose is required")
class ServerComposeTests(unittest.TestCase):
    def config(self, *, server=True, omit=None, channel="develop"):
        env = {
            key: value
            for key, value in os.environ.items()
            if key not in {"API_IMAGE", "WEB_IMAGE", "COMPOSE_FILE", "COMPOSE_PROFILES"}
        }
        env.update(
            API_IMAGE=API_IMAGE,
            WEB_IMAGE=WEB_IMAGE,
            APP_CHANNEL=channel,
            WEB_NETWORK_ALIAS=f"unipath-{channel}-web",
        )
        if omit:
            env.pop(omit)
        command = [
            "docker",
            "compose",
            "--project-name",
            "unipath-image-pin-test",
            "--env-file",
            str(ROOT / ".env.example"),
            "-f",
            str(ROOT / "compose.yaml"),
        ]
        if server:
            command.extend(["-f", str(ROOT / "compose.server.yaml")])
        return subprocess.run(
            [*command, "config", "--format", "json"],
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_server_uses_same_immutable_backend_for_api_and_migrations(self):
        result = self.config()
        self.assertEqual(result.returncode, 0, result.stderr)
        services = json.loads(result.stdout)["services"]
        for name, expected in (
            ("api", API_IMAGE),
            ("migrate", API_IMAGE),
            ("web", WEB_IMAGE),
        ):
            with self.subTest(service=name):
                self.assertEqual(services[name]["image"], expected)
                self.assertNotIn("build", services[name])
                self.assertEqual(services[name]["pull_policy"], "never")

    def test_each_image_is_required_before_server_can_start(self):
        for variable in ("API_IMAGE", "WEB_IMAGE"):
            with self.subTest(variable=variable):
                result = self.config(omit=variable)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(variable, result.stderr)

    def test_channel_name_does_not_select_a_mutable_image_tag(self):
        for channel in ("develop", "product"):
            with self.subTest(channel=channel):
                result = self.config(channel=channel)
                self.assertEqual(result.returncode, 0, result.stderr)
                services = json.loads(result.stdout)["services"]
                self.assertEqual(services["api"]["image"], API_IMAGE)
                self.assertEqual(services["web"]["image"], WEB_IMAGE)

    def test_local_development_still_builds_backend(self):
        result = self.config(server=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        services = json.loads(result.stdout)["services"]
        for name in ("api", "migrate"):
            self.assertEqual(services[name]["image"], "unipath-backend:local")
            self.assertIn("build", services[name])


if __name__ == "__main__":
    unittest.main()
