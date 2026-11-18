#!/usr/bin/env python3
"""Configure a private, persistent JKS signing key for the Android release build."""

from __future__ import annotations

import base64
import os
import shutil
import subprocess
from collections.abc import Mapping
from pathlib import Path


class AndroidSigningError(RuntimeError):
    """Raised when release signing cannot be configured safely."""


REQUIRED_SECRETS = (
    "ANDROID_KEYSTORE_BASE64",
    "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_ALIAS",
    "ANDROID_KEY_PASSWORD",
)


def _escape_property(value: str) -> str:
    """Escape values for java.util.Properties without printing secret contents."""
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r")


def _find_debug_signing_assignment(source: str, is_kotlin: bool) -> tuple[int, int, str]:
    import re

    if is_kotlin:
        pattern = re.compile(
            r'(?m)^(?P<indent>[ \\t]*)signingConfig[ \\t]*=[ \\t]*'
            r'signingConfigs\\.getByName\\("debug"\\)[ \\t]*$'
        )
        replacement = 'signingConfig = signingConfigs.getByName("release")'
    else:
        pattern = re.compile(
            r"(?m)^(?P<indent>[ \\t]*)signingConfig[ \\t]*=?[ \\t]*"
            r"signingConfigs\\.debug[ \\t]*$"
        )
        replacement = "signingConfig = signingConfigs.release"

    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise AndroidSigningError(
            "Expected exactly one generated debug signing assignment; "
            f"found {len(matches)}."
        )
    match = matches[0]
    return match.start(), match.end(), match.group("indent") + replacement


def configure_release_signing(
    project_root: Path,
    environment: Mapping[str, str] | None = None,
    keytool_path: str | None = None,
) -> Path:
    """Validate the supplied JKS, write local secrets, and switch release signing."""
    env = os.environ if environment is None else environment
    missing = [name for name in REQUIRED_SECRETS if not env.get(name)]
    if missing:
        raise AndroidSigningError(
            "Release signing is not configured. Missing GitHub Actions secrets: "
            + ", ".join(missing)
        )

    store_password = env["ANDROID_KEYSTORE_PASSWORD"]
    key_password = env["ANDROID_KEY_PASSWORD"]
    key_alias = env["ANDROID_KEY_ALIAS"]
    if any("\n" in value or "\r" in value for value in (store_password, key_password, key_alias)):
        raise AndroidSigningError("Signing secrets must not contain line breaks.")

    try:
        keystore_bytes = base64.b64decode(
            env["ANDROID_KEYSTORE_BASE64"],
            validate=True,
        )
    except (ValueError, TypeError) as error:
        raise AndroidSigningError("ANDROID_KEYSTORE_BASE64 is not valid base64.") from error
    if len(keystore_bytes) < 256:
        raise AndroidSigningError("The decoded keystore file is unexpectedly small.")

    android_dir = project_root / "android"
    app_dir = android_dir / "app"
    if not app_dir.is_dir():
        raise AndroidSigningError("The generated android/app directory is missing.")

    gradle_path = app_dir / "build.gradle"
    is_kotlin = False
    if not gradle_path.is_file():
        gradle_path = app_dir / "build.gradle.kts"
        is_kotlin = True
    if not gradle_path.is_file():
        raise AndroidSigningError("The Android app Gradle file is missing.")

    source = gradle_path.read_text(encoding="utf-8")
    if "signingConfigs {" in source:
        raise AndroidSigningError(
            "An existing signingConfigs block needs explicit reconciliation."
        )
    build_types_position = source.find("buildTypes {")
    if build_types_position < 0:
        raise AndroidSigningError("Could not locate the Android buildTypes block.")
    line_start = source.rfind("\n", 0, build_types_position) + 1
    indent = source[line_start:build_types_position]
    assignment_start, assignment_end, release_assignment = (
        _find_debug_signing_assignment(source, is_kotlin)
    )

    if is_kotlin:
        signing_config = (
            indent + "signingConfigs {\n"
            + indent + '    create("release") {\n'
            + indent + '        keyAlias = keystoreProperties.getProperty("keyAlias")\n'
            + indent + '        keyPassword = keystoreProperties.getProperty("keyPassword")\n'
            + indent + '        storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }\n'
            + indent + '        storePassword = keystoreProperties.getProperty("storePassword")\n'
            + indent + '        storeType = keystoreProperties.getProperty("storeType")\n'
            + indent + "    }\n"
            + indent + "}\n\n"
        )
        properties_loader = (
            'val keystoreProperties = java.util.Properties()\n'
            'val keystorePropertiesFile = rootProject.file("key.properties")\n'
            'if (!keystorePropertiesFile.exists()) throw GradleException("Release key.properties is missing")\n'
            'keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))\n\n'
        )
    else:
        signing_config = (
            indent + "signingConfigs {\n"
            + indent + "    release {\n"
            + indent + "        keyAlias = keystoreProperties['keyAlias']\n"
            + indent + "        keyPassword = keystoreProperties['keyPassword']\n"
            + indent + "        storeFile = file(keystoreProperties['storeFile'])\n"
            + indent + "        storePassword = keystoreProperties['storePassword']\n"
            + indent + "        storeType = keystoreProperties['storeType']\n"
            + indent + "    }\n"
            + indent + "}\n\n"
        )
        properties_loader = (
            "def keystoreProperties = new java.util.Properties()\n"
            "def keystorePropertiesFile = rootProject.file('key.properties')\n"
            'if (!keystorePropertiesFile.exists()) throw new GradleException("Release key.properties is missing")\n'
            "keystoreProperties.load(new java.io.FileInputStream(keystorePropertiesFile))\n\n"
        )

    keytool = keytool_path or shutil.which("keytool")
    if not keytool:
        raise AndroidSigningError("keytool was not found; Java is required for release signing.")

    keystore_path = android_dir / "upload-keystore.jks"
    keystore_path.write_bytes(keystore_bytes)
    try:
        keystore_path.chmod(0o600)
    except OSError:
        pass

    try:
        subprocess.run(
            [
                keytool,
                "-list",
                "-keystore",
                str(keystore_path),
                "-storetype",
                "JKS",
                "-storepass",
                store_password,
                "-alias",
                key_alias,
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError as error:
        keystore_path.unlink(missing_ok=True)
        raise AndroidSigningError(
            "The JKS keystore, password, or alias is invalid."
        ) from error

    properties = (
        "storePassword=" + _escape_property(store_password) + "\n"
        + "keyPassword=" + _escape_property(key_password) + "\n"
        + "keyAlias=" + _escape_property(key_alias) + "\n"
        + "storeType=JKS\n"
        + "storeFile=../upload-keystore.jks\n"
    )
    properties_path = android_dir / "key.properties"
    properties_path.write_text(properties, encoding="utf-8")
    try:
        properties_path.chmod(0o600)
    except OSError:
        pass

    source = source[:assignment_start] + release_assignment + source[assignment_end:]
    source = source[:line_start] + properties_loader + source[line_start:]
    source = source[:line_start] + signing_config + source[line_start:]
    if "signingConfigs.release" not in source and 'getByName("release")' not in source:
        raise AndroidSigningError("Release signing assignment verification failed.")

    gradle_path.write_text(source, encoding="utf-8")
    return keystore_path


if __name__ == "__main__":
    configured = configure_release_signing(Path(__file__).resolve().parents[1])
    print(f"Android release signing configured and JKS validated: {configured.name}")
