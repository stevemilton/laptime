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

echo ""
echo "Build complete. Uploading to TestFlight..."
xcrun altool --upload-app --type ios \
  -f build/ios/ipa/TestTrack.ipa \
  --apiKey PTUAC5QR6U \
  --apiIssuer 951dbb13-6540-4a22-b425-4f00f11d9119

echo ""
echo "Upload complete. Build should appear in TestFlight shortly."
