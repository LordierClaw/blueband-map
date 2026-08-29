#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-}"
if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  echo "usage: $0 /path/to/BlueBandMap.app" >&2
  exit 2
fi

plist="$app_path/Info.plist"
test -f "$plist"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
minimum_os=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$plist")
bluetooth=$(/usr/libexec/PlistBuddy -c 'Print :NSBluetoothAlwaysUsageDescription' "$plist")
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")

[[ "$bundle_id" == "dev.lordierclaw.bluebandmap" ]]
[[ "$minimum_os" == "17.0" ]]
[[ -n "$bluetooth" ]]
if /usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes' "$plist" >/dev/null 2>&1; then
  echo "UIBackgroundModes must be absent" >&2
  exit 1
fi

families=$(plutil -extract UIDeviceFamily json -o - "$plist")
python3 - "$families" <<'PY'
import json, sys
assert json.loads(sys.argv[1]) == [1], "UIDeviceFamily must contain iPhone only"
PY

test ! -e "$app_path/_CodeSignature"
test ! -e "$app_path/embedded.mobileprovision"
archs=$(lipo -archs "$app_path/$executable")
case " $archs " in
  *" arm64 "*) ;;
  *) echo "main executable is missing arm64: $archs" >&2; exit 1 ;;
esac

echo "verified unsigned arm64 iPhone artifact: $app_path"
