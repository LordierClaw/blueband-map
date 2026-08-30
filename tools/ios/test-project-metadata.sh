#!/usr/bin/env bash
set -euo pipefail

project="apps/ios/project.yml"
app_model="apps/ios/App/AppModel.swift"
h1_state="apps/ios/App/H1State.swift"
h1_coordinator="apps/ios/App/H1RenderCoordinator.swift"
h1_factory="apps/ios/Adapters/Rendering/H1AssetFactory.swift"
test -f "$project"
test -f "$app_model"
test -f "$h1_state"
test -f "$h1_coordinator"
test -f "$h1_factory"
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
grep -Fq 'func startH1(mode: H1TestMode) async' "$app_model"
grep -Fq 'h1Session: (any H1SessionSending)?' "$app_model"
grep -Fq 'ForEach(H1TestMode.allCases' apps/ios/App/ContentView.swift
grep -Fq 'try await styleClient.discover(tileMapKey:' "$h1_factory"
grep -Fq 'VectorSceneCodec.encode(scene)' "$h1_factory"

echo "iOS project metadata OK"
