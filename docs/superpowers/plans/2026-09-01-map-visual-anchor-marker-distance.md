# Fixed Navigation Marker Visuals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the first active route with a fixed upright user marker, move edge destinations outward by 6 pixels, format compact distances, and release new IPA/RPK artifacts.

**Architecture:** Translate the Vietmap route overlay so its matched route anchor lands at `(106, 374)`, then publish that fixed anchor instead of rotating or following the marker. Reuse the existing safe-mask math with a zero-margin copy only for the 20x20 edge ring, and keep distance formatting entirely on the Band.

**Tech Stack:** Swift/XCTest, Vietmap `MGLMapSnapshotter`, Vela UX JavaScript, Node test runner, Make/Docker, GitHub Actions.

---

### Task 1: Authoritative fixed route anchor

**Files:**
- Modify: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`
- Modify: `apps/ios/Tests/AppModelPickerTests.swift`

- [x] Add iOS tests asserting the overlay translation lands at `(106, 374)` and every prepare/live update uses that fixed marker with heading bucket `0`.
- [x] Run the iOS target checks and confirm the assertions fail while previews still use projected live markers.
- [x] Translate all route-overlay paths and the maneuver ring by the matched-position offset to `(106, 374)`.
- [x] Build `RenderNavigationPreview` and `NavigationUpdate` with `x: 106`, `y: 374`, and `headingBucket: 0`; keep map heading selection unchanged.
- [x] Run targeted Swift checks and confirm the fixed-anchor tests pass.

### Task 2: Upright triangular marker and compact distance

**Files:**
- Modify: `apps/band/scripts/generate-icon.mjs`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`

- [x] Add failing Node tests that all eight marker PNGs are byte-identical upright triangles, marker style stays at `left:83px;top:347px`, and distance boundaries render `0 m`, `999 m`, `1 km`, `1.4 km`, `2 km`, and `12.3 km` in preview and live paths.
- [x] Run `make test-rpk` and confirm failures reflect the current rotated concave marker, moving marker styles, and raw metre labels.
- [x] Replace the concave polygon with a dark outer triangle `[[23,6],[38,43],[8,43]]` and green inner triangle `[[23,13],[32,37],[14,37]]`; write the same bitmap to all eight compatibility filenames.
- [x] Add one `formatDistance(distanceM)` method using integer metres below 1,000 and rounded one-decimal kilometres with `.0` removed at or above 1,000.
- [x] Use the formatter in `handleNavigationUpdate` and staged preview, and always place the marker at `(106,374)` with `marker-0.png`.
- [x] Run `make test-rpk` and confirm resource, UI, preview, refresh, and transfer tests pass.

### Task 3: Six-pixel outward edge destination

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/BandDisplaySafeMask.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/BandDisplaySafeMaskTests.swift`
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderProtocol.swift`
- Modify: `apps/band/src/common/render-protocol.js`
- Modify: `apps/band/src/pages/index/index.ux`

- [x] Add failing tests for all eight directions proving the edge ring moves outward by 6 pixels from the conservative point while its complete 20x20 bounds remain inside the physical curved contour.
- [x] Run `make test-swift` and `make test-rpk`; confirm the current visual-margin point fails the outward-distance assertions.
- [x] Add a minimal `withoutVisualMargin` mask value and compute edge destinations with it; do not alter the production mask constants or marker/visible-pin validation.
- [x] Validate `destinationMode=edge` against the physical zero-margin mask in Swift and Band prepare/live validators; keep `visible` on the normal six-pixel visual margin.
- [x] Run the targeted Swift and RPK suites and confirm preview/live destination tests pass.

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

- [x] Update assertions first for IPA `0.5.3 (19)` and RPK `0.6.2 (17)` and confirm metadata tests fail.
- [x] Apply the exact version/build changes and update the manual hardware test guide with the fixed marker, route-anchor, edge-ring, and distance checks.
- [x] Run `make clean && make bootstrap && make test && make lint && scripts/verify-no-secrets.sh && git diff --check`.
- [ ] Commit directly on `main`, push, wait for GitHub iOS/Band/Swift/repository checks, and download the unsigned IPA from the successful iOS run.
- [ ] Replace `artifacts/handoff` atomically with the new IPA, RPK, handoff guide, and checksums; verify versions, hashes, and that no old artifact remains.
