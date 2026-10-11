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
