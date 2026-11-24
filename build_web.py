#!/usr/bin/env python3
"""Build the web app (WebAssembly with JS fallback) -> dist/<file_prefix>-<version>-web.zip
    python build_web.py [--version 1.2.3] [--build-number N]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "scripts"))
import build_common as b

a = b.args()
b.ensure_platform("web")
b.flutter_build(a, "build", "web", "--wasm")
b.zip_dir(b.ROOT / "build/web", a.out / f"{a.file}-web.zip")
