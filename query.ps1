# --- FIX 1: build.py output filename ---
$bp = "C:\Development\rustdesk-tbg\build.py"
(Get-Content $bp -Raw) -replace 'rustdesk-\{version\}-install\.exe', 'tbg-remote-support-{version}-install.exe' | Set-Content $bp -NoNewline

# --- FIX 2: generate.py default folder ---
$gen = "C:\Development\rustdesk-tbg\libs\portable\generate.py"
(Get-Content $gen -Raw) -replace "folder = options\.folder or './rustdesk'", "folder = options.folder or './tbg-remote-support'" | Set-Content $gen -NoNewline

# --- VERIFY ---
Write-Host "=== build.py output filename ===" -ForegroundColor Cyan
Select-String -Path $bp -Pattern "install\.exe" | Select-Object LineNumber, Line

Write-Host "`n=== generate.py default folder ===" -ForegroundColor Cyan
Select-String -Path $gen -Pattern "folder = options\.folder" | Select-Object LineNumber, Line