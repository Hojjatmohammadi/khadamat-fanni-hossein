#!/usr/bin/env python3
"""Enforce the stable Android package identity for generated Flutter projects."""

from __future__ import annotations

import re
from pathlib import Path

APPLICATION_ID = "com.khadamatfanni.khadamat_fanni_hossein"


class AndroidProjectError(RuntimeError):
    """Raised when a generated Android project does not match the app identity."""


def _replace_gradle_property(source: str, property_name: str) -> str:
    pattern = re.compile(
        rf"""(?m)^(?P<prefix>[ \t]*{re.escape(property_name)}[ \t]*(?:=[ \t]*)?)"""
        rf"""(?P<quote>["'])(?P<value>[^"']+)(?P=quote)(?P<tail>[ \t]*(?://.*)?$)"""
    )
    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise AndroidProjectError(
            f"Expected exactly one Gradle {property_name} declaration; found {len(matches)}."
        )

    match = matches[0]
    replacement = (
        match.group("prefix")
        + match.group("quote")
        + APPLICATION_ID
        + match.group("quote")
        + match.group("tail")
    )
    return source[: match.start()] + replacement + source[match.end() :]


def configure_android_project(project_root: Path) -> Path:
    """Set namespace/applicationId and verify the generated MainActivity package."""
    app_dir = project_root / "android" / "app"
    gradle_candidates = (app_dir / "build.gradle.kts", app_dir / "build.gradle")
    gradle_path = next((path for path in gradle_candidates if path.is_file()), None)
    if gradle_path is None:
        raise AndroidProjectError("Android app Gradle file was not generated.")

    source = gradle_path.read_text(encoding="utf-8")
    source = _replace_gradle_property(source, "namespace")
    source = _replace_gradle_property(source, "applicationId")
    gradle_path.write_text(source, encoding="utf-8")

    main_activities = list((app_dir / "src" / "main").rglob("MainActivity.*"))
    main_activities = [
        path for path in main_activities if path.suffix in {".kt", ".java"}
    ]
    if len(main_activities) != 1:
        raise AndroidProjectError(
            f"Expected exactly one MainActivity source file; found {len(main_activities)}."
        )

    activity_source = main_activities[0].read_text(encoding="utf-8")
    package_match = re.search(
        r"(?m)^package[ \t]+([A-Za-z0-9_.]+)[ \t]*;?[ \t]*$",
        activity_source,
    )
    if package_match is None:
        raise AndroidProjectError("MainActivity has no readable package declaration.")
    if package_match.group(1) != APPLICATION_ID:
        raise AndroidProjectError(
            "MainActivity package does not match the fixed application ID: "
            + package_match.group(1)
        )

    return gradle_path


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    configured = configure_android_project(root)
    print(f"Android identity verified: {APPLICATION_ID} ({configured})")
