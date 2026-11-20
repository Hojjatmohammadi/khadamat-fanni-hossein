#!/usr/bin/env python3
"""Validate the Android build number against previously distributed APKs."""

from __future__ import annotations

import re
from pathlib import Path

# Previously supplied ARM64 APKs used versionCode 2002.
# Every follow-up installation must use a strictly greater versionCode.
MINIMUM_BUILD_NUMBER = 2003
_VERSION_PATTERN = re.compile(
    r"""(?m)^version:\s*['"]?(?P<name>\d+\.\d+\.\d+)\+(?P<build>\d+)['"]?\s*(?:#.*)?$"""
)


class AndroidVersionError(RuntimeError):
    """Raised when the app version cannot safely update prior installations."""


def validate_android_build_number(project_root: Path) -> tuple[str, int]:
    pubspec = project_root / "pubspec.yaml"
    if not pubspec.is_file():
        raise AndroidVersionError(f"Missing Flutter package manifest: {pubspec}")

    source = pubspec.read_text(encoding="utf-8")
    matches = list(_VERSION_PATTERN.finditer(source))
    if len(matches) != 1:
        raise AndroidVersionError(
            "pubspec.yaml must contain exactly one version in name+build format."
        )

    version_name = matches[0].group("name")
    build_number = int(matches[0].group("build"))
    if build_number < MINIMUM_BUILD_NUMBER:
        raise AndroidVersionError(
            f"Android versionCode must be at least {MINIMUM_BUILD_NUMBER} "
            f"to update the previously distributed ARM64 build 2002; "
            f"found {build_number}."
        )
    return version_name, build_number


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    name, build = validate_android_build_number(root)
    print(f"Android update version verified: {name} (versionCode {build}).")
