@AGENTS.md

# TBG Remote Support (fork notes)

Branch `tbg-<version>` = upstream tag + a few small branding commits. Everything
TBG-specific lives in `tbg/`; upstream files are touched only where listed below.

## Branding changes to upstream files (redo after a rebase)

* `flutter/windows/runner/Runner.rc`: `CompanyName`, `FileDescription`,
  `LegalCopyright`, `OriginalFilename`, `ProductName` (exe file properties).
* `flutter/windows/runner/resources/app_icon.ico` = `tbg/icons/icon.ico`
  (exe, window, taskbar, shortcuts).
* `res/icon.ico` = `tbg/icons/icon.ico` (librustdesk.dll resource; the MSI copies
  it for the Add/Remove Programs and shortcut icon).
* `res/tray-icon.ico` = `tbg/icons/tray-icon.ico` (system tray, `include_bytes!`).
* `flutter/assets/icon.svg`: in-app icon (connection manager 30px, tab bar 16px,
  via `loadIcon()` in `flutter/lib/common.dart`). It is an SVG wrapping
  `tbg/icons/tbg-icon-rounded.png` downscaled to 256x256 as a base64 PNG
  (flutter_svg / vector_graphics_compiler render `<image href="data:image/png;base64,...">`).
  Regenerate:

  ```
  magick tbg/icons/tbg-icon-rounded.png -filter Lanczos -resize 256x256 -strip icon-256.png
  python -c "import base64;d=base64.b64encode(open('icon-256.png','rb').read()).decode();open('flutter/assets/icon.svg','w',newline='\n').write(f'<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"256\" height=\"256\" viewBox=\"0 0 256 256\"><image width=\"256\" height=\"256\" href=\"data:image/png;base64,{d}\"/></svg>\n')"
  ```

  Do not add `flutter/assets/icon.png`: `src/tray.rs` prefers it over
  `res/tray-icon.ico`, which would replace the tray icon.

App name, server and key are NOT committed: `tbg/hbb_common-tbg.patch` is applied
to the `libs/hbb_common` submodule at build time (never commit in the submodule).
Runtime strings pick up `APP_NAME`; "Powered by RustDesk" is deliberately excluded
by `src/lang.rs` (`powered_by_me`) and must stay.

## Build

```
pwsh -File tbg\build.ps1          # incremental
pwsh -File tbg\build.ps1 -Clean   # wipe target/, flutter/build/, tbg/out/, MSI outputs first
```

Output: `tbg\out\TBG-Remote-Support-<version>-x64.msi` (`tbg/out/` is gitignored).
The script mirrors the Windows x64 job in `.github/workflows/flutter-build.yml`:
checks the toolchain below, enters a VS dev shell pinned to MSVC 14.44, runs the
vcpkg manifest install, applies `tbg/hbb_common-tbg.patch`, generates the Rust
bridge, runs `build.py --portable --flutter --skip-portable-pack --hwcodec --vram`,
assembles the dist folder (exe renamed to `TBG Remote Support.exe`, which the MSI
requires; usbmmidd_v2 and the checksum-verified printer driver, as CI does), and
builds `res/msi` with `preprocess.py --app-name "TBG Remote Support" -m "The Bozeman Group"`.
On exit it reverts the hbb_common patch, `res/msi` and `flutter/pubspec.lock`.

Build-time fixes applied and reverted by the script (never committed):

* `tbg/hbb_common-tbg.patch`: APP_NAME, RENDEZVOUS_SERVERS, RS_PUB_KEY.
* `tbg/msi-preprocess-quote-exe.patch`: `preprocess.py` runs `<app>.exe --version`
  through cmd unquoted, which fails for names with spaces.
* `res/msi/Package/License.rtf` is restored after `preprocess.py`, which would
  otherwise rewrite the license to name "TBG Remote Support" as licensor.
