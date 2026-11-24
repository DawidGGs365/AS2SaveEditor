#!/usr/bin/env python3
"""Build the Android APK -> dist/<file_prefix>-<version>-android.apk
    python build_android.py [--version 1.2.3] [--build-number N]
Signing: android/app/build.gradle.kts reads KEYSTORE_FILE (path), KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD
from the environment (set by CI); if any is missing the APK is debug-signed.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "scripts"))
import build_common as b

a = b.args()
b.ensure_platform("android")
b.flutter_build(a, "build", "apk")
dst = a.out / f"{a.file}-android.apk"
b.shutil.copyfile(b.one("build/app/outputs/flutter-apk/app-release.apk"), dst)
b.done(dst)
