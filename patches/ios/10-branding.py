"""iOS branding hook: home-screen display name (regex based, the Info.plist layout varies by Flutter version)."""
import os, re
from pathlib import Path

p = Path(os.environ["PROJECT_ROOT"]) / "ios/Runner/Info.plist"
t = p.read_text(encoding="utf-8")
t, n = re.subn(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)",
               lambda m: m.group(1) + os.environ["DISPLAY_NAME"] + m.group(2), t)
if n != 1:
    raise SystemExit("CFBundleDisplayName not found in ios/Runner/Info.plist")
p.write_text(t, encoding="utf-8")
