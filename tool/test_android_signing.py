import base64
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from android_signing import (
    AndroidSigningError,
    configure_release_signing,
)


class AndroidSigningTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "android" / "app").mkdir(parents=True)
        self.environment = {
            "ANDROID_KEYSTORE_BASE64": base64.b64encode(b"jks-test-data" * 64).decode("ascii"),
            "ANDROID_KEYSTORE_PASSWORD": "store-secret",
            "ANDROID_KEY_ALIAS": "upload",
            "ANDROID_KEY_PASSWORD": "key-secret",
        }

    def _write_gradle(self, filename: str, source: str) -> Path:
        path = self.root / "android" / "app" / filename
        path.write_text(source, encoding="utf-8")
        return path

    @patch("android_signing.subprocess.run")
    def test_configures_groovy_release_signing(self, run) -> None:
        gradle = self._write_gradle(
            "build.gradle",
            """plugins {
    id 'com.android.application'
}

android {
    namespace 'com.example.old'
    buildTypes {
        release {
            signingConfig = signingConfigs.debug
        }
    }
}
""",
        )

        keystore = configure_release_signing(
            self.root, self.environment, keytool_path="/usr/bin/keytool"
        )

        result = gradle.read_text(encoding="utf-8")
        self.assertLess(result.index("def keystoreProperties"), result.index("android {"))
        self.assertLess(result.index("signingConfigs {"), result.index("buildTypes {"))
        self.assertIn("signingConfig = signingConfigs.release", result)
        self.assertIn("storeType = keystoreProperties['storeType']", result)
        self.assertNotIn("signingConfigs.debug", result)
        self.assertEqual(keystore.read_bytes(), base64.b64decode(self.environment["ANDROID_KEYSTORE_BASE64"]))
        self.assertIn("storeFile=../upload-keystore.jks", (self.root / "android" / "key.properties").read_text())
        self.assertIn("-storetype", run.call_args.args[0])
        self.assertEqual(run.call_args.kwargs["check"], True)

    @patch("android_signing.subprocess.run")
    def test_configures_kotlin_release_signing(self, run) -> None:
        gradle = self._write_gradle(
            "build.gradle.kts",
            """plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.old"
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
""",
        )

        configure_release_signing(
            self.root, self.environment, keytool_path="/usr/bin/keytool"
        )

        result = gradle.read_text(encoding="utf-8")
        self.assertLess(result.index("val keystoreProperties"), result.index("android {"))
        self.assertLess(result.index('create("release")'), result.index("buildTypes {"))
        self.assertIn(
            'signingConfig = signingConfigs.getByName("release")',
            result,
        )
        self.assertIn('storeType = keystoreProperties.getProperty("storeType")', result)
        self.assertNotIn('getByName("debug")', result)
        self.assertTrue(run.called)

    def test_missing_signing_secrets_fail_before_writing_files(self) -> None:
        self._write_gradle(
            "build.gradle",
            "android {\n    buildTypes {\n        release {\n"
            "            signingConfig = signingConfigs.debug\n"
            "        }\n    }\n}\n",
        )
        with self.assertRaises(AndroidSigningError):
            configure_release_signing(self.root, {}, keytool_path="/usr/bin/keytool")
        self.assertFalse((self.root / "android" / "upload-keystore.jks").exists())

    def test_invalid_base64_is_rejected(self) -> None:
        self._write_gradle(
            "build.gradle",
            "android {\n    buildTypes {\n        release {\n"
            "            signingConfig = signingConfigs.debug\n"
            "        }\n    }\n}\n",
        )
        environment = dict(self.environment)
        environment["ANDROID_KEYSTORE_BASE64"] = "%%%invalid%%%"
        with self.assertRaises(AndroidSigningError):
            configure_release_signing(self.root, environment, keytool_path="/usr/bin/keytool")

    @patch("android_signing.subprocess.run", side_effect=__import__("subprocess").CalledProcessError(1, "keytool"))
    def test_invalid_keystore_is_removed_and_not_configured(self, run) -> None:
        gradle = self._write_gradle(
            "build.gradle",
            "android {\n    buildTypes {\n        release {\n"
            "            signingConfig = signingConfigs.debug\n"
            "        }\n    }\n}\n",
        )
        original = gradle.read_text(encoding="utf-8")
        with self.assertRaises(AndroidSigningError):
            configure_release_signing(
                self.root, self.environment, keytool_path="/usr/bin/keytool"
            )
        self.assertFalse((self.root / "android" / "upload-keystore.jks").exists())
        self.assertEqual(gradle.read_text(encoding="utf-8"), original)
        self.assertFalse((self.root / "android" / "key.properties").exists())


if __name__ == "__main__":
    unittest.main()
