#!/usr/bin/env python3
"""Turn your edits of generated platform files into a patch under patches/<platform>/.

    python scripts/setup_platform.py linux --clean --no-patches --no-icons   # fresh template
    (edit files in linux/)
    python scripts/save_patch.py linux 20-my-change linux/runner/my_application.cc [more files]

Compares each file with the pristine copy in .platform-base/<platform>/ and writes
patches/<platform>/20-my-change.patch with the org/name/display name turned back into placeholders.
"""
import argparse, difflib, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from setup_platform import ROOT, cfg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("platform")
    ap.add_argument("patch_name")
    ap.add_argument("files", nargs="+", help="paths relative to the project root, e.g. linux/CMakeLists.txt")
    ap.add_argument("--base", default=str(ROOT / ".platform-base"))
    ap.add_argument("--org")
    a = ap.parse_args()
    c = cfg()
    org = a.org or c["org"]

    def rev(t):
        t = t.replace(org, "@ORG@").replace(c["display_name"], "@DISPLAY_NAME@")
        return t.replace(c["name"], "@NAME@") if c["name"] not in ("", "app") else t

    out = []
    for f in a.files:
        old = rev((Path(a.base) / f).read_text(encoding="utf-8")).splitlines(True)
        new = rev((ROOT / f).read_text(encoding="utf-8")).splitlines(True)
        for line in difflib.unified_diff(old, new, f"a/{f}", f"b/{f}", n=1):
            out.append(line if line.endswith("\n") else line + "\n\\ No newline at end of file\n")
    if not out:
        sys.exit("no differences")
    dst = ROOT / "patches" / a.platform / f"{a.patch_name}.patch"
    dst.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote", dst.relative_to(ROOT))


if __name__ == "__main__":
    main()
