#!/bin/sh
set -eu

sdk_version="$(xcrun --show-sdk-version)"

for target in 14.0 15.0 "$sdk_version"; do
  echo "Building for macOS $target"
  xcodebuild \
    -project Medieval.xcodeproj \
    -scheme Medieval \
    -configuration Debug \
    -derivedDataPath ".build/Compatibility-$target" \
    MACOSX_DEPLOYMENT_TARGET="$target" \
    CODE_SIGNING_ALLOWED=NO \
    build
done
