#!/bin/bash
# Build and upload TestTrack IPA to TestFlight.
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

echo "Building TestTrack IPA..."
flutter build ipa --release $DART_DEFINE_ARGS

IPA_PATH="build/ios/ipa/TestTrack.ipa"

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

# Re-package the IPA
cd "$WORK_DIR"
zip -q -r "$SCRIPT_DIR/$IPA_PATH" Payload
cd "$SCRIPT_DIR"
rm -rf "$WORK_DIR"
echo "IPA re-packaged."

echo ""
echo "Uploading to TestFlight..."
xcrun altool --upload-app --type ios \
  -f "$IPA_PATH" \
  --apiKey PTUAC5QR6U \
  --apiIssuer 951dbb13-6540-4a22-b425-4f00f11d9119

echo ""
echo "Upload complete. Build should appear in TestFlight shortly."
