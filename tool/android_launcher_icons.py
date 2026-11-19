#!/usr/bin/env python3
"""Validate generated Android launcher resources without building an APK."""

from __future__ import annotations

import struct
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


class AndroidLauncherIconError(RuntimeError):
    """Raised when the generated Android launcher icon set is incomplete."""


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _validate_png(path: Path, expected_size: int) -> None:
    if not path.is_file():
        raise AndroidLauncherIconError(f"Missing launcher icon: {path}")
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\\x89PNG\\r\\n\\x1a\\n" or data[12:16] != b"IHDR":
        raise AndroidLauncherIconError(f"Invalid PNG launcher icon: {path}")
    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (expected_size, expected_size):
        raise AndroidLauncherIconError(
            f"Wrong dimensions for {path}: {width}x{height}, expected "
            f"{expected_size}x{expected_size}."
        )


def validate_android_launcher_icons(project_root: Path) -> None:
    """Verify manifest wiring, all legacy densities, and the adaptive XML."""
    res_dir = project_root / "android" / "app" / "src" / "main" / "res"
    manifest = project_root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.is_file():
        raise AndroidLauncherIconError(f"Missing Android manifest: {manifest}")

    try:
        manifest_root = ET.parse(manifest).getroot()
    except ET.ParseError as exc:
        raise AndroidLauncherIconError(f"Invalid Android manifest: {exc}") from exc

    application = manifest_root.find("application")
    if application is None:
        raise AndroidLauncherIconError("Android manifest has no application element.")
    icon_ref = application.get(ANDROID_NS + "icon")
    if icon_ref != "@mipmap/ic_launcher":
        raise AndroidLauncherIconError(
            "Android manifest must reference @mipmap/ic_launcher; "
            f"found {icon_ref!r}."
        )

    for folder, size in DENSITIES.items():
        _validate_png(res_dir / folder / "ic_launcher.png", size)

    adaptive_xml = res_dir / "mipmap-anydpi-v26" / "ic_launcher.xml"
    if not adaptive_xml.is_file():
        raise AndroidLauncherIconError(f"Missing adaptive launcher icon: {adaptive_xml}")
    try:
        adaptive_root = ET.parse(adaptive_xml).getroot()
    except ET.ParseError as exc:
        raise AndroidLauncherIconError(f"Invalid adaptive launcher XML: {exc}") from exc

    child_names = {_local_name(child.tag) for child in adaptive_root}
    if _local_name(adaptive_root.tag) != "adaptive-icon" or not {
        "background",
        "foreground",
    }.issubset(child_names):
        raise AndroidLauncherIconError(
            "Adaptive launcher XML must contain background and foreground layers."
        )


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    validate_android_launcher_icons(root)
    print("Android launcher icons verified: 5 density PNGs and adaptive icon XML.")
