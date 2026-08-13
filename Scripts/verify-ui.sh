#!/bin/sh
set -eu

# UI tests drive the real app through the window server, so they need a signed
# build and take minutes. Keep them out of Scripts/verify.sh.
#
# XCUITest inspects every running application on the machine. A background app
# that never settles will stall the run — Grammarly's update service has been
# seen holding testLaunch for two minutes before failing. Quit noisy background
# apps if a launch test hangs.
xcodebuild \
  -project Medieval.xcodeproj \
  -scheme Medieval \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  -only-testing:MedievalTestsUI \
  test
