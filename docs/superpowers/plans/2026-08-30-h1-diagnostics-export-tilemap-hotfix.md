# H1 Diagnostics, Export, and TileMap Hotfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the next iPhone hardware run diagnostically useful, fix the confirmed Vietmap z17/404 and MIME mismatch, and make the sanitized H1 record shareable without changing the Band RPK.

**Architecture:** Keep the existing H1 transport and application envelope unchanged. Tighten failure classification in `H1RenderCoordinator`, carry provider zoom metadata through `VietmapStyleClient` into `H1AssetFactory`, and expose the already-written sanitized record through SwiftUI `ShareLink`.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI, XCTest, XcodeGen, Make/Docker, GitHub Actions.

---

## Task 1: Classify Band result failures at their real boundary

- [ ] Add failing fixtures to `apps/ios/Tests/H1RenderCoordinatorTests.swift` for:
  - legacy Boolean/schema-invalid result -> `RESULT_SCHEMA_INVALID`;
  - valid success result received while transferring -> `RESULT_EARLY`;
  - valid result with mismatched renderer/count/hash metadata -> `RESULT_METADATA_INVALID`.
- [ ] Run the focused iOS test command exposed by the Makefile (or the smallest package/source gate available on Linux) and confirm the assertions fail for the old `ASSET_RESULT_INVALID` behavior.
- [ ] Update `apps/ios/App/H1RenderCoordinator.swift` so only current-run results are classified, stale run/scene results remain ignored, and no raw body is logged.
- [ ] Re-run the focused tests and commit the result-classification change.

## Task 2: Preserve and validate provider zoom bounds

- [ ] Add failing tests to `packages/BlueBandKit/Tests/BlueBandMapCoreTests/VietmapStyleClientTests.swift` covering valid `minzoom`/`maxzoom`, absent bounds, fractional/out-of-range values, contradictory bounds, and conflicting selected-source metadata.
- [ ] Run the focused Swift package test and confirm the new tests fail.
- [ ] Extend `VectorTileTemplate` in `packages/BlueBandKit/Sources/BlueBandMapCore/VietmapStyleClient.swift` with optional `minimumZoom`/`maximumZoom` and strict integer range validation (`0...22`).
- [ ] Re-run the focused package tests and commit the provider-metadata change.

## Task 3: Clamp tile requests and safely accept Vietmap `text/plain` PBF

- [ ] Add failing app-level tests in `apps/ios/Tests/ProjectSmokeTests.swift` (and test helpers there if needed) proving:
  - requested z17 clamps to source z15 before x/y calculation;
  - existing vector MIME types still pass;
  - `text/plain` passes only for HTTPS `maps.vietmap.vn` `.pbf` responses whose body decodes as MVT;
  - foreign host/path and invalid MVT bodies fail;
  - style and final-tile HTTP failures map to `STYLE_HTTP_<status>` and `TILE_HTTP_<status>`.
- [ ] Run the smallest available app test gate and confirm the new expectations fail.
- [ ] Update `apps/ios/Adapters/Rendering/H1AssetFactory.swift` to clamp zoom before coordinate calculation and apply the bounded URL-aware MIME exception.
- [ ] Update provider-code mapping in `apps/ios/App/H1RenderCoordinator.swift` without including URLs, keys, or response bodies.
- [ ] Re-run app tests and commit the TileMap fix.

## Task 4: Replace the write-only Export button and bump only iOS

- [ ] Add a failing source/UI smoke test in `apps/ios/Tests/ProjectSmokeTests.swift` requiring `ShareLink` backed by `lastH1ExportURL` and rejecting the old write-only button.
- [ ] Replace the H1 export action in `apps/ios/App/ContentView.swift` with an enabled `ShareLink` when the sanitized file exists and a visibly disabled label otherwise.
- [ ] Remove the now-unused manual rewrite action from `apps/ios/App/AppModel.swift` if no call sites remain.
- [ ] Bump only iOS from `0.1.1 (2)` to `0.1.2 (3)` in `apps/ios/project.yml` and the in-app version display; leave all Band source and `0.2.3 (5)` metadata untouched.
- [ ] Run app tests and commit the export/version change.

## Task 5: Verify, document, build, and publish flat latest artifacts

- [ ] Run `make test` and record the exact passing totals.
- [ ] Run the repository lint/secret gates required by the Makefile, then `git diff --check`.
- [ ] Update H1 handoff/testing documentation with the new expected outcomes and explicit hardware-acceptance boundary.
- [ ] Push the branch and run only the required GitHub Actions jobs for iOS verification/release; do not add redundant CI.
- [ ] Download the successful release artifact, validate IPA/RPK versions and SHA-256 hashes, and compare the RPK hash with the existing `0.2.3 (5)` file.
- [ ] Replace only the latest files in `/home/hainn/blue/code/blueband-map/artifacts/h1-hybrid/`; keep the directory flat and state exactly which file the tester must reinstall.
- [ ] Finish with a concise POC handoff: changes, test steps, expected output, IPA path, RPK path, and unchanged-RPK note.
