# Fixed Navigation Marker Visuals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the first active route with a fixed upright user marker, move edge destinations outward by 6 pixels, format compact distances, and release new IPA/RPK artifacts.

**Architecture:** Capture the actual Vietmap overlay projection for the matched route anchor and return it with the snapshot, then publish that fixed `(106, 374)` anchor instead of rotating or following the marker. Reuse the existing safe-mask math with a zero-margin copy only for the 20x20 edge ring, and keep distance formatting entirely on the Band.

**Tech Stack:** Swift/XCTest, Vietmap `MGLMapSnapshotter`, Vela UX JavaScript, Node test runner, Make/Docker, GitHub Actions.

---

### Task 1: Authoritative fixed route anchor

**Files:**
- Modify: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`
- Modify: `apps/ios/Tests/RouteCardRenderCoordinatorTests.swift`

- [ ] Add iOS tests asserting the snapshot output carries the route overlay's projected matched point and every prepare/live update uses `(106, 374)` with heading bucket `0`.
- [ ] Run the iOS syntax/target checks and confirm the new assertions fail because the output has no authoritative anchor and previews still use projected live markers.
- [ ] In the snapshot overlay handler, capture `overlay.point(for: request.matchedPosition)` before drawing and return it as `presentationAnchor` in `VietmapSnapshotOutput`.
- [ ] Reject a snapshot whose anchor is non-finite or differs from `(106, 374)` after rounding; this prevents publishing a raster whose route cannot meet the fixed marker.
- [ ] Build `RenderNavigationPreview` and `NavigationUpdate` with `x: 106`, `y: 374`, and `headingBucket: 0`; keep map heading selection unchanged.
- [ ] Run targeted Swift checks and confirm the fixed-anchor tests pass.

### Task 2: Upright triangular marker and compact distance

**Files:**
- Modify: `apps/band/scripts/generate-icon.mjs`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`

- [ ] Add failing Node tests that all eight marker PNGs are byte-identical upright triangles, marker style stays at `left:83px;top:347px`, and distance boundaries render `0 m`, `999 m`, `1 km`, `1.4 km`, `2 km`, and `12.3 km` in preview and live paths.
- [ ] Run `make test-rpk` and confirm failures reflect the current rotated concave marker, moving marker styles, and raw metre labels.
- [ ] Replace the concave polygon with a dark outer triangle `[[23,6],[38,43],[8,43]]` and green inner triangle `[[23,13],[32,37],[14,37]]`; write the same bitmap to all eight compatibility filenames.
- [ ] Add one `formatDistance(distanceM)` method using integer metres below 1,000 and rounded one-decimal kilometres with `.0` removed at or above 1,000.
- [ ] Use the formatter in `handleNavigationUpdate` and staged preview, and always place the marker at `(106,374)` with `marker-0.png`.
- [ ] Run `make test-rpk` and confirm resource, UI, preview, refresh, and transfer tests pass.

### Task 3: Six-pixel outward edge destination

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/BandDisplaySafeMask.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/BandDisplaySafeMaskTests.swift`
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderProtocol.swift`
- Modify: `apps/band/src/common/render-protocol.js`
- Modify: `apps/band/src/pages/index/index.ux`

- [ ] Add failing tests for all eight directions proving the edge ring moves outward by 6 pixels from the conservative point while its complete 20x20 bounds remain inside the physical curved contour.
- [ ] Run `make test-swift` and `make test-rpk`; confirm the current visual-margin point fails the outward-distance assertions.
- [ ] Add a minimal `withoutVisualMargin` mask value and compute edge destinations with it; do not alter the production mask constants or marker/visible-pin validation.
- [ ] Validate `destinationMode=edge` against the physical zero-margin mask in Swift and Band prepare validators; keep `visible` on the normal six-pixel visual margin.
- [ ] Run the targeted Swift and RPK suites and confirm preview/live destination tests pass.

### Task 4: Versions, verification, and artifacts

**Files:**
- Modify: `apps/ios/project.yml`
- Modify: `apps/ios/App/BlueBandMapApp.swift`
- Modify: `tools/ios/test-project-metadata.sh`
- Modify: `apps/band/package.json`
- Modify: `apps/band/package-lock.json`
- Modify: `apps/band/src/manifest.json`
- Modify: `apps/band/scripts/verify-rpk.mjs`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `docs/testing/handoffs/hybrid-heading-up-guidance.md`

- [ ] Update assertions first for IPA `0.5.3 (19)` and RPK `0.6.2 (17)` and confirm metadata tests fail.
- [ ] Apply the exact version/build changes and update the manual hardware test guide with the fixed marker, route-anchor, edge-ring, and distance checks.
- [ ] Run `make clean && make bootstrap && make test && make lint && scripts/verify-no-secrets.sh && git diff --check`.
- [ ] Commit directly on `main`, push, wait for GitHub iOS/Band/Swift/repository checks, and download the unsigned IPA from the successful iOS run.
- [ ] Replace `artifacts/handoff` atomically with the new IPA, RPK, handoff guide, and checksums; verify versions, hashes, and that no old artifact remains.
