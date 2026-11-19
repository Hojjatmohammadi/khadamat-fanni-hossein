import base64
import shutil
import subprocess
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

    def _create_real_keystore(self) -> tuple[str, bytes]:
        keytool = shutil.which("keytool")
        if keytool is None:
            self.skipTest("keytool is not installed in this environment")

        source_keystore = self.root / "source-test-keystore.jks"
        subprocess.run(
            [
                keytool,
                "-genkeypair",
                "-noprompt",
                "-keystore",
                str(source_keystore),
                "-storetype",
                "JKS",
                "-storepass",
                "store-secret",
                "-keypass",
                "key-secret",
                "-alias",
                "upload",
                "-keyalg",
                "RSA",
                "-keysize",
                "2048",
                "-validity",
                "30",
                "-dname",
                "CN=Khadamat Fanni Test, OU=QA, O=Local, L=Test, ST=Test, C=IR",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return keytool, source_keystore.read_bytes()

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
        self.assertIn("-certreq", run.call_args.args[0])
        self.assertIn("-storetype", run.call_args.args[0])
        self.assertIn("-keypass", run.call_args.args[0])
        self.assertIn("key-secret", run.call_args.args[0])
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

    def test_real_jks_key_and_password_are_validated_before_gradle_configuration(self) -> None:
        keytool, keystore_bytes = self._create_real_keystore()
        gradle = self._write_gradle(
            "build.gradle",
            "android {\n    buildTypes {\n        release {\n"
            "            signingConfig = signingConfigs.debug\n"
            "        }\n    }\n}\n",
        )
        environment = dict(self.environment)
        environment["ANDROID_KEYSTORE_BASE64"] = base64.b64encode(
            keystore_bytes
        ).decode("ascii")

        configured_keystore = configure_release_signing(
            self.root,
            environment,
            keytool_path=keytool,
        )

        self.assertEqual(configured_keystore.read_bytes(), keystore_bytes)
        self.assertTrue((self.root / "android" / "key.properties").is_file())
        self.assertIn(
            "signingConfig = signingConfigs.release",
            gradle.read_text(encoding="utf-8"),
        )
        self.assertEqual(
            sorted(path.name for path in (self.root / "android").iterdir()),
            ["app", "key.properties", "upload-keystore.jks"],
        )

    def test_real_jks_rejects_wrong_private_key_password_and_cleans_up(self) -> None:
        keytool, keystore_bytes = self._create_real_keystore()
        gradle = self._write_gradle(
            "build.gradle",
            "android {\n    buildTypes {\n        release {\n"
            "            signingConfig = signingConfigs.debug\n"
            "        }\n    }\n}\n",
        )
        original_gradle = gradle.read_text(encoding="utf-8")
        environment = dict(self.environment)
        environment["ANDROID_KEYSTORE_BASE64"] = base64.b64encode(
            keystore_bytes
        ).decode("ascii")
        environment["ANDROID_KEY_PASSWORD"] = "wrong-private-key-password"

        with self.assertRaisesRegex(
            AndroidSigningError,
            "private key is invalid",
        ):
            configure_release_signing(
                self.root,
                environment,
                keytool_path=keytool,
            )

        self.assertFalse(
            (self.root / "android" / "upload-keystore.jks").exists()
        )
        self.assertFalse((self.root / "android" / "key.properties").exists())
        self.assertEqual(gradle.read_text(encoding="utf-8"), original_gradle)

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
    def test_invalid_private_key_password_is_rejected_before_configuration(self, run) -> None:
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
