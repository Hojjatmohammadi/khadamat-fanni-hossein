import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from android_compile_sdk import (
    AndroidCompileSdkError,
    configure_file_picker_compile_sdk,
)


class FilePickerCompileSdkTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.package_dir = (
            self.home / ".pub-cache" / "hosted" / "pub.dev"
            / "file_picker-8.3.7" / "android"
        )
        self.package_dir.mkdir(parents=True)

    def _write(self, name: str, source: str) -> Path:
        path = self.package_dir / name
        path.write_text(source, encoding="utf-8")
        return path

    def test_updates_numeric_groovy_and_flutter_kotlin_declarations(self) -> None:
        groovy = self._write(
            "build.gradle",
            "android {\n    compileSdkVersion 34\n}\n",
        )
        kotlin = self._write(
            "build.gradle.kts",
            "android {\n    compileSdk = flutter.compileSdkVersion\n}\n",
        )

        with patch("android_compile_sdk.Path.home", return_value=self.home):
            changed = configure_file_picker_compile_sdk()

        self.assertEqual(set(changed), {groovy, kotlin})
        self.assertIn("compileSdkVersion 36", groovy.read_text(encoding="utf-8"))
        self.assertIn("compileSdk = 36", kotlin.read_text(encoding="utf-8"))

    def test_is_idempotent_when_already_api_36(self) -> None:
        gradle = self._write(
            "build.gradle",
            "android {\n    compileSdkVersion 36\n}\n",
        )
        original = gradle.read_text(encoding="utf-8")
        with patch("android_compile_sdk.Path.home", return_value=self.home):
            configure_file_picker_compile_sdk()
        self.assertEqual(gradle.read_text(encoding="utf-8"), original)

    def test_rejects_unknown_or_ambiguous_gradle_layout(self) -> None:
        gradle = self._write(
            "build.gradle",
            "android {\n    compileSdk = 34\n    compileSdk = 35\n}\n",
        )
        with patch("android_compile_sdk.Path.home", return_value=self.home):
            with self.assertRaises(AndroidCompileSdkError):
                configure_file_picker_compile_sdk()
        self.assertIn("compileSdk = 34", gradle.read_text(encoding="utf-8"))

    def test_rejects_missing_package(self) -> None:
        with patch("android_compile_sdk.Path.home", return_value=self.home):
            with self.assertRaises(AndroidCompileSdkError):
                configure_file_picker_compile_sdk()


if __name__ == "__main__":
    unittest.main()
