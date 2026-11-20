import tempfile
import unittest
from pathlib import Path

from android_identity import (
    APPLICATION_ID,
    AndroidProjectError,
    configure_android_project,
)


class AndroidIdentityTests(unittest.TestCase):
    def _project(self, gradle_name: str, gradle_text: str, package: str = APPLICATION_ID) -> Path:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        app = root / "android" / "app"
        app.mkdir(parents=True)
        (app / gradle_name).write_text(gradle_text, encoding="utf-8")
        activity = app / "src" / "main" / "kotlin" / "sample" / "MainActivity.kt"
        activity.parent.mkdir(parents=True)
        activity.write_text(f"package {package}\n\nclass MainActivity\n", encoding="utf-8")
        return root

    def test_configures_kotlin_gradle_identity(self) -> None:
        root = self._project(
            "build.gradle.kts",
            'android {\n    namespace = "com.example.old"\n'
            '    defaultConfig {\n        applicationId = "com.example.old"\n    }\n}\n',
        )
        gradle = configure_android_project(root)
        result = gradle.read_text(encoding="utf-8")
        self.assertEqual(result.count(APPLICATION_ID), 2)
        self.assertNotIn("com.example.old", result)

    def test_configures_groovy_gradle_identity(self) -> None:
        root = self._project(
            "build.gradle",
            "android {\n    namespace 'com.example.old'\n"
            "    defaultConfig {\n        applicationId 'com.example.old'\n    }\n}\n",
        )
        gradle = configure_android_project(root)
        result = gradle.read_text(encoding="utf-8")
        self.assertEqual(result.count(APPLICATION_ID), 2)
        self.assertNotIn("com.example.old", result)

    def test_rejects_mismatched_main_activity_package(self) -> None:
        root = self._project(
            "build.gradle.kts",
            'android {\n    namespace = "com.example.old"\n'
            '    defaultConfig {\n        applicationId = "com.example.old"\n    }\n}\n',
            package="com.example.wrong",
        )
        with self.assertRaises(AndroidProjectError):
            configure_android_project(root)

    def test_rejects_ambiguous_gradle_declaration(self) -> None:
        root = self._project(
            "build.gradle.kts",
            'android {\n    namespace = "com.example.old"\n'
            '    defaultConfig {\n        applicationId = "com.example.old"\n'
            '        applicationId = "com.example.duplicate"\n    }\n}\n',
        )
        with self.assertRaises(AndroidProjectError):
            configure_android_project(root)


if __name__ == "__main__":
    unittest.main()
