#!/usr/bin/env bash
set -euo pipefail

project="apps/ios/project.yml"
app_model="apps/ios/App/AppModel.swift"
test -f "$project"
test -f "$app_model"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER: dev.lordierclaw.bluebandmap' "$project"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER: dev.lordierclaw.bluebandmap.tests' "$project"
grep -Fq 'iOS: "17.0"' "$project"
grep -Fq 'INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription:' "$project"
grep -Fq 'path: ../../packages/BlueBandKit' "$project"
if grep -Fq 'UIBackgroundModes' "$project"; then
  echo "UIBackgroundModes must stay absent: the app is foreground-only" >&2
  exit 1
fi

grep -Fq 'let operationTask: Task<Void, Never> = Task { @MainActor [weak self] in' "$app_model"
grep -Fq 'guard let self else { return }' "$app_model"

echo "iOS project metadata OK"
