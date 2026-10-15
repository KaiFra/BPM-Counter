#!/usr/bin/env bash
# Reports the size of an APK and fails if it contains native libraries for any
# ABI other than 64-bit ARM (arm64-v8a).
# Usage: tool/check_apk_abi.sh path/to/app.apk
set -euo pipefail

apk="$1"
expected="arm64-v8a"

# File entries look like lib/<abi>/libfoo.so; skip directory entries.
abis="$( (unzip -Z1 "$apk" 'lib/*' 2>/dev/null || true) \
  | awk -F/ '$2 != "" && $3 != "" { print $2 }' | sort -u | paste -sd, -)"
size="$(numfmt --to=si --format=%.1f --suffix=B "$(stat -c %s "$apk")")"

echo "::notice title=APK::$size, native libraries: ${abis:-none}"
if [[ "$abis" != "$expected" ]]; then
  others="$( (unzip -Z1 "$apk" 'lib/*' 2>/dev/null || true) \
    | awk -v keep="lib/$expected/" 'index($0, keep) != 1 && !/\/$/' | paste -sd' ' -)"
  echo "::error::Expected native libraries only for $expected, found: ${abis:-none}. Other files: ${others:-none}"
  exit 1
fi
