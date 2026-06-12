#!/bin/bash
# Build and upload the LapTime IPA to TestFlight.
# Reads API keys from dart_defines.env automatically.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/dart_defines.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found"
  exit 1
fi

# Read dart defines from env file
DART_DEFINE_ARGS=""
while IFS='=' read -r key value; do
  # Skip empty lines and comments
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  DART_DEFINE_ARGS="$DART_DEFINE_ARGS --dart-define=$key=$value"
done < "$ENV_FILE"

# Version comes from pubspec.yaml — the single source of truth.
# The Runner target picks it up via FLUTTER_BUILD_NAME/NUMBER, but the
# WatchApp target is a plain Xcode target with no Flutter config, so its
# Info.plist must be stamped here. App Store Connect tracks the watch
# bundle id's version independently and rejects uploads that don't
# increase it (and requires it to match the companion app).
VERSION_LINE=$(grep '^version:' "$SCRIPT_DIR/pubspec.yaml" | awk '{print $2}')
BUILD_NAME="${VERSION_LINE%%+*}"
BUILD_NUMBER="${VERSION_LINE##*+}"
echo "Version from pubspec: $BUILD_NAME ($BUILD_NUMBER)"

WATCH_PLIST="$SCRIPT_DIR/ios/WatchApp/Info.plist"
if [ -f "$WATCH_PLIST" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $BUILD_NAME" "$WATCH_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$WATCH_PLIST"
  echo "Stamped WatchApp Info.plist to $BUILD_NAME ($BUILD_NUMBER)"
fi

echo "Building LapTime IPA..."
flutter build ipa --release $DART_DEFINE_ARGS

# flutter names the .ipa after the app; don't assume the display name.
IPA_PATH=$(ls "$SCRIPT_DIR"/build/ios/ipa/*.ipa | head -1)
if [ -z "$IPA_PATH" ]; then
  echo "ERROR: no .ipa found in build/ios/ipa/"
  exit 1
fi
echo "IPA: $IPA_PATH"

# Strip simulator architectures from embedded frameworks inside the IPA.
# Some Flutter packages ship fat binaries with x86_64 simulator slices
# that App Store Connect rejects.
echo ""
echo "Stripping simulator frameworks from IPA..."
WORK_DIR=$(mktemp -d)
unzip -q "$IPA_PATH" -d "$WORK_DIR"

find "$WORK_DIR/Payload" -name '*.framework' -type d | while read -r framework; do
  binary_name=$(basename "$framework" .framework)
  binary_path="$framework/$binary_name"
  if [ ! -f "$binary_path" ]; then
    continue
  fi

  # Strip x86_64 simulator slices (Intel simulator)
  if lipo -info "$binary_path" 2>/dev/null | grep -q 'x86_64'; then
    echo "  Stripping x86_64 from $binary_name"
    lipo -remove x86_64 "$binary_path" -output "$binary_path" 2>/dev/null || true
  fi

  # Detect arm64 simulator platform using vtool (Apple Silicon simulator).
  # The binary may be arm64 but tagged with platform IOSSIMULATOR instead of IOS.
  if xcrun vtool -show "$binary_path" 2>/dev/null | grep -q 'IOSSIMULATOR'; then
    echo "  Removing simulator framework: $binary_name"
    rm -rf "$framework"
  fi
done

# Sanity check: print every bundle's version so a stale/pinned number is
# visible BEFORE the upload burns an App Store Connect attempt.
echo ""
echo "Bundle versions in IPA:"
find "$WORK_DIR/Payload" -name 'Info.plist' -maxdepth 4 | while read -r plist; do
  bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null) || continue
  ver=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null) || continue
  build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist" 2>/dev/null) || continue
  echo "  $bundle: $ver ($build)"
done

# Re-package the IPA
cd "$WORK_DIR"
zip -q -r "$IPA_PATH" Payload
cd "$SCRIPT_DIR"
rm -rf "$WORK_DIR"
echo "IPA re-packaged."

echo ""
echo "Uploading to TestFlight..."
UPLOAD_LOG=$(mktemp)
# altool can exit 0 even when the upload is rejected — check its output.
xcrun altool --upload-app --type ios \
  -f "$IPA_PATH" \
  --apiKey PTUAC5QR6U \
  --apiIssuer 951dbb13-6540-4a22-b425-4f00f11d9119 \
  2>&1 | tee "$UPLOAD_LOG"

if grep -q "ERROR" "$UPLOAD_LOG"; then
  echo ""
  echo "UPLOAD FAILED — see errors above."
  rm -f "$UPLOAD_LOG"
  exit 1
fi
rm -f "$UPLOAD_LOG"

echo ""
echo "Upload complete. Build should appear in TestFlight shortly."
