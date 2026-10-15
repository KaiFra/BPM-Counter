#!/usr/bin/env bash
# Fails if an APK requests any permission beyond the allowed set.
# Usage: tool/check_apk_permissions.sh path/to/app.apk
set -euo pipefail

apk="$1"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
aapt2="$(ls -d "$sdk"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -n 1)"
if [[ -z "$aapt2" ]]; then
  echo "aapt2 not found in \$ANDROID_HOME/build-tools" >&2
  exit 2
fi

allowed=(
  "android.permission.RECORD_AUDIO"
  # Install-time permissions for the optional "phone audio" capture service.
  "android.permission.FOREGROUND_SERVICE"
  "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"
  # Signature-level permission AndroidX declares for the app's own
  # broadcast receivers. Not user-visible, no access to anything.
  "flkaiser.de.bpmcounter.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
)

echo "Permissions in $apk:"
mapfile -t requested < <("$aapt2" dump permissions "$apk" \
  | grep -E '^uses-permission' | sed -E "s/.*name='([^']+)'.*/\1/" | sort -u)
printf '  %s\n' "${requested[@]}"

status=0
for permission in "${requested[@]}"; do
  if [[ ! " ${allowed[*]} " =~ " ${permission} " ]]; then
    echo "::error::Unexpected permission: $permission"
    status=1
  fi
done
exit $status
