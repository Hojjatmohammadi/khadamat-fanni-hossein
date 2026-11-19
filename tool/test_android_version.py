from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from android_version import (
    AndroidVersionError,
    MINIMUM_BUILD_NUMBER,
    validate_android_build_number,
)


class AndroidVersionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _write(self, content: str) -> None:
        (self.root / "pubspec.yaml").write_text(content, encoding="utf-8")

    def test_accepts_minimum_safe_update_build_number(self) -> None:
        self._write(f"version: 1.0.1+{MINIMUM_BUILD_NUMBER}\n")
        self.assertEqual(
            validate_android_build_number(self.root),
            ("1.0.1", MINIMUM_BUILD_NUMBER),
        )

    def test_accepts_higher_build_number(self) -> None:
        self._write("version: 1.0.2+2003\n")
        self.assertEqual(validate_android_build_number(self.root), ("1.0.2", 2003))

    def test_rejects_build_number_that_would_downgrade_previous_arm64_apk(self) -> None:
        self._write("version: 1.0.1+2001\n")
        with self.assertRaisesRegex(AndroidVersionError, "previously distributed ARM64"):
            validate_android_build_number(self.root)

    def test_rejects_version_without_build_number(self) -> None:
        self._write("version: 1.0.1\n")
        with self.assertRaisesRegex(AndroidVersionError, "exactly one version"):
            validate_android_build_number(self.root)

    def test_rejects_duplicate_version_declarations(self) -> None:
        self._write("version: 1.0.1+2002\nversion: 1.0.2+2003\n")
        with self.assertRaisesRegex(AndroidVersionError, "exactly one version"):
            validate_android_build_number(self.root)

    def test_rejects_missing_pubspec(self) -> None:
        with self.assertRaisesRegex(AndroidVersionError, "Missing Flutter package"):
            validate_android_build_number(self.root)


if __name__ == "__main__":
    unittest.main()
