#!/usr/bin/env python3
"""Build the Linux bundle (Linux only) -> dist/<file_prefix>-<version>-linux-<arch>.tar.gz
    python build_linux.py [--version 1.2.3] [--build-number N]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "scripts"))
import build_common as b

b.require_host("linux")
a = b.args()
b.ensure_platform("linux")
b.flutter_build(a, "build", "linux")

bundle = b.one("build/linux/*/release/bundle")
arch = bundle.parent.parent.name
b.tar_gz(bundle, a.out / f"{a.file}-linux-{arch}.tar.gz", arcname=b.name)
