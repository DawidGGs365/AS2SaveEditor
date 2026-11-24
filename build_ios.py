#!/usr/bin/env python3
"""Build an unsigned iOS .ipa (macOS only) -> dist/<file_prefix>-<version>-ios-unsigned.ipa
    python build_ios.py [--version 1.2.3] [--build-number N]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "scripts"))
import build_common as b

b.require_host("darwin")
a = b.args()
b.ensure_platform("ios")
b.flutter_build(a, "build", "ios", "--no-codesign")

payload = b.ROOT / "build/ios/Payload"
b.shutil.rmtree(payload, ignore_errors=True)
payload.mkdir(parents=True)
b.shutil.copytree(b.one("build/ios/iphoneos/Runner.app"), payload / "Runner.app", symlinks=True)
dst = a.out / f"{a.file}-ios-unsigned.ipa"
dst.unlink(missing_ok=True)
b.run(["zip", "-qry", str(dst.resolve()), "Payload"], cwd=payload.parent)  # keeps file permissions
b.done(dst)
