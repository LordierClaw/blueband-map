# Band Navigation Raster Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a sharper heading-up navigation snapshot and corrected Smart Band overlays without ever sending more than 8192 bytes or changing the proven 212×520 indexed-PNG display contract.

**Architecture:** Vietmap renders the existing logical viewport at 2× output scale and `SnapshotPNGEncoder` performs the only downsample before the existing 16-colour admission ladder. Band changes are limited to one cache-busted cursor resource, a destination-specific 2 px margin, and a wider transparent HUD label.

**Tech Stack:** Swift 6, CoreGraphics/ImageIO, VietMap/Mapbox snapshot SDK, SwiftUI, Xiaomi Vela JS/UX, Node 20 tests, Docker/Make, GitHub Actions

---

### Task 1: Supersampled heading-up snapshot and preview

**Files:**
- Modify: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`
- Modify: `apps/ios/Tests/SnapshotPNGEncoderTests.swift`
- Modify: `tools/ios/test-project-metadata.sh`
- Modify: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Modify: `apps/ios/Adapters/Rendering/SnapshotPNGEncoder.swift`
- Modify: `apps/ios/App/ContentView.swift`

- [ ] **Step 1: Write failing contracts and XCTest expectations**

Change the renderer expectation to `2`, add a 424×1040 source test that decodes to 212×520, and add source-contract assertions:

```swift
func testDownsamplesTwoXSnapshotToTransportDimensionsWithinBudget() throws {
    let output = try SnapshotPNGEncoder.encode(
        solidImage(width: 424, height: 1040),
        profiles: [.colors16Labels]
    )
    let source = try XCTUnwrap(CGImageSourceCreateWithData(output.data as CFData, nil))
    let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(decoded.width, 212)
    XCTAssertEqual(decoded.height, 520)
    XCTAssertLessThanOrEqual(output.data.count, RenderProtocol.maximumPayloadBytes)
}
```

```bash
grep -Fq 'let scale: CGFloat = 2' apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift
grep -Fq '.interpolation(.high)' apps/ios/App/ContentView.swift
! grep -Fq '.interpolation(.none)' apps/ios/App/ContentView.swift
```

- [ ] **Step 2: Run the local contract to verify RED**

Run: `make test-ios-metadata`  
Expected: FAIL because the renderer scale is 1 and the preview uses `.interpolation(.none)`.

- [ ] **Step 3: Implement the minimal 2× render and one high-quality normalization**

Set the logical configuration scale to 2. Accept only 1× or 2× sources in the encoder, always allocate the transport-size RGBA buffer, draw with `.high`, and use transport dimensions for blocking and PNG encoding:

```swift
let scale: CGFloat = 2
```

```swift
let width = RenderProtocol.viewportWidth
let height = RenderProtocol.viewportHeight
guard image.width == width || image.width == width * 2,
      image.height == height * (image.width / width) else { throw Error.unsupportedImage }
let pixels = try rgbaPixels(image, width: width, height: height)
```

```swift
context.interpolationQuality = .high
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
```

Change the SwiftUI preview to `.interpolation(.high)`. Do not change camera heading, zoom, viewport dimensions, palette order, protocol format, or the 8192-byte cap.

- [ ] **Step 4: Run focused verification GREEN**

Run: `make test-ios-metadata && make test-swift`  
Expected: PASS. The macOS/iOS XCTest is executed by the repository GitHub workflow later in Task 5.

- [ ] **Step 5: Commit**

```bash
git add apps/ios tools/ios/test-project-metadata.sh
git commit -m "fix: supersample navigation snapshots"
```

### Task 2: Cache-busted approved cursor and wider transparent HUD

**Files:**
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`
- Modify: `apps/band/scripts/generate-icon.mjs`
- Modify: `apps/band/scripts/verify-rpk.mjs`
- Modify: `apps/band/src/pages/index/index.ux`
- Delete: `apps/band/src/common/marker-0.png` through `marker-7.png`
- Create (generated): `apps/band/src/common/marker-cursor-v3.png`

- [ ] **Step 1: Write failing marker and layout tests**

Require `/common/marker-cursor-v3.png`, reject every `marker-N.png` reference, require street width 126, and inspect the RGBA marker:

```javascript
assert.match(page, /navMarkerPath:\s*["']\/common\/marker-cursor-v3\.png["']/)
assert.doesNotMatch(page, /\/common\/marker-[0-7]\.png/)
assert.match(page, /\.nav-street\s*\{[^}]*left:\s*72px;[^}]*top:\s*60px;[^}]*width:\s*126px;/s)
```

