# Band Map JPEG Quality And Edge Markers Implementation Plan

**Goal:** Preserve the detailed rotated map while improving diagonal/text quality under 8 KiB, and finish the two approved marker refinements without regressing Band publication.

**Architecture:** iOS keeps rendering Vietmap at 2x, enlarges road labels, downsamples once, then selects the highest native JPEG quality that fits 8,192 bytes. The existing indexed PNG encoder is the bounded fallback. Core and RPK carry the actual MIME/extension; the existing atomic scene publication stays unchanged.

## Task 1: Lock the image and protocol behavior with failing tests

- Add iOS tests for a representative diagonal/text scene: JPEG is selected, decodes to 212x520, fits 8,192 bytes, and remains above a bounded image-error threshold.
- Add a forced fallback test proving indexed PNG still fits and decodes at 212x520.
- Add core and RPK vectors accepting both `image/png` and `image/jpeg`, rejecting other MIME values, and using `.jpg` for JPEG storage.
- Run the focused tests and record the expected failures before implementation.

## Task 2: Implement the smallest bounded raster encoder

- Add a native ImageIO JPEG wrapper around the existing high-quality downsample.
- Try a fixed descending quality ladder and return the first candidate within 8,192 bytes.
- Fall back to the existing 16-colour indexed PNG with block sizes 1/2/4/8.
- Render only the full-label/full-land-use profile in `AppModel`, pass the real MIME to `RenderAsset`, and log format, quality, bytes, and fallback metadata.

## Task 3: Carry JPEG through core and Band atomically

- Extend `RenderFormat` and `RenderAsset` to represent PNG/JPEG without changing dimensions, hashes, chunks, or payload limits.
- Let both Swift and JavaScript prepare validators accept only these two formats.
- Derive the internal file extension from MIME in the RPK and keep all current scene/token/map-complete checks.
- Add an ADR with exact Swift/JavaScript vectors and hardware acceptance cases.

## Task 4: Improve labels at the source

- Add a pure road-label style policy with 14-point text and 1.25-point halo constants and tests.
- Apply it only to retained road-label symbol layers before snapshotting.
- Keep all layers selected by the current full-label profile; do not add another simplification profile.

## Task 5: Refine marker resources and edge geometry

- Change the resource contract test first: require `marker-cursor-v4.png`, the approved green polygon, a one-pixel white exterior outline, unchanged tip/notch axis, and no v3 reference.
- Generate v4 and update page/verifier references without changing the fixed 30x38 lower-centre layout.
- Add a destination-edge mask test proving a horizontal 24x24 chevron centre reaches x=12 or x=200 while curved corners remain contained.
- Implement the zero-inset/zero-margin edge mask in Swift and mirror it in RPK validation.
- Generate and visually inspect an enlarged cursor plus representative compression outputs.

## Task 6: Version, verify, and hand off

- Bump iOS to `0.5.8 (24)` and RPK to `0.6.10 (25)` with matching metadata/verifier tests.
- Run focused tests, `make test`, `make lint`, `scripts/verify-no-secrets.sh`, `git diff --check`, and the verified RPK build.
- Commit and push `main`; trigger/wait for the GitHub Actions IPA for the exact commit and verify the downloaded artifact.
- Remove only old IPA/RPK files from `artifacts/handoff`, copy the verified current pair, regenerate checksum/handoff metadata, and confirm no stale package remains.
- Hand over a concise Vietnamese change list and manual test that explicitly checks JPEG display, rotated label readability, payload/Band errors, cursor outline, and destination-edge placement.
