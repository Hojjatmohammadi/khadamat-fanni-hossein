from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AndroidReleaseBuildTests(unittest.TestCase):
    def test_github_release_build_targets_arm64_and_publishes_checksum(self) -> None:
        workflow = (ROOT / ".github/workflows/android-apk.yml").read_text(
            encoding="utf-8"
        )
        build_commands = [
            line.strip()
            for line in workflow.splitlines()
            if "flutter build apk" in line
        ]

        self.assertEqual(len(build_commands), 1)
        command = build_commands[0]
        self.assertIn("--target-platform=android-arm64", command)
        self.assertIn("--obfuscate", command)
        self.assertIn("--split-debug-info=build/symbols", command)
        self.assertIn("app-release.apk.sha256", workflow)
        self.assertIn("hashlib.sha256", workflow)

    def test_codemagic_release_build_matches_github_arm64_configuration(self) -> None:
        workflow = (ROOT / "codemagic.yaml").read_text(encoding="utf-8")
        build_commands = [
            line.strip()
            for line in workflow.splitlines()
            if "flutter build apk" in line
        ]

        self.assertEqual(len(build_commands), 1)
        command = build_commands[0]
        self.assertIn("--target-platform=android-arm64", command)
        self.assertIn("--obfuscate", command)
        self.assertIn("--split-debug-info=build/symbols", command)
        self.assertIn("app-release.apk.sha256", workflow)
        self.assertIn("hashlib.sha256", workflow)

    def test_release_and_emulator_build_workflows_require_manual_dispatch(self) -> None:
        for relative_path in (
            ".github/workflows/android-apk.yml",
            ".github/workflows/android-emulator.yml",
        ):
            workflow = (ROOT / relative_path).read_text(encoding="utf-8")
            header = workflow.split("permissions:", maxsplit=1)[0]
            self.assertIn("on:\n  workflow_dispatch:", header, relative_path)
            self.assertNotIn("  push:", header, relative_path)

    def test_regular_flutter_ci_does_not_build_or_install_an_apk(self) -> None:
        workflow = (ROOT / ".github/workflows/flutter-ci.yml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("flutter build apk", workflow)
        self.assertNotIn("android-emulator-runner", workflow)


if __name__ == "__main__":
    unittest.main()
