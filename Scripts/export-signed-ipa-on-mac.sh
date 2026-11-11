#!/usr/bin/env bash
# Requires a real Apple development team and a matching HealthKit-capable profile.
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'A Mac with full Xcode 16 or newer is required.' >&2; exit 1
fi
if [[ $# -ne 2 || ! "$1" =~ ^[A-Z0-9]{10}$ || ! "$2" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo 'Usage: bash Scripts/export-signed-ipa-on-mac.sh APPLE_TEAM_ID your.unique.bundleid' >&2
  echo 'Sign in with your Apple account in Xcode first; never put its password in this command.' >&2
  exit 1
fi
TASK_TEAM="$1"; TASK_BUNDLE="$2"
command -v python3 >/dev/null 2>&1 || { echo 'Python 3 is required.' >&2; exit 1; }
python3 Scripts/validate-nutrition-resource.py
mkdir -p build
TASK_EXPORT="$(mktemp -d "$TASK_ROOT/build/signed-export.XXXXXX")"
python3 - "$TASK_EXPORT/ExportOptions.plist" "$TASK_TEAM" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({'method':'debugging','teamID':sys.argv[2],
                  'signingStyle':'automatic','destination':'export',
                  'manageAppVersionAndBuildNumber':False}, output)
PY
xcodebuild -project WHOOP.xcodeproj -scheme WHOOP -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$TASK_EXPORT/WHOOP.xcarchive" \
  -resultBundlePath "$TASK_EXPORT/Archive.xcresult" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TASK_TEAM" APP_BUNDLE_IDENTIFIER="$TASK_BUNDLE" \
  CODE_SIGN_STYLE=Automatic archive 2>&1 | tee "$TASK_EXPORT/archive.log"
xcodebuild -exportArchive -archivePath "$TASK_EXPORT/WHOOP.xcarchive" \
  -exportPath "$TASK_EXPORT/ipa" -exportOptionsPlist "$TASK_EXPORT/ExportOptions.plist" \
  -allowProvisioningUpdates 2>&1 | tee "$TASK_EXPORT/export.log"
TASK_IPA="$TASK_EXPORT/ipa/WHOOP.ipa"
[[ -f "$TASK_IPA" ]] || { echo 'Xcode did not produce WHOOP.ipa. Inspect the export log.' >&2; exit 1; }
python3 Scripts/validate-ipa.py "$TASK_IPA" > "$TASK_EXPORT/package-check.json"
/usr/bin/shasum -a 256 "$TASK_IPA" > "$TASK_IPA.sha256"
printf '\nSigned development IPA: %s\n' "$TASK_IPA"
printf 'It installs only on devices covered by the exported provisioning profile.\n'
