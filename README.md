# AS2 Save Editor (Animal Shelter 2)

Flutter editor for Animal Shelter 2 `.save` files (.NET BinaryFormatter).
Platforms: Windows, Linux, macOS, Android, iOS, web.

Everything the editor shows by name comes from the game's own data (`assets/gamedb.json`): every asset GUID that can
appear in a save (perks, skills, breeds, items, diseases, tricks, quests, needs, life stages, unlocks, ...) with its
I2 localization term, plus the game's full translation table in all 13 languages. Names follow the system language
(or the one picked in Settings) and fall back to English.

## Tabs
- **Shelter**: shelter name, money, reputation, day, time, tracked quest, custom difficulty settings.
- **Pets**: name, age stage, difficulty, perks (add / remove / hide), needs, tricks (add / remove / progress),
  disease (cure), behavioural problem (remove), vaccines, adopter wishes, coat (groom & clean).
- **Workers**: name, wage, volunteer, skill levels (0–100, the game's cap), missing skills.
- **Inventory**: each player's hotbar; put items into empty slots or remove them.
- **Progress**: unlocks (add / remove), quests.
- **Browse / Search** (Settings → Advanced mode): the raw save tree; any value can be edited and list entries
  duplicated or deleted. Not checked against the game's rules.

## File format
`[header: SaveFileHeaderData][zero padding to 1024][body: SaveData]`.
The header repeats day, time, shelter name/icon, tracked quest and reputation for the Load window; the editor keeps it
in sync. Value edits are written in place, so an untouched file re-serialises byte for byte (the app refuses files
that don't). Adding or removing anything re-writes the body from the root (`lib/graph.dart`), with the same object
graph, verified by `test/edit_test.dart`.

## Saving
- Windows / Linux / macOS: overwrites the opened file in place and keeps a one-time `<file>.bak`.
- Android / web: the system only hands the app a copy, so Save exports an edited copy.

Close the game before editing a save.

## Set up
The repo contains no platform folders (`android/ linux/ macos/ windows/ web/`). They are generated per platform:

    flutter pub get
    pip install pillow                          # only for icons
    python scripts/setup_platform.py linux      # or windows / macos / android / ios / web / all
    flutter run -d linux

`setup_platform.py` runs `flutter create` for that platform, applies `patches/<platform>/` (window title, signing,
macOS sandbox off, ...) and generates the icons from `icons/`. Re-run with `--clean` to regenerate a platform.
Flutter version: see `.flutter-version`. App id prefix / display name: `scripts/config.json`.
Details on how patches work: [`patches/README.md`](patches/README.md). Icons: [`icons/README.md`](icons/README.md).

Linux needs `clang cmake ninja-build pkg-config libgtk-3-dev`; the Browse button needs `zenity` or `kdialog`.

## Building
Each desktop build has to be made on its own OS (Flutter can't cross-compile desktop apps).
Run `python scripts/setup_platform.py <platform>` first, then:

| Platform | Command | Output |
|---|---|---|
| Linux | `flutter build linux --release` | `build/linux/x64/release/bundle/` (ship the whole folder) |
| Windows | `flutter build windows --release` | `build\windows\x64\runner\Release\` (ship the whole folder) |
| macOS | `flutter build macos --release` | `build/macos/Build/Products/Release/*.app` |
| Android | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| iOS | `flutter build ios --release --no-codesign` | `build/ios/iphoneos/Runner.app` (unsigned) |
| Web | `flutter build web --release --wasm` | `build/web/` (WebAssembly, JS fallback) |

Or use the per-platform build scripts in the project root, which do setup if needed, the build, and packaging
exactly like CI (output goes to `dist/`; each file shows its own `flutter build` command):

    python build_linux.py       # build_windows.py / build_macos.py / build_android.py / build_ios.py / build_web.py
    # options: --version 1.2.3 --build-number 7

Windows needs Visual Studio with the "Desktop development with C++" workload (users need the VC++ runtime);
macOS and iOS need Xcode (iOS can only be built on a Mac); Android needs the Android SDK (`flutter doctor --android-licenses` once).

## Releases
Every push to `main` builds all platforms and updates one **rolling release per platform**, each under its own tag:
`android-latest`, `ios-latest`, `linux-latest`, `macos-latest`, `web-latest`, `windows-latest`
(title `v<version from pubspec.yaml>`, description = `.github/SHRTCHNGLOG.md` plus a build footer; the tag always
points at the newest build, old files are replaced). Bump `version:` in `pubspec.yaml` and edit the changelog before pushing.
A failed platform doesn't stop the others. Runs started manually on other branches only keep workflow artifacts.

Workflows: `.github/workflows/ci.yml` (analyze, tests, translation check, patch check on every push/PR) and
`release.yml` (build + rolling releases; each runner calls `build_<platform>.py`).
Optional Android signing secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`
(the workflow decodes the keystore to a temp file and Gradle reads the values from env vars; otherwise the APK is debug-signed). The macOS build is unsigned: on first start use right-click -> Open
(or `xattr -cr <app>`). The iOS release is an **unsigned** `.ipa`: it can't be installed directly, sideload it with
SideStore / AltStore / Sideloadly (re-signed with your Apple ID) or TrollStore. App Store / TestFlight needs a paid Apple
Developer account and signing set up in CI. Like Android, iOS saves an edited copy (Files / share sheet) instead of
overwriting the original.

## Translations
The UI uses the same language as the game names (Settings → Language, 13 languages). UI texts are wrapped in `t('...')`
(`lib/l10n.dart`); their translations live in `l10n/ui_*.txt`, one line per text:
`English|Polish|Simplified Chinese|Traditional Chinese|French|Italian|German|Spanish|Korean|Russian|Turkish|Japanese|Portuguese (Brazil)`.
After adding or changing a `t('...')` text, run `python3 l10n/build_l10n.py`: it lists missing translations and
placeholder mismatches and writes `assets/l10n.json`.

## Tests
    SAVE_FILE=/path/to/AutoSave.save flutter test

## Regenerating the game data
`assets/gamedb.json` is built by `tools/save_re/build_db.py` (in the BepinPlugins repo) from static scans of the game
files (UnityPy + Odin decoding) and an I2 dump made in game by the DataMiner dev plugin.
