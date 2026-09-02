#!/usr/bin/env bash
set -euo pipefail

project="apps/ios/project.yml"
test -f "$project"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER: dev.lordierclaw.bluebandmap' "$project"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER: dev.lordierclaw.bluebandmap.tests' "$project"
grep -Fq 'iOS: "17.0"' "$project"
grep -Fq 'INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription:' "$project"
grep -Fq 'INFOPLIST_KEY_NSLocationWhenInUseUsageDescription:' "$project"
grep -Fq 'INFOPLIST_KEY_UIBackgroundModes: [location, bluetooth-central]' "$project"
grep -Fq 'path: ../../packages/BlueBandKit' "$project"
grep -Fq 'CURRENT_PROJECT_VERSION: 25' "$project"
grep -Fq 'MARKETING_VERSION: 0.5.9' "$project"
grep -Fq 'static let version = "0.5.9"' apps/ios/App/BlueBandMapApp.swift
grep -Fq 'scale: 2,' apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift
grep -Fq '.interpolation(.high)' apps/ios/App/ContentView.swift
grep -Fq 'mask.destinationEdge.destinationEdgePoint' apps/ios/App/AppModel.swift
if grep -Fq '.interpolation(.none)' apps/ios/App/ContentView.swift; then
  echo "route preview must not use nearest-neighbour interpolation" >&2
  exit 1
fi
if grep -Eq 'VietmapRouteOverlay\.translated|offset: offset' apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift; then
  echo "route overlay must use the snapshot camera projection without a private translation" >&2
  exit 1
fi
location_source="apps/ios/Adapters/Location/ForegroundLocationClient.swift"
grep -Fq 'CLBackgroundActivitySession' "$location_source"
grep -Fq 'manager.allowsBackgroundLocationUpdates = true' "$location_source"
grep -Fq 'manager.allowsBackgroundLocationUpdates = false' "$location_source"
grep -Fq 'backgroundActivitySession?.invalidate()' "$location_source"
run_navigation=$(sed -n '/private func runNavigation/,/let gpsStarted/p' apps/ios/App/AppModel.swift)
grep -Fq 'locationClient.stop()' <<<"$run_navigation"

echo "iOS project metadata OK"
