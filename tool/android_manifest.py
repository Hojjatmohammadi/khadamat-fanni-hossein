#!/usr/bin/env python3
"""Configure and validate the generated Android app label and runtime permissions."""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
ANDROID_URI = "http://schemas.android.com/apk/res/android"
APP_LABEL = "خدمات فنی حسین"

PERMISSIONS = (
    "android.permission.READ_CONTACTS",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
)

RECEIVER_NAMES = (
    "com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver",
    "com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver",
)

BOOT_ACTIONS = (
    "android.intent.action.BOOT_COMPLETED",
    "android.intent.action.MY_PACKAGE_REPLACED",
    "android.intent.action.QUICKBOOT_POWERON",
    "com.htc.intent.action.QUICKBOOT_POWERON",
)


class AndroidManifestError(RuntimeError):
    """Raised when Android manifest setup or validation fails."""


def _parse_manifest(content: str, manifest_path: Path) -> ET.Element:
    try:
        root = ET.fromstring(content)
    except ET.ParseError as exc:
        raise AndroidManifestError(f"Invalid Android manifest XML at {manifest_path}: {exc}") from exc
    if root.tag != "manifest":
        raise AndroidManifestError("Android manifest root element must be <manifest>.")
    if root.find("application") is None:
        raise AndroidManifestError("Android manifest has no <application> element.")
    return root


def configure_android_manifest(project_root: Path) -> Path:
    """Apply required app label, permissions, and notification receivers idempotently."""
    manifest = (
        project_root
        / "android"
        / "app"
        / "src"
        / "main"
        / "AndroidManifest.xml"
    )
    if not manifest.is_file():
        raise AndroidManifestError(f"Android manifest was not generated: {manifest}")

    content = manifest.read_text(encoding="utf-8")
    root = _parse_manifest(content, manifest)

    existing_permissions = {
        node.get(ANDROID_NS + "name")
        for node in root.findall("uses-permission")
    }
    missing_permissions = [
        name for name in PERMISSIONS if name not in existing_permissions
    ]
    if missing_permissions:
        application_match = re.search(r"<application\\b", content)
        if application_match is None:
            raise AndroidManifestError("Could not locate the <application> opening tag.")
        permission_xml = "".join(
            f'    <uses-permission android:name="{name}" />\\n'
            for name in missing_permissions
        )
        content = (
            content[:application_match.start()]
            + permission_xml
            + "\\n"
            + content[application_match.start():]
        )

    application_match = re.search(r"<application\\b[^>]*>", content)
    if application_match is None:
        raise AndroidManifestError("Could not locate the <application> opening tag.")

    opening_tag = application_match.group(0)
    label_pattern = re.compile(
        r"""android:label\\s*=\\s*(?P<quote>["'])[^"']*(?P=quote)"""
    )
    if label_pattern.search(opening_tag):
        updated_tag = label_pattern.sub(
            f'android:label="{APP_LABEL}"',
            opening_tag,
            count=1,
        )
    else:
        updated_tag = opening_tag[:-1] + f' android:label="{APP_LABEL}">'
    content = (
        content[:application_match.start()]
        + updated_tag
        + content[application_match.end():]
    )

    root = _parse_manifest(content, manifest)
    application = root.find("application")
    assert application is not None
    existing_receivers = {
        node.get(ANDROID_NS + "name")
        for node in application.findall("receiver")
    }

    receiver_xml = []
    if RECEIVER_NAMES[0] not in existing_receivers:
        receiver_xml.append(
            '    <receiver android:exported="false" '
            f'android:name="{RECEIVER_NAMES[0]}" />'
        )
    if RECEIVER_NAMES[1] not in existing_receivers:
        receiver_xml.extend(
            [
                '    <receiver android:exported="false" '
                f'android:name="{RECEIVER_NAMES[1]}">',
                "        <intent-filter>",
                *[
                    f'            <action android:name="{action}" />'
                    for action in BOOT_ACTIONS
                ],
                "        </intent-filter>",
                "    </receiver>",
            ]
        )
    if receiver_xml:
        closing_tag = content.rfind("</application>")
        if closing_tag < 0:
            raise AndroidManifestError("Could not locate </application> in Android manifest.")
        content = (
            content[:closing_tag]
            + "\\n".join(receiver_xml)
            + "\\n"
            + content[closing_tag:]
        )

    _parse_manifest(content, manifest)
    manifest.write_text(content, encoding="utf-8")

    # Re-read the saved file so validation covers the exact bytes written.
    saved_root = _parse_manifest(manifest.read_text(encoding="utf-8"), manifest)
    app = saved_root.find("application")
    assert app is not None
    saved_permissions = {
        node.get(ANDROID_NS + "name")
        for node in saved_root.findall("uses-permission")
    }
    saved_receivers = {
        node.get(ANDROID_NS + "name")
        for node in app.findall("receiver")
    }
    if not set(PERMISSIONS).issubset(saved_permissions):
        raise AndroidManifestError("Android manifest is missing required permissions.")
    if not set(RECEIVER_NAMES).issubset(saved_receivers):
        raise AndroidManifestError("Android manifest is missing required notification receivers.")
    if app.get(ANDROID_NS + "label") != APP_LABEL:
        raise AndroidManifestError("Android application label was not configured.")

    boot_receiver = next(
        node for node in app.findall("receiver")
        if node.get(ANDROID_NS + "name") == RECEIVER_NAMES[1]
    )
    actions = {
        action.get(ANDROID_NS + "name")
        for action in boot_receiver.findall("./intent-filter/action")
    }
    if not set(BOOT_ACTIONS).issubset(actions):
        raise AndroidManifestError("Notification boot receiver is missing required actions.")

    return manifest


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    configured = configure_android_manifest(root)
    print(
        "Android manifest verified: Persian app label, contacts/notification permissions, "
        f"and boot receivers ({configured})."
    )
