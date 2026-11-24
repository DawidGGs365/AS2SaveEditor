"""Helpers shared by the build_<platform>.py scripts in the project root."""
import argparse, json, os, re, shutil, subprocess, sys, tarfile, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_t = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
name = re.search(r"^name:\s*(\S+)", _t, re.M).group(1)
file_prefix = json.loads((ROOT / "scripts" / "config.json").read_text(encoding="utf-8")).get("file_prefix") or name
_pub_version = re.search(r"^version:\s*([^\s+]+)", _t, re.M).group(1)


def run(cmd, cwd=ROOT):
    print("+", " ".join(map(str, cmd)), flush=True)
    subprocess.run(cmd, check=True, cwd=cwd)


def args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", help="e.g. 1.2.3 or 1.2.3-beta.1 (default: pubspec version)")
    ap.add_argument("--build-number", default=os.environ.get("GITHUB_RUN_NUMBER", "1"))
    ap.add_argument("--out", default="dist")
    a = ap.parse_args()
    a.version = (a.version or _pub_version).lstrip("v")
    a.build_name = a.version.split("-")[0]  # Windows/Apple need plain x.y.z
    a.out = ROOT / a.out
    a.out.mkdir(exist_ok=True)
    a.file = f"{file_prefix}-{a.version}"  # prefix of the packaged file name
    return a


def require_host(host):
    if not sys.platform.startswith(host):
        sys.exit(f"This platform can only be built on {host} (this is {sys.platform}).")


def ensure_platform(platform):
    """Generate + patch the platform folder if it doesn't exist yet."""
    if not (ROOT / platform).is_dir():
        run([sys.executable, "scripts/setup_platform.py", platform])


def flutter_build(a, *cmd):
    flutter = shutil.which("flutter") or sys.exit("flutter not found in PATH")
    run([flutter, *cmd, "--release", "--build-name", a.build_name, "--build-number", str(a.build_number)])


def one(pattern):
    hits = sorted(ROOT.glob(pattern))
    if not hits:
        sys.exit(f"build output not found: {pattern}")
    return hits[0]


def zip_dir(src, dst):
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(Path(src).rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(src))
    done(dst)


def tar_gz(src, dst, arcname):
    with tarfile.open(dst, "w:gz") as t:
        t.add(src, arcname=arcname)
    done(dst)


def done(dst):
    print("\nBuilt:", dst)
