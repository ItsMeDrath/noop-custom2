#!/usr/bin/env bash
# Builds a real arm64 device product before packaging. Never packages a simulator app.
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'A Mac with Xcode 16 or newer is required to build the iPhone binary.' >&2
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo 'Python 3 is required for the device-package check.' >&2; exit 1; }
mkdir -p build
TASK_LOG_DIR="$(mktemp -d "$TASK_ROOT/build/device-build.XXXXXX")"
printf 'Build log: %s\n' "$TASK_LOG_DIR/xcodebuild.log"
xcodebuild -version
python3 Scripts/validate-nutrition-resource.py
xcodebuild -project WHOOP.xcodeproj -scheme WHOOP -configuration Release \
  -destination 'generic/platform=iOS' -sdk iphoneos -arch arm64 \
  -derivedDataPath build/DeviceDerivedData \
  -resultBundlePath "$TASK_LOG_DIR/WHOOP.xcresult" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build \
  2>&1 | tee "$TASK_LOG_DIR/xcodebuild.log"
TASK_APP="$TASK_ROOT/build/DeviceDerivedData/Build/Products/Release-iphoneos/WHOOP.app"
[[ -d "$TASK_APP" ]] || { echo 'No iPhone app product was produced.' >&2; exit 1; }
TASK_STAGE="$(mktemp -d "$TASK_ROOT/build/ipa.XXXXXX")"
trap 'rm -rf -- "$TASK_STAGE"' EXIT
mkdir -p "$TASK_STAGE/Payload"
/usr/bin/ditto "$TASK_APP" "$TASK_STAGE/Payload/WHOOP.app"
TASK_IPA="$TASK_ROOT/build/WHOOP-unsigned.ipa"
TASK_PENDING_IPA="$TASK_STAGE/WHOOP-unsigned.ipa"
/usr/bin/ditto -c -k --norsrc --keepParent "$TASK_STAGE/Payload" "$TASK_PENDING_IPA"
python3 Scripts/validate-ipa.py "$TASK_PENDING_IPA" > "$TASK_LOG_DIR/package-check.json"
mv -- "$TASK_PENDING_IPA" "$TASK_IPA"
/usr/bin/shasum -a 256 "$TASK_IPA" > "$TASK_IPA.sha256"
printf '\nUnsigned device package: %s\n' "$TASK_IPA"
printf 'It must be signed for your device before installation. HealthKit requires a compatible signing entitlement.\n'
