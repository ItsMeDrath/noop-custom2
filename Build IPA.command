#!/usr/bin/env bash
# Double-click after extracting on a Mac with full Xcode installed.
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TASK_STATUS=0
if /bin/bash "$TASK_ROOT/Scripts/package-ipa-on-mac.sh"; then
  /usr/bin/open -R "$TASK_ROOT/build/WHOOP-unsigned.ipa"
else
  TASK_STATUS=$?
  printf '\nBuild did not finish. The error above or the build log explains why.\n' >&2
fi
if [[ -t 0 ]]; then read -r -p 'Press Return to close this window…' TASK_REPLY; fi
exit "$TASK_STATUS"
