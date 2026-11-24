#!/usr/bin/env python3
"""Generate platform icons from icons/icon.png (needs `pip install pillow`).

    python scripts/make_icons.py <android|ios|linux|macos|windows|web|all>

icons/icon.png                 required, square PNG, 1024x1024 (or larger)
icons/icon_foreground.png      optional, Android adaptive icon foreground (1024x1024, transparent,
                               keep the artwork inside the centre 66%); also used for web maskable icons
icons/icon_monochrome.png      optional, Android 13 themed icon (same layout as foreground)
icons/adaptive_background.txt  optional, background colour for adaptive/maskable icons, e.g. #1E88E5 (default #FFFFFF)
"""
import json, sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / "icons"


def load(name):
    p = ICONS / name
    return Image.open(p).convert("RGBA") if p.exists() else None


def sized(img, n):
    return img.resize((n, n), Image.LANCZOS)


def save(img, path, n):
    path.parent.mkdir(parents=True, exist_ok=True)
    sized(img, n).save(path)


def bg_color():
    f = ICONS / "adaptive_background.txt"
    return f.read_text().strip() if f.exists() else "#FFFFFF"


def android(icon, fg, mono):
    res = ROOT / "android/app/src/main/res"
    for d, n in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        save(icon, res / f"mipmap-{d}/ic_launcher.png", n)
    if fg:
        for d, n in (("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)):
            save(fg, res / f"mipmap-{d}/ic_launcher_foreground.png", n)
            if mono:
                save(mono, res / f"mipmap-{d}/ic_launcher_monochrome.png", n)
        (res / "values").mkdir(parents=True, exist_ok=True)
        (res / "values/ic_launcher_background.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            f'    <color name="ic_launcher_background">{bg_color()}</color>\n</resources>\n')
        (res / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
        (res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            + ('    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n' if mono else "")
            + '</adaptive-icon>\n')


def windows(icon, *_):
    out = ROOT / "windows/runner/resources/app_icon.ico"
    out.parent.mkdir(parents=True, exist_ok=True)
    sized(icon, 256).save(out, sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])


def macos(icon, *_):
    d = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for n in (16, 32, 64, 128, 256, 512, 1024):
        save(icon, d / f"app_icon_{n}.png", n)


def ios(icon, *_):
    """Sizes come from the template's Contents.json; iOS icons must not have an alpha channel."""
    d = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    cj = d / "Contents.json"
    if not cj.exists():
        return
    flat = Image.new("RGBA", icon.size, bg_color())
    flat.alpha_composite(icon)
    flat = flat.convert("RGB")
    for e in json.loads(cj.read_text())["images"]:
        if "filename" in e:
            px = round(float(e["size"].split("x")[0]) * int(e["scale"].rstrip("x")))
            flat.resize((px, px), Image.LANCZOS).save(d / e["filename"])


def linux(icon, *_):
    save(icon, ROOT / "linux/icon.png", 512)


def web(icon, fg, _m):
    w = ROOT / "web"
    save(icon, w / "favicon.png", 32)
    for n in (192, 512):
        save(icon, w / f"icons/Icon-{n}.png", n)
        base = Image.new("RGBA", (n, n), bg_color())
        art = sized(fg, n) if fg else sized(icon, int(n * 0.8))
        base.alpha_composite(art, ((n - art.width) // 2, (n - art.height) // 2))
        base.save(w / f"icons/Icon-maskable-{n}.png")


FUNCS = {"android": android, "ios": ios, "windows": windows, "macos": macos, "linux": linux, "web": web}


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "all"
    icon = load("icon.png")
    if icon is None:
        print("icons/icon.png not found - keeping the default Flutter icons.")
        return
    if icon.width != icon.height:
        sys.exit("icons/icon.png must be square")
    fg, mono = load("icon_foreground.png"), load("icon_monochrome.png")
    for p in (FUNCS if arg == "all" else [arg]):
        if (ROOT / p).is_dir():
            FUNCS[p](icon, fg, mono)
            print(f"icons written for {p}")


if __name__ == "__main__":
    main()
