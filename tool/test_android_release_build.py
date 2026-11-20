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

    def test_release_workflow_requires_manual_dispatch(self) -> None:
        workflow = (ROOT / ".github/workflows/android-apk.yml").read_text(
            encoding="utf-8"
        )
        header = workflow.split("permissions:", maxsplit=1)[0]
        self.assertIn("on:\n  workflow_dispatch:", header)
        self.assertNotIn("  push:", header)

    def test_emulator_validation_runs_on_development_branch_without_building_apk(self) -> None:
        workflow = (ROOT / ".github/workflows/android-emulator.yml").read_text(
            encoding="utf-8"
        )
        header = workflow.split("permissions:", maxsplit=1)[0]
        self.assertIn("  push:", header)
        self.assertIn("fix/dashboard-layout-phase2", header)
        self.assertIn("  workflow_dispatch:", header)
        self.assertIn("integration_test/material_localizations_test.dart", workflow)
        self.assertIn("integration_test/app_smoke_test.dart", workflow)
        self.assertNotIn("flutter build apk", workflow)

    def test_regular_flutter_ci_does_not_build_or_install_an_apk(self) -> None:
        workflow = (ROOT / ".github/workflows/flutter-ci.yml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("flutter build apk", workflow)
        self.assertNotIn("android-emulator-runner", workflow)


if __name__ == "__main__":
    unittest.main()
