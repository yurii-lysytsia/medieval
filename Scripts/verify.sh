#!/bin/sh
set -eu

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "swiftformat is required. Install it with: brew install swiftformat" >&2
  exit 1
fi

swiftformat --lint --cache ignore Medieval MedievalDomain MedievalTests MedievalTestsUI

# Unit tests only. The UI tests need code signing, take minutes, and drive the
# real window server, so they run from Scripts/verify-ui.sh instead of holding
# up the fast local gate.
xcodebuild \
  -project Medieval.xcodeproj \
  -scheme Medieval \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  -only-testing:MedievalTests \
  CODE_SIGNING_ALLOWED=NO \
  test
