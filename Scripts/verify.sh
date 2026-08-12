#!/bin/sh
set -eu

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "swiftformat is required. Install it with: brew install swiftformat" >&2
  exit 1
fi

swiftformat --lint --cache ignore Medieval Tests Package.swift
swift test
xcodebuild \
  -project Medieval.xcodeproj \
  -scheme Medieval \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
