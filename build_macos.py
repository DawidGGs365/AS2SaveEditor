#!/usr/bin/env python3
"""Build the macOS app (macOS only) -> dist/<file_prefix>-<version>-macos.zip
    python build_macos.py [--version 1.2.3] [--build-number N]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "scripts"))
import build_common as b

b.require_host("darwin")
a = b.args()
b.ensure_platform("macos")
b.flutter_build(a, "build", "macos")

app = b.one("build/macos/Build/Products/Release/*.app")
dst = a.out / f"{a.file}-macos.zip"
b.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(dst)])
b.done(dst)
