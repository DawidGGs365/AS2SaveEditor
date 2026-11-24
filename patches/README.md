# Platform patches

`scripts/setup_platform.py <platform>` runs `flutter create` for one platform and then applies, in order:

1. `patches/<platform>/*.patch` - unified diffs (`git apply -p1`) against the freshly generated template, sorted by name.
2. `patches/<platform>/overlay/**` - files copied over the project root (new or replaced files, e.g. extra Kotlin/C++/Swift sources).
3. `patches/<platform>/*.py` - optional hook scripts (env: `PROJECT_ROOT`, `PLATFORM`, `ORG`, `PROJECT_NAME`, `DISPLAY_NAME`, `DESCRIPTION`).

Placeholders `@ORG@ @NAME@ @DISPLAY_NAME@ @DESCRIPTION@` (from `scripts/config.json` and `pubspec.yaml`) are expanded in patches and overlay files.
Patches are written for the Flutter version in `.flutter-version`; if a Flutter upgrade breaks one, CI's "platform setup" job fails and you regenerate it.

## Writing / regenerating a patch
    python scripts/setup_platform.py linux --clean --no-patches --no-icons    # pristine template
    # edit files under linux/
    python scripts/save_patch.py linux 20-my-change linux/runner/my_application.cc
The helper diffs against `.platform-base/linux/` (a pristine copy kept by the setup script) and writes
`patches/linux/20-my-change.patch`. Keep hunks small (the helper uses 1 line of context) and avoid touching lines that
contain the year or other values `flutter create` generates.

## Current patches
- android: app label, release signing read directly from env vars `KEYSTORE_FILE`/`KEYSTORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD` (debug-signed fallback).
- linux: window title, window icon (`icon.png` installed into `data/`).
- windows: window title, version-info strings.
- macos: product name; App Sandbox **off** (the editor writes `<save>.bak` next to the chosen file and accepts typed paths, which the sandbox blocks).
- web: title / manifest branding (hook, regex based).
- ios: home-screen display name (hook, regex based). Icons are generated from the template's `Contents.json`, flattened (no alpha).