For every nontransparent marker pixel require RGB `[20,128,74]`; require a nontransparent tip near `(15,2)`, a transparent notch-side sample at `(15,29)`, no white RGB, and opaque bounds contained inside the 30×38 canvas.

- [ ] **Step 2: Run Band tests to verify RED**

Run: `make test-rpk`  
Expected: FAIL because the new cursor resource/path and 126 px label do not exist.

- [ ] **Step 3: Generate the approved cursor with coverage alpha**

Replace the opposed-triangle generator with one antialiased polygon on a 30×38 canvas:

```javascript
const cursorPoints = [[15.18, 2], [28, 30.97], [15.03, 26.12], [2, 30.78]]
const marker = new Uint8Array(30 * 38 * 4)
paintAntialiasedPolygonRGBA(marker, 30, 38, cursorPoints, [20, 128, 74, 255])
await writeFile(new URL("../src/common/marker-cursor-v3.png", import.meta.url), rgbaPNG(30, 38, marker))
```

The coverage helper samples a fixed 4×4 grid per output pixel and varies alpha only; all nontransparent RGB remains `#14804a`. Delete the obsolete generated marker files from source and required-resource lists.

- [ ] **Step 4: Switch every initial, staged, restored, and published marker path**

Replace all Band page assignments of `/common/marker-0.png` with `/common/marker-cursor-v3.png`. Keep `left:91px; top:355px`, canvas 30×38, and iOS anchor `(106,374)` unchanged. Change only `.nav-street` width from 94 px to 126 px. Do not add background, gradient, panel, transform, or shadow.

- [ ] **Step 5: Run Band tests and build GREEN**

Run: `make test-rpk`  
Expected: all Node tests pass and the verified RPK build contains `common/marker-cursor-v3.png` but no referenced obsolete marker path.

- [ ] **Step 6: Commit**

```bash
git add apps/band
git commit -m "fix: replace cached navigation cursor"
```

### Task 3: Destination edge at a consistent 2 px visual margin

**Files:**
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/BandDisplaySafeMaskTests.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/RenderProtocolTests.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/NavigationUpdateTests.swift`
- Modify: `apps/band/test/render-protocol.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/BandDisplaySafeMask.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderProtocol.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/NavigationUpdate.swift`
- Modify: `apps/band/src/common/render-protocol.js`
- Modify: `apps/band/src/pages/index/index.ux`

- [ ] **Step 1: Write failing 2 px edge-margin tests**

For a far-left target, require the destination centre generated with the 2 px mask to be closer to the edge than the 6 px result, require all four 24×24 corners plus 2 px margin inside the physical mask, and require at least one corner plus any additional margin to fall outside:

```swift
let edgeMask = BandDisplaySafeMask.smartBand10PhotoEstimate.withVisualMargin(2)
let point = edgeMask.destinationEdgePoint(
    from: ScreenPoint(x: 106, y: 374),
    toward: ScreenPoint(x: -500, y: 374)
)
XCTAssertTrue(edgeMask.contains(center: point, resourceWidth: 24, resourceHeight: 24))
XCTAssertFalse(BandDisplaySafeMask.smartBand10PhotoEstimate.contains(
    center: point, resourceWidth: 24, resourceHeight: 24
))
```

Update Swift and JS protocol fixtures so an edge point valid at margin 2 is accepted while the same coordinates in visible-pin mode remain rejected.

- [ ] **Step 2: Run Swift and Band tests to verify RED**

Run: `make test-swift && make test-rpk`  
Expected: FAIL because `withVisualMargin` and destination-specific validation do not exist.

- [ ] **Step 3: Implement one mask-copy helper and destination-specific validation**

Add:

```swift
public func withVisualMargin(_ margin: Double) -> Self {
    Self(width: width, height: height, inset: inset, topCenterY: topCenterY,
         bottomCenterY: bottomCenterY, topRadius: topRadius,
         bottomRadius: bottomRadius, visualMargin: margin)
}
```

Use `mask.withVisualMargin(2)` only for `.edge` placement and validation. Keep margin 6 for self marker and `.visible` pin. Mirror the exact rule in both Band validators:

```javascript
const margin = preview.destinationMode === "edge" ? 2 : 6
safeCenter(preview.destinationX, preview.destinationY, width, height, margin)
```

- [ ] **Step 4: Run focused tests GREEN**

Run: `make test-swift && make test-rpk`  
Expected: PASS with matching Swift and Band destination validation.

- [ ] **Step 5: Commit**

```bash
git add packages/BlueBandKit apps/band
git commit -m "fix: move destination chevron toward edge"
```

### Task 4: Version both changed components

**Files:**
- Modify: `apps/ios/project.yml`
- Modify: `apps/ios/Tests/InfoPlistMetadataTests.swift`
- Modify: `apps/band/package.json`
- Modify: `apps/band/package-lock.json`
- Modify: `apps/band/src/manifest.json`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/scripts/verify-rpk.mjs`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Write failing metadata expectations**

