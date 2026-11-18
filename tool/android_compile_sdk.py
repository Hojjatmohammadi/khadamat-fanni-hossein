#!/usr/bin/env python3
"""Pin file_picker's generated Android Gradle compile SDK to API 36 safely."""

from __future__ import annotations

import re
from pathlib import Path


class AndroidCompileSdkError(RuntimeError):
    """Raised when the resolved file_picker Gradle files cannot be updated safely."""


COMPILE_SDK = 36
PACKAGE_PATTERN = "file_picker-*/android/build.gradle*"
COMPILE_SDK_PATTERN = re.compile(
    r"(?m)^(?P<prefix>[ \t]*compileSdk(?:Version)?[ \t]*(?:=[ \t]*)?)"
    r"(?P<value>flutter\.compileSdkVersion|[0-9]+)"
    r"(?P<suffix>[ \t]*(?://.*)?$)"
)


def configure_file_picker_compile_sdk(project_root: Path) -> list[Path]:
    """Set every resolved file_picker Android Gradle declaration to API 36.

    Accepts numeric versions and Flutter's compileSdkVersion variable so a
    compatible package patch release cannot silently bypass the API setting.
    The function is idempotent and refuses unknown Gradle layouts.
    """
    pub_cache = Path.home() / ".pub-cache" / "hosted" / "pub.dev"
    packages = sorted(pub_cache.glob(PACKAGE_PATTERN))
    if not packages:
        raise AndroidCompileSdkError(
            "Could not locate the resolved file_picker Android Gradle file."
        )

    updated: list[Path] = []
    for gradle_path in packages:
        source = gradle_path.read_text(encoding="utf-8")
        matches = list(COMPILE_SDK_PATTERN.finditer(source))
        if len(matches) != 1:
            raise AndroidCompileSdkError(
                f"Expected exactly one compileSdk declaration in {gradle_path}; "
                f"found {len(matches)}."
            )

        match = matches[0]
        replacement = (
            match.group("prefix")
            + str(COMPILE_SDK)
            + match.group("suffix")
        )
        configured = (
            source[: match.start()]
            + replacement
            + source[match.end() :]
        )
        if configured != source:
            gradle_path.write_text(configured, encoding="utf-8")
        updated.append(gradle_path)

    return updated


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    files = configure_file_picker_compile_sdk(root)
    print(
        f"file_picker Android compile SDK verified at API {COMPILE_SDK}: "
        + ", ".join(str(path) for path in files)
    )
