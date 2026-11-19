#!/bin/sh
# Wraps ptouchkit-testpage in an app bundle so macOS lets it use Bluetooth.
# macOS checks NSBluetoothAlwaysUsageDescription on the app that launched a
# process, so run the bundle with `open`, not from a shell.
#
#   Tools/hardware/make-testpage-app.sh
#   open -W --stdout "$PWD/testpage.log" --stderr "$PWD/testpage.log" \
#     .build/PTouchKitTestPage.app --args print --bluetooth
set -eu
cd "$(dirname "$0")/../.."
swift build -c release --product ptouchkit-testpage
app=.build/PTouchKitTestPage.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/ptouchkit-testpage" "$app/Contents/MacOS/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.ptouchkit.testpage</string>
  <key>CFBundleName</key><string>PTouchKit Test Page</string>
  <key>CFBundleExecutable</key><string>ptouchkit-testpage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Prints test pages on a Brother P-touch label printer.</string>
</dict></plist>
PLIST
codesign -s - -f "$app" >/dev/null 2>&1
echo "Built $app"