Require iOS 0.5.7 build 23 and RPK 0.6.9 code 24 in their existing metadata tests and verifiers.

- [ ] **Step 2: Run metadata tests to verify RED**

Run: `make test-ios-metadata && make test-rpk`  
Expected: FAIL against the old iOS 0.5.6 (22) and RPK 0.6.8 (23) metadata.

- [ ] **Step 3: Update version sources and changelog**

Change all iOS marketing/build values to 0.5.7/23 and all Band package/manifest/UI/verifier values to 0.6.9/24. Add concise changelog entries for supersampling, the cache-busted cursor, destination offset, HUD width, and unchanged 8192-byte display contract.

- [ ] **Step 4: Run metadata tests GREEN**

Run: `make test-ios-metadata && make test-rpk`  
Expected: PASS and a verified `.0.6.9.rpk` output.

- [ ] **Step 5: Commit**

```bash
git add apps/ios apps/band CHANGELOG.md
git commit -m "chore: bump navigation quality builds"
```

### Task 5: Full verification, GitHub IPA, artifacts, and main handoff

**Files:**
- Replace: `artifacts/handoff/*.ipa`
- Replace: `artifacts/handoff/*.rpk`
- Modify: `artifacts/handoff/release-manifest.json` or repository-equivalent handoff metadata

- [ ] **Step 1: Run canonical local verification**

Run:

```bash
make clean
make bootstrap
make test
make lint
scripts/verify-no-secrets.sh
git diff --check
```

Expected: every command exits 0. Confirm generated map transport tests still cap payload at 8192 and RPK verification reports version 0.6.9.

- [ ] **Step 2: Build and verify the RPK**

Run the repository Band build through Docker/Make, locate the single 0.6.9 RPK, and run `apps/band/scripts/verify-rpk.mjs` through the package build. Inspect the archive to confirm `marker-cursor-v3.png`, 212×520 map contract code, and no missing required resource.

- [ ] **Step 3: Push `main` and obtain the IPA only from GitHub Actions**

Push the verified commits to `origin/main`. Trigger or observe the repository's IPA workflow for that exact commit, wait for success, download the 0.5.7 (23) IPA artifact, and run `scripts/verify-ios-artifact.sh` against it. Do not use a locally built IPA.

- [ ] **Step 4: Replace stale handoff artifacts safely**

Remove only the explicitly enumerated old `.ipa` and `.rpk` files under `artifacts/handoff`, copy in the verified 0.5.7 IPA and 0.6.9 RPK, regenerate the release manifest for the exact main commit, and confirm the directory retains only the current IPA/RPK pair plus required metadata.

- [ ] **Step 5: Commit and push handoff artifacts**

```bash
git add artifacts/handoff
git commit -m "release: hand off navigation quality builds"
git push origin main
```

- [ ] **Step 6: Re-run final evidence checks**

Run: `make test && make lint && git diff --check && git status --short --branch`  
Expected: tests/lint exit 0, no diff errors, clean `main` synchronized with `origin/main`. Verify handoff hashes and versions one final time.

- [ ] **Step 7: Prepare the manual acceptance guide**

The handoff must tell the user to install IPA 0.5.7 (23) and RPK 0.6.9 (24), start a route with a diagonal initial bearing and a far destination, then verify:

1. No `MAP_PAYLOAD_TOO_LARGE` or `BAND_DISPLAY_FAILED` status.
2. Full route and labels remain readable after heading rotation.
3. Dark-green cursor has no white border, keeps its tip exactly on the route centreline, and stays fixed at `(106,374)`.
4. Destination chevron is closer to but never clipped by the curved edge.
5. Guidance street text reaches near the right edge with no panel/gradient background.

Record that hardware acceptance is still pending until these checks pass on the user's Smart Band 10.
