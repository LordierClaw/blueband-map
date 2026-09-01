# Atomic First Map Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the first raster with its user and destination overlays atomically, enforce heading-up projection, reconnect the waiting page automatically, and ship the approved component versions without runtime calibration UI.

**Architecture:** Extend the existing optional `render.prepare.preview` rather than adding a topic. Compute all initial overlay coordinates from the exact accepted snapshot configuration, stage them on the Band, and promote raster plus overlays together in `mapComplete`; keep later `nav.update` behavior unchanged. Reuse the current safe-mask constants and one interconnect instance.

**Tech Stack:** Swift 6 portable package tests, XCTest iOS adapter tests, Vela UX JavaScript, Node test runner, Make/Docker.

---

### Task 1: Complete atomic preview contract

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderProtocol.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/RenderProtocolTests.swift`
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `apps/ios/Tests/RouteCardRenderCoordinatorTests.swift`
- Modify: `apps/band/src/common/render-protocol.js`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/render-protocol.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`

- [x] Add failing Swift and RPK tests for complete marker/destination fields, bounded values, and partial-preview rejection.
- [x] Run `make test-swift` and `make test-rpk`; confirm failures are caused by the missing fields and atomic staging.
- [x] Extend `RenderNavigationPreview` with `x`, `y`, `heading`, `destinationMode`, `destinationX`, and `destinationY`; serialize those exact existing `nav.update` field names.
- [x] Compute the preview from the selected snapshot's authoritative `VietmapSnapshotConfiguration` before `render.prepare`.
- [x] Stage the validated preview on the RPK and promote marker/destination state synchronously in `mapComplete` without hiding the confirmed scene during refresh.
- [x] Run `make test-swift` and `make test-rpk`; confirm the new tests and existing stale-scene/transfer tests pass.

### Task 2: Enforce stationary heading-up

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/GuidancePresentation.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/GuidancePresentationTests.swift`
- Modify: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Modify: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`
- Modify: `apps/ios/App/AppModel.swift`

- [x] Add failing tests for selected-maneuver forward-point choice, degenerate fallback, cardinal bearings, and the supplied stationary route shape.
- [x] Run the targeted Swift tests and confirm camera sign/reversal assertions fail.
- [x] Reuse `GuidancePresentationPolicy` to choose the non-degenerate forward point and bearing; keep course activation, hysteresis, matching, and reroute policy untouched.
- [x] Validate in `VietmapSnapshotConfiguration.make` that the safe user and forward points satisfy `forward.y < user.y`.
- [x] Run `make test-swift` and confirm all portable and adapter tests pass.

### Task 3: Automatic waiting lifecycle and fixed mask cleanup

**Files:**
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`
- Modify: `apps/band/scripts/generate-icon.mjs`
- Modify: `apps/band/scripts/verify-rpk.mjs`
- Delete: `apps/band/src/common/safe-area-calibration.png`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/BandDisplaySafeMask.swift`
- Modify: `docs/testing/handoffs/hybrid-heading-up-guidance.md`
- Modify: `docs/development/troubleshooting.md`

- [x] Add failing lifecycle tests for immediate probing, one in-flight probe, one two-second timer, reconnect stop/restart, and `onDestroy` cleanup.
- [x] Remove the connection button and calibration UI/resource assertions; assert the static Vietnamese waiting view and accepted fixed constants.
- [x] Run `make test-rpk`; confirm the expected failures.
- [x] Implement the minimal timer/probe state using the existing interconnect instance and epoch ownership checks; do not log failed probes.
- [x] Remove calibration generation, packaged resource, state, handlers, CSS, and normal handoff instructions while preserving safe-mask tests/constants.
- [x] Run `make test-rpk` and confirm lifecycle/build/resource tests pass.

### Task 4: Versions, handoff, and repository verification

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

- [x] Add/update version assertions for IPA `0.5.2 (18)` and RPK `0.6.1 (16)`.
- [x] Apply the exact metadata and visible-label bumps; do not build an IPA locally.
- [x] Run `make clean && make bootstrap && make test && make lint && scripts/verify-no-secrets.sh` and `git diff --check`.
- [x] Inspect `git status`, generated artifacts, and the full diff; keep exactly one built RPK and no local IPA, and state that hardware acceptance remains pending.
