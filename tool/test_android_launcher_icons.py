from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

from android_launcher_icons import (
    AndroidLauncherIconError,
    DENSITIES,
    PNG_SIGNATURE,
    validate_android_launcher_icons,
)


class AndroidLauncherIconTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        res = self.root / "android/app/src/main/res"
        manifest = self.root / "android/app/src/main/AndroidManifest.xml"
        manifest.parent.mkdir(parents=True)
        manifest.write_text(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            '<application android:icon="@mipmap/ic_launcher" /></manifest>',
            encoding="utf-8",
        )
        for folder, size in DENSITIES.items():
            target = res / folder / "ic_launcher.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            header = (
                PNG_SIGNATURE
                + struct.pack(">I", 13)
                + b"IHDR"
                + struct.pack(">II", size, size)
            )
            target.write_bytes(header + bytes(5))
        adaptive = res / "mipmap-anydpi-v26/ic_launcher.xml"
        adaptive.parent.mkdir(parents=True)
        adaptive.write_text(
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">'
            '<background android:drawable="@color/ic_launcher_background" />'
            '<foreground android:drawable="@drawable/ic_launcher_foreground" />'
            '</adaptive-icon>',
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_accepts_complete_launcher_icon_set(self) -> None:
        validate_android_launcher_icons(self.root)

    def test_rejects_missing_density(self) -> None:
        (self.root / "android/app/src/main/res/mipmap-hdpi/ic_launcher.png").unlink()
        with self.assertRaisesRegex(AndroidLauncherIconError, "Missing launcher icon"):
            validate_android_launcher_icons(self.root)

    def test_rejects_wrong_manifest_icon_reference(self) -> None:
        manifest = self.root / "android/app/src/main/AndroidManifest.xml"
        manifest.write_text(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            '<application android:icon="@mipmap/old_icon" /></manifest>',
            encoding="utf-8",
        )
        with self.assertRaisesRegex(AndroidLauncherIconError, "must reference"):
            validate_android_launcher_icons(self.root)

    def test_rejects_wrong_png_dimensions(self) -> None:
        icon = self.root / "android/app/src/main/res/mipmap-mdpi/ic_launcher.png"
        icon.write_bytes(
            PNG_SIGNATURE
            + struct.pack(">I", 13)
            + b"IHDR"
            + struct.pack(">II", 47, 48)
            + bytes(5)
        )
        with self.assertRaisesRegex(AndroidLauncherIconError, "Wrong dimensions"):
            validate_android_launcher_icons(self.root)

    def test_rejects_incomplete_adaptive_icon(self) -> None:
        adaptive = self.root / "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
        adaptive.write_text("<adaptive-icon><background /></adaptive-icon>", encoding="utf-8")
        with self.assertRaisesRegex(AndroidLauncherIconError, "background and foreground"):
            validate_android_launcher_icons(self.root)


if __name__ == "__main__":
    unittest.main()