* `flutter pub get` rewrites `flutter/pubspec.lock` (the committed lock does not
  satisfy Flutter 3.24.5's SDK pins); CI does the same.

MSI version is `<version>.<minutes since epoch>` (upstream default), so every build
upgrades the previous one. Component GUIDs are regenerated per build by
`preprocess.py` for non-RustDesk names; compare MSIs by payload, not bytes.

## Toolchain (one-time; checked by build.ps1)

Pinned by the 1.5.0 workflow, installed here:

| Item | Version / location |
|---|---|
| Visual Studio | 2026 (18.x) Enterprise with the MSVC v143 14.44 component; generator `Visual Studio 18 2026` + toolset v143 (set in-process only) |
| Rust | 1.75 via `RUSTUP_TOOLCHAIN` (default toolchain stays stable) |
| flutter_rust_bridge_codegen / cargo-expand | 1.80.1 / 1.0.95 |
| LLVM | 15.0.6 at `C:\Development\LLVM-15` (`LIBCLANG_PATH`) |
| vcpkg | `C:\Development\vcpkg` at the `vcpkg.json` baseline; `tbg/vcpkg-triplets` pins v143 |
| Flutter | 3.24.5 at `C:\Development\flutter`, patched as below |

MSI: WiX SDK 4.0.5 comes from NuGet via `msbuild -restore -p:RestorePackagesConfig=true`;
no `nuget.exe` needed. `CMAKE_GENERATOR="Visual Studio 17 2022"` in the user
environment is stale (no VS 2022 instance); the script overrides it in-process.

## Upgrading to a new upstream release

1. `git fetch upstream --tags; git checkout -b tbg-<new> <new-tag>;
   git submodule update --init --recursive`
2. `git cherry-pick` the commits `<old-tag>..tbg-<old>` (all small; the branding
   ones touch only the files listed above). Conflicts are most likely in
   `Runner.rc` if upstream changed its copyright year.
3. `git -C libs/hbb_common apply --check ../../tbg/hbb_common-tbg.patch`. If it
   fails, edit the three lines by hand, then regenerate:
   `git -C libs/hbb_common diff > tbg/hbb_common-tbg.patch` and revert the submodule.
   Same for `tbg/msi-preprocess-quote-exe.patch` against `res/msi/preprocess.py`
   (drop it if upstream quotes the path).
4. Compare `.github/workflows/flutter-build.yml` pins with the toolchain table:
   `FLUTTER_VERSION`, `SCITER_RUST_VERSION`, `LLVM_VERSION`, `VCPKG_COMMIT_ID`
   (and `vcpkg.json` baseline), bridge.yml `FLUTTER_RUST_BRIDGE_VERSION` /
   `CARGO_EXPAND_VERSION`, the Windows x64 dist steps (drivers, extra files) and
   the MSI step. Update `build.ps1` constants and this file to match.
5. If the Flutter version changes, re-check the RustDesk engine zip and the
   dropdown patch, and re-derive `tbg/flutter-patches` for the new Flutter tool.
6. `pwsh -File tbg\build.ps1 -Clean`, then run the manual checklist.

## Local Flutter checkout (C:\Development\flutter, 3.24.5)

Not in the repo; the build checks each item and fails if one is missing.

1. `tbg/flutter-patches/flutter-tools-vs18-generator.patch`: maps VS 2026 (major 18)
   to the `Visual Studio 18 2026` CMake generator.
2. `tbg/flutter-patches/flutter-tools-cmake-toolset-env.patch`: passes
   `-T $CMAKE_GENERATOR_TOOLSET` to CMake when that env var is set (CMake ignores
   the env var when `-G` is given, which Flutter always does). Used to force v143.
3. `.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff` (from CI).
4. RustDesk engine: `windows-x64-release.zip` from the rustdesk/engine release
   `main` extracted over `bin\cache\artifacts\engine\windows-x64-release\`
   (`flutter_windows.dll` sha256 `295d3767a5e5c4017f4877e67a4a8926178ecdfbb1196c3bd21ec5f5097f5ed3`).

Re-applying to a fresh 3.24.5 checkout:

```
git clone -b 3.24.5 https://github.com/flutter/flutter C:\Development\flutter
cd C:\Development\flutter
git apply <repo>\tbg\flutter-patches\flutter-tools-vs18-generator.patch
git apply <repo>\tbg\flutter-patches\flutter-tools-cmake-toolset-env.patch
git apply <repo>\.github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff
del bin\cache\flutter_tools.snapshot bin\cache\flutter_tools.stamp
flutter precache --windows
# then download and extract the engine zip over bin\cache\artifacts\engine\windows-x64-release\
```

`flutter precache --force` or a Flutter upgrade restores the stock engine; re-extract it.

## Known items (not fixed)

* URI scheme becomes `tbg remote support://` (lowercased app name with spaces,
  not a valid scheme). Only affects clickable connection links.
* CI also drops `RustDeskTempTopMostWindow` artifacts (built by a separate job)
  into the dist folder; this build does not include them. They back the
  "topmost window" privacy-mode implementation (`privacy_mode::win_topmost_window`),
  so that privacy-mode option is unavailable; other privacy modes are unaffected.
* Not code-signed; SmartScreen will warn on first run of the MSI.
