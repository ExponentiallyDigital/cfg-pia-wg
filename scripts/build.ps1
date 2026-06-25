# Builder script

# Extract version from pubspec.yaml and strip the build number
$versionLine = Get-Content .\pubspec.yaml | Select-String -Pattern "^version:"
if ($versionLine -match '^version:\s*([^+ ]+)') {
    $version = $Matches[1].Trim()
} else {
    Write-Error "Could not parse version from pubspec.yaml"
    Exit
}

Write-Host "Wiping old caches..." -ForegroundColor Cyan
flutter clean

Write-Host "Fetching dependencies..." -ForegroundColor Cyan
flutter pub get --enforce-lockfile

Write-Host "Adding icons..." -ForegroundColor Cyan
dart run flutter_launcher_icons

Write-Host "Running analyze..." -ForegroundColor Cyan
flutter analyze

Write-Host "Running tests..." -ForegroundColor Cyan
flutter test --coverage

Write-Host "Compiling debug version..." -ForegroundColor Green
flutter build apk --debug

Write-Host "Compiling release version..." -ForegroundColor Green
flutter build apk --release

# Move and rename the production output file
$defaultApk = ".\build\app\outputs\flutter-apk\app-release.apk"
$targetApk = ".\build\app\outputs\flutter-apk\cfg_pia_wireguard-v${version}_release.apk"
if (Test-Path $defaultApk) {
    Move-Item -Path $defaultApk -Destination $targetApk -Force
    Write-Host "Renamed release APK to: $targetApk" -ForegroundColor Green
}

Write-Host "Compiling signed Android App Bundle (.aab) for Google Play..." -ForegroundColor Green
flutter build appbundle --release

Write-Host ""
Write-Host "-------------------------------------------------------------------------------" -ForegroundColor DarkMagenta
Write-Host "Play Store:   " -ForegroundColor White -NoNewline
Write-Host ".\build\app\outputs\" -ForegroundColor Green -NoNewline
Write-Host "bundle\release\" -ForegroundColor Cyan -NoNewline
Write-Host "cfg_pia_wireguard-release.aab" -ForegroundColor Yellow
Write-Host "Side loading: " -ForegroundColor White -NoNewline
Write-Host ".\build\" -ForegroundColor Green -NoNewline
Write-Host "cfg_pia_wireguard-v${version}_release.apk" -ForegroundColor Yellow
Write-Host "Debug:        " -ForegroundColor White -NoNewline
Write-Host ".\build\app\outputs\" -ForegroundColor Green -NoNewline
Write-Host "flutter-apk\" -ForegroundColor Cyan -NoNewline
Write-Host "app-debug.apk" -ForegroundColor Yellow
Write-Host "-------------------------------------------------------------------------------" -ForegroundColor DarkMagenta
Write-Host ""
