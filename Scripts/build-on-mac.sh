#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'This step requires a Mac with Xcode 16 or newer. Open WHOOP.xcodeproj on your Mac.' >&2
  exit 1
fi
swift test --parallel
python3 Scripts/validate-nutrition-resource.py
xcodebuild -project WHOOP.xcodeproj -scheme WHOOP -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
printf '\nSimulator build: %s\n' "$TASK_ROOT/build/DerivedData/Build/Products/Debug-iphonesimulator/WHOOP.app"
