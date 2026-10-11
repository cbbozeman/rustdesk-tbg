<#
.SYNOPSIS
    Builds the TBG Remote Support MSI (Windows x64) from a checkout of this branch.

.DESCRIPTION
    Mirrors the Windows x64 job of .github/workflows/flutter-build.yml, plus TBG
    branding applied at build time:
      * tbg/hbb_common-tbg.patch          -> libs/hbb_common (app name, server, key)
      * tbg/msi-preprocess-quote-exe.patch -> res/msi/preprocess.py
    Both are reverted when the script exits, as are the in-place res/msi rewrite
    and the pubspec.lock rewrite done by `flutter pub get`.

    Every compiled binary uses MSVC 14.44 (v143) from VS 2026; see CLAUDE.md for the
    one-time toolchain setup this script checks for.

    Output: tbg/out/TBG-Remote-Support-<version>-x64.msi

.PARAMETER Clean
    Delete previous Rust, Flutter, MSI and tbg/out build output first.
#>
param(
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

$AppName      = 'TBG Remote Support'
$Manufacturer = 'The Bozeman Group'
$FileStem     = 'TBG-Remote-Support'

$Repo        = (Resolve-Path "$PSScriptRoot\..").Path
$FlutterRoot = 'C:\Development\flutter'
$VcpkgRoot   = 'C:\Development\vcpkg'
$LibclangDir = 'C:\Development\LLVM-15\bin'
$VsPath      = 'C:\Program Files\Microsoft Visual Studio\18\Enterprise'
$MsvcVersion = '14.44'
$RustToolchain = '1.75'
$EngineSha256  = '295D3767A5E5C4017F4877E67A4A8926178ECDFBB1196C3BD21EC5F5097F5ED3'
$Out  = "$Repo\tbg\out"
$Dist = "$Out\dist"

function Step($msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan }
function Fail($msg) { throw "build.ps1: $msg" }
function Run($exe, [string[]]$argv) {
    & $exe @argv
    if ($LASTEXITCODE -ne 0) { Fail "'$exe $argv' failed with exit code $LASTEXITCODE" }
}
function Git([string[]]$argv) { Run git $argv }
function IsPatchApplied($dir, $patch) {
    git -C $dir apply --check -R $patch 2>$null
    return $LASTEXITCODE -eq 0
}

Set-Location $Repo
$Version = (Select-String -Path Cargo.toml -Pattern '^version\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value

# ---------------------------------------------------------------- preflight
Step "Preflight ($AppName $Version)"
Git @('submodule', 'update', '--init', '--recursive')

$dirty = git status --porcelain --ignore-submodules=none -- libs/hbb_common res/msi flutter/pubspec.lock
if ($dirty) { Fail "libs/hbb_common, res/msi or flutter/pubspec.lock has local changes; commit or revert them first:`n$dirty" }

foreach ($p in @($FlutterRoot, $VcpkgRoot, $LibclangDir, $VsPath)) {
    if (-not (Test-Path $p)) { Fail "missing $p (see CLAUDE.md, 'Toolchain')" }
}

$flutterPatches = @(Get-ChildItem "$Repo\tbg\flutter-patches\*.patch") +
                  (Get-Item "$Repo\.github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff")
foreach ($p in $flutterPatches) {
    if (-not (IsPatchApplied $FlutterRoot $p.FullName)) {
        Fail "Flutter patch not applied: $($p.Name). Run: git -C $FlutterRoot apply `"$($p.FullName)`", then delete $FlutterRoot\bin\cache\flutter_tools.snapshot (see CLAUDE.md)"
    }
}
$engine = "$FlutterRoot\bin\cache\artifacts\engine\windows-x64-release\flutter_windows.dll"
if (-not (Test-Path $engine) -or (Get-FileHash $engine).Hash -ne $EngineSha256) {
    Fail "Flutter engine is not RustDesk's: extract windows-x64-release.zip from the rustdesk/engine release 'main' over $(Split-Path $engine) (see CLAUDE.md)"
}

$baseline = (Get-Content vcpkg.json -Raw | ConvertFrom-Json).'vcpkg-configuration'.'default-registry'.baseline
$vcpkgHead = git -C $VcpkgRoot rev-parse HEAD
if ($vcpkgHead -ne $baseline) { Fail "vcpkg at $vcpkgHead, vcpkg.json wants $baseline. Run: git -C $VcpkgRoot fetch; git -C $VcpkgRoot checkout $baseline; $VcpkgRoot\bootstrap-vcpkg.bat -disableMetrics" }

if (-not ((rustup toolchain list) -match "^$([regex]::Escape($RustToolchain))-")) { Fail "Rust $RustToolchain missing. Run: rustup toolchain install $RustToolchain --profile minimal -c rustfmt" }
$installed = cargo install --list
if (-not ($installed -match '^flutter_rust_bridge_codegen v1\.80\.1:')) { Fail 'flutter_rust_bridge_codegen 1.80.1 missing. Run: cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked' }
if (-not ($installed -match '^cargo-expand v1\.0\.95:')) { Fail "cargo-expand 1.0.95 missing. Run: cargo +$RustToolchain install cargo-expand --version 1.0.95 --locked" }

# ---------------------------------------------------------------- environment
Step "MSVC $MsvcVersion developer environment"
$env:PATH = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer;$env:PATH"
$devShell = "$VsPath\Common7\Tools\vsdevshell\Microsoft.VisualStudio.DevShell.dll"
if (-not (Test-Path $devShell)) { $devShell = "$VsPath\Common7\Tools\Microsoft.VisualStudio.DevShell.dll" }
Import-Module $devShell
Enter-VsDevShell -VsInstallPath $VsPath -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64 -vcvars_ver=$MsvcVersion" | Out-Null
if ($env:VCToolsVersion -notlike "$MsvcVersion.*") { Fail "vcvars selected MSVC $env:VCToolsVersion, expected $MsvcVersion (install the 'MSVC v143 - 14.44' VS component)" }
Set-Location $Repo

# Process scope only; the user environment is not changed.
$env:RUSTUP_TOOLCHAIN = $RustToolchain
$env:CMAKE_GENERATOR = 'Visual Studio 18 2026'
$env:CMAKE_GENERATOR_TOOLSET = 'v143'   # honored by Flutter via tbg/flutter-patches
$env:VCPKG_ROOT = $VcpkgRoot
$env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
$env:LIBCLANG_PATH = $LibclangDir
$env:PATH = "$FlutterRoot\bin;$env:PATH"
Write-Host "MSVC $env:VCToolsVersion, $(rustc --version), Flutter $FlutterRoot"

if ($Clean) {
    Step 'Clean'
    foreach ($d in @('target', 'flutter\build', 'tbg\out', 'res\msi\x64', 'res\msi\CustomActions\x64',
                     'res\msi\Package\bin', 'res\msi\Package\obj', 'res\msi\Package\Resources')) {
        if (Test-Path $d) { Remove-Item -Recurse -Force $d }
    }
}
New-Item -ItemType Directory -Force $Out | Out-Null

$hbbPatch = "$Repo\tbg\hbb_common-tbg.patch"
try {
    # ------------------------------------------------------------ vcpkg
    Step 'vcpkg dependencies (x64-windows-static, v143)'
    Run "$VcpkgRoot\vcpkg.exe" @('install', '--triplet', 'x64-windows-static',
        "--overlay-triplets=$Repo\tbg\vcpkg-triplets", "--x-install-root=$VcpkgRoot\installed")

    # ------------------------------------------------------------ branding patch
    Step 'Apply hbb_common branding patch'
    Git @('-C', 'libs/hbb_common', 'apply', $hbbPatch)

    # ------------------------------------------------------------ bridge + build
    Step 'Flutter dependencies and Rust bridge'
    Push-Location flutter
    try { Run flutter @('pub', 'get') } finally { Pop-Location }
    if (-not (Select-String -Quiet -Path flutter\.dart_tool\package_config.json -Pattern '"screen_retriever"')) {
        Fail 'flutter pub get dropped screen_retriever (window_manager dependency). Run the build again.'
    }
    Run flutter_rust_bridge_codegen @('--rust-input', './src/flutter_ffi.rs',
        '--dart-output', './flutter/lib/generated_bridge.dart',
        '--c-output', './flutter/macos/Runner/bridge_generated.h')

    Step 'Build (build.py --portable --flutter --skip-portable-pack --hwcodec --vram)'
    Run python @('.\build.py', '--portable', '--flutter', '--skip-portable-pack', '--hwcodec', '--vram')

    # ------------------------------------------------------------ dist folder
    Step 'Assemble dist folder'
    if (Test-Path $Dist) { Remove-Item -Recurse -Force $Dist }
    Copy-Item -Recurse flutter\build\windows\x64\runner\Release $Dist
    Move-Item "$Dist\rustdesk.exe" "$Dist\$AppName.exe"

    $dl = "$Out\dl"
    if (Test-Path $dl) { Remove-Item -Recurse -Force $dl }
    New-Item -ItemType Directory $dl | Out-Null
    Push-Location $dl
    try {
        Invoke-WebRequest https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip -OutFile usbmmidd_v2.zip
        Expand-Archive usbmmidd_v2.zip -DestinationPath .
        Remove-Item usbmmidd_v2\Win32 -Recurse
        Remove-Item 'usbmmidd_v2\deviceinstaller64.exe', 'usbmmidd_v2\deviceinstaller.exe', 'usbmmidd_v2\usbmmidd.bat'
        Move-Item usbmmidd_v2 $Dist

        $base = 'https://github.com/rustdesk/hbb_common/releases/download/driver'
        Invoke-WebRequest "$base/rustdesk_printer_driver_v4-1.4.zip" -OutFile rustdesk_printer_driver_v4-1.4.zip
        Invoke-WebRequest "$base/printer_driver_adapter.zip" -OutFile printer_driver_adapter.zip
        Invoke-WebRequest "$base/sha256sums" -OutFile sha256sums
        foreach ($z in 'rustdesk_printer_driver_v4-1.4.zip', 'printer_driver_adapter.zip') {
            $want = (Select-String -Path sha256sums -Pattern "^([a-fA-F0-9]{64}) \*$([regex]::Escape($z))$").Matches[0].Groups[1].Value
            if ($want -ne (Get-FileHash $z).Hash) { Fail "checksum mismatch for $z" }
        }
        Expand-Archive rustdesk_printer_driver_v4-1.4.zip -DestinationPath .
        New-Item -ItemType Directory "$Dist\drivers" | Out-Null
        Move-Item rustdesk_printer_driver_v4-1.4 "$Dist\drivers\RustDeskPrinterDriver"
        Expand-Archive printer_driver_adapter.zip -DestinationPath .
        Move-Item printer_driver_adapter.dll $Dist
    } finally { Pop-Location }

    # ------------------------------------------------------------ MSI
    Step 'MSI'
    Git @('apply', "$Repo\tbg\msi-preprocess-quote-exe.patch")
    Push-Location res\msi
    try {
        Run python @('preprocess.py', '-d', $Dist, '--app-name', $AppName, '-m', $Manufacturer)
        # preprocess.py rewrites the license to name the app as licensor; ship upstream's.
        Git @('checkout', '--', 'Package/License.rtf')
        Run msbuild @('msi.sln', '-restore', '-p:RestorePackagesConfig=true', '-p:Configuration=Release',
            '-p:Platform=x64', '/p:TargetVersion=Windows10', '-v:minimal', '-nologo')
    } finally { Pop-Location }
    $msi = "$Out\$FileStem-$Version-x64.msi"
    Move-Item -Force res\msi\Package\bin\x64\Release\en-us\Package.msi $msi
    Step "Done: $msi"
    Get-FileHash $msi | Format-List Algorithm, Hash, Path
} finally {
    Set-Location $Repo
    git checkout -- res/msi flutter/pubspec.lock
    if (IsPatchApplied "$Repo\libs\hbb_common" $hbbPatch) { git -C libs/hbb_common apply -R $hbbPatch }
}
