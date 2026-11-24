"""Web branding hook (regex based, because the web template varies between Flutter versions)."""
import json, os, re
from pathlib import Path

root = Path(os.environ["PROJECT_ROOT"]) / "web"
name, display, desc = os.environ["PROJECT_NAME"], os.environ["DISPLAY_NAME"], os.environ["DESCRIPTION"]

idx = root / "index.html"
t = idx.read_text(encoding="utf-8")
t = re.sub(r"<title>.*?</title>", f"<title>{display}</title>", t, flags=re.S)
t = re.sub(r'(<meta name="description" content=")[^"]*(")', lambda m: m.group(1) + desc + m.group(2), t)
t = re.sub(r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(")', lambda m: m.group(1) + display + m.group(2), t)
idx.write_text(t, encoding="utf-8")

mf = root / "manifest.json"
m = json.loads(mf.read_text(encoding="utf-8"))
m.update({"name": display, "short_name": display, "description": desc})
mf.write_text(json.dumps(m, indent=2) + "\n", encoding="utf-8")
