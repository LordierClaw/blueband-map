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
location=$(/usr/libexec/PlistBuddy -c 'Print :NSLocationWhenInUseUsageDescription' "$plist")
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
short_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
build_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")

[[ "$bundle_id" == "dev.lordierclaw.bluebandmap" ]]
[[ "$minimum_os" == "17.0" ]]
[[ "$short_version" == "0.5.9" ]]
[[ "$build_version" == "25" ]]
[[ -n "$bluetooth" ]]
[[ -n "$location" ]]

background_modes=$(plutil -extract UIBackgroundModes json -o - "$plist")
python3 - "$background_modes" <<'PY'
import json, sys
assert set(json.loads(sys.argv[1])) == {"location", "bluetooth-central"}, \
    "UIBackgroundModes must contain only location and bluetooth-central"
PY

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
