#!/bin/zsh
# Builds a release app bundle at dist/Delay No More.app (ad-hoc signed).
set -eu
root="${0:A:h:h}"
version="1.11.0"
build="26"
app_dir="$root/dist/Delay No More.app"
# The newest Command Line Tools SDK has lacked a SwiftUI macro plugin before;
# prefer the known-good 15.2 SDK when it is installed.
sdk_path="${DELAY_NO_MORE_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk}"
if [[ ! -d "$sdk_path" ]]; then sdk_path=$(xcrun --show-sdk-path); fi
export SDKROOT="$sdk_path"
swift_build=(swift build --disable-sandbox --sdk "$sdk_path" --package-path "$root"
             -c release -debug-info-format none --product DelayNoMore)
"${swift_build[@]}"
binary_dir=$("${swift_build[@]}" --show-bin-path)

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
rm -f "$app_dir/Contents/MacOS/DelayNoMore"  # new inode; a running copy keeps its mapped file
cp "$binary_dir/DelayNoMore" "$app_dir/Contents/MacOS/DelayNoMore"
cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>DelayNoMore</string>
<key>CFBundleIdentifier</key><string>com.delaynomore.desktop</string>
<key>CFBundleName</key><string>Delay No More</string>
<key>CFBundleDisplayName</key><string>Delay No More</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Delay No More switches to the terminal tab of the agent session you clicked.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 "$root/scripts/make-icns.py" "$root/assets/AppIcon.png" "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist" >/dev/null
touch "$app_dir"
print "Packaged $version ($build): $app_dir"
