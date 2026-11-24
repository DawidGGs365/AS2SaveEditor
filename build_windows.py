#!/usr/bin/env python3
"""Build the Windows app (Windows only) -> dist/<file_prefix>-<version>-windows-<arch>.zip
    python build_windows.py [--version 1.2.3] [--build-number N]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "scripts"))
import build_common as b

b.require_host("win32")
a = b.args()
b.ensure_platform("windows")
b.flutter_build(a, "build", "windows")

release = b.one("build/windows/*/runner/Release")
b.zip_dir(release, a.out / f"{a.file}-windows-{release.parent.parent.name}.zip")
