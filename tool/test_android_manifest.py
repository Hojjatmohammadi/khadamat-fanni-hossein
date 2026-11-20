from __future__ import annotations

import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from android_manifest import (
    ANDROID_NS,
    APP_LABEL,
    BOOT_ACTIONS,
    PERMISSIONS,
    RECEIVER_NAMES,
    AndroidManifestError,
    configure_android_manifest,
)


class AndroidManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.manifest = (
            self.root / "android/app/src/main/AndroidManifest.xml"
        )
        self.manifest.parent.mkdir(parents=True)
        self.manifest.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
            'package="com.example.shop">\n'
            '    <application android:label="Old label" '
            'android:icon="@mipmap/ic_launcher">\n'
            '    </application>\n'
            '</manifest>\n',
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _root(self) -> ET.Element:
        return ET.parse(self.manifest).getroot()

    def test_configures_label_permissions_and_notification_receivers(self) -> None:
        configure_android_manifest(self.root)
        root = self._root()
        app = root.find("application")
        self.assertIsNotNone(app)
        assert app is not None
        self.assertEqual(app.get(ANDROID_NS + "label"), APP_LABEL)

        permission_names = {
            node.get(ANDROID_NS + "name")
            for node in root.findall("uses-permission")
        }
        self.assertTrue(set(PERMISSIONS).issubset(permission_names))

        receivers = {
            node.get(ANDROID_NS + "name"): node
            for node in app.findall("receiver")
        }
        self.assertTrue(set(RECEIVER_NAMES).issubset(receivers))
        boot_actions = {
            action.get(ANDROID_NS + "name")
            for action in receivers[RECEIVER_NAMES[1]].findall(
                "./intent-filter/action"
            )
        }
        self.assertTrue(set(BOOT_ACTIONS).issubset(boot_actions))

    def test_configuration_is_idempotent(self) -> None:
        configure_android_manifest(self.root)
        first = self.manifest.read_text(encoding="utf-8")
        configure_android_manifest(self.root)
        second = self.manifest.read_text(encoding="utf-8")
        self.assertEqual(second, first)

        root = self._root()
        app = root.find("application")
        self.assertIsNotNone(app)
        self.assertEqual(
            sum(1 for node in root.findall("uses-permission")
                if node.get(ANDROID_NS + "name") in PERMISSIONS),
            len(PERMISSIONS),
        )
        assert app is not None
        self.assertEqual(
            sum(1 for node in app.findall("receiver")
                if node.get(ANDROID_NS + "name") in RECEIVER_NAMES),
            len(RECEIVER_NAMES),
        )

    def test_replaces_existing_label_without_duplicate_attribute(self) -> None:
        configure_android_manifest(self.root)
        content = self.manifest.read_text(encoding="utf-8")
        self.assertEqual(content.count("android:label="), 1)
        self.assertIn(f'android:label="{APP_LABEL}"', content)

    def test_rejects_manifest_without_application(self) -> None:
        self.manifest.write_text(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android" />',
            encoding="utf-8",
        )
        with self.assertRaisesRegex(AndroidManifestError, "no <application>"):
            configure_android_manifest(self.root)

    def test_rejects_invalid_xml(self) -> None:
        self.manifest.write_text("<manifest><application>", encoding="utf-8")
        with self.assertRaisesRegex(AndroidManifestError, "Invalid Android manifest XML"):
            configure_android_manifest(self.root)

    def test_rejects_missing_manifest_file(self) -> None:
        self.manifest.unlink()
        with self.assertRaisesRegex(AndroidManifestError, "was not generated"):
            configure_android_manifest(self.root)


if __name__ == "__main__":
    unittest.main()
