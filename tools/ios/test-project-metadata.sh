#!/usr/bin/env bash
set -euo pipefail

project="apps/ios/project.yml"
test -f "$project"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER: dev.lordierclaw.bluebandmap' "$project"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER: dev.lordierclaw.bluebandmap.tests' "$project"
grep -Fq 'iOS: "17.0"' "$project"
grep -Fq 'INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription:' "$project"
grep -Fq 'INFOPLIST_KEY_NSLocationWhenInUseUsageDescription:' "$project"
grep -Fq 'path: ../../packages/BlueBandKit' "$project"
grep -Fq 'CURRENT_PROJECT_VERSION: 21' "$project"
grep -Fq 'MARKETING_VERSION: 0.5.5' "$project"
grep -Fq 'static let version = "0.5.5"' apps/ios/App/BlueBandMapApp.swift
if grep -Eq 'VietmapRouteOverlay\.translated|offset: offset' apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift; then
  echo "route overlay must use the snapshot camera projection without a private translation" >&2
  exit 1
fi
if grep -Fq 'UIBackgroundModes' "$project"; then
  echo "UIBackgroundModes must stay absent: the app is foreground-only" >&2
  exit 1
fi

echo "iOS project metadata OK"
