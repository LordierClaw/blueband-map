# Band Navigation Raster Quality Design

**Date:** 2026-09-02  
**Status:** Approved  
**Scope:** iOS snapshot generation and preview, Smart Band 10 navigation overlays, release artifacts

## Problem

Hardware and iPhone preview evidence shows four independent defects:

1. A heading-up map is rendered at final resolution and the iPhone preview explicitly uses nearest-neighbour interpolation, so diagonal roads, labels, and route strokes become visibly jagged.
2. The Band still displays the obsolete bright, white-bordered triangular marker even though RPK 0.6.8 contains different marker bytes. The stable `/common/marker-0.png` resource path is the remaining cache key shared with the obsolete asset.
3. The off-screen destination chevron is fully safe but visually too far from the curved screen edge because it uses the general 6 px visual margin.
4. The street label ends at x=166 although the safe upper-right area extends farther, causing avoidable truncation.

The change must not reintroduce `MAP_PAYLOAD_TOO_LARGE`, `BAND_DISPLAY_FAILED`, route/marker misalignment, or clipped overlay resources.

## Decisions

### 1. Supersample before quantization

Keep heading rotation inside `MGLMapSnapshotter` through `MGLMapCamera.heading`. Set the snapshot output scale to 2 so Vietmap renders roads, labels, and route overlays at 424×1040 pixels for the same 212×520-point viewport. Do not rotate a completed bitmap.

`SnapshotPNGEncoder` will accept the 2× source and draw it once into a 212×520 RGBA buffer with high-quality interpolation before palette quantization. The transport image remains an indexed 212×520 PNG.

The iPhone debug preview will use high-quality SwiftUI interpolation rather than nearest-neighbour interpolation.

### 2. Preserve bounded payload admission

Do not change `RenderProtocol.maximumPayloadBytes` (8192), viewport dimensions, format version, renderer, or Band decoder.

The existing admission ladder remains authoritative:

1. 16-colour snapshot with labels, no spatial blocking.
2. 16-colour snapshot without low-priority labels.
3. 16-colour snapshot without low-priority land use.
4. The same rejected profiles with bounded 2×2, 4×4, then 8×8 spatial fallback.

Every candidate is encoded and measured before `RenderAsset` or `render.prepare` is created. Only a payload in `1...8192` may be sent. The 8×8 fallback remains covered by a high-entropy regression test and the decoded PNG must still be 212×520 indexed colour.

### 3. Replace the self marker and its cache key

Generate one new RGBA asset at `/common/marker-cursor-v3.png` and remove use of the `marker-0.png` compatibility path.

The silhouette is the approved classic cursor geometry rotated as one rigid shape by 36 degrees. Its sharp tip-to-notch axis is placed at the horizontal centre of the 30×38 canvas, so the tip lies exactly on the route centreline while the navigation anchor remains fixed at `(106, 374)`. Use solid dark green `#14804a`, coverage alpha only for anti-aliasing, and no border or white pixels.

The new resource name intentionally invalidates any path-keyed Band image cache.

### 4. Move only the edge destination closer

Keep the existing 24×24 directional chevron and physical curved-screen mask. Use a destination-edge visual margin of 2 px instead of the general 6 px margin. The complete icon must still remain inside the physical safe mask. Visible destination pins and the self marker retain their existing safety margins.

iOS construction, Swift protocol validation, Band protocol validation, staged preview validation, and overlay placement must all use the same 2 px edge-destination rule.

### 5. Expand the HUD without adding a risky surface

Keep the HUD transparent. Expand the one-line street label from `left:72px; width:94px` to `left:72px; width:126px`, ending at x=198. Keep its current vertical placement and right alignment.

Do not add a gradient in this release. AIoT Toolkit 2 supports gradient syntax, but this application targets platform version 1000 and there is no Smart Band 10 hardware evidence for this property. A cosmetic gradient does not justify adding a new runtime failure variable.

## Versioning and artifacts

The iOS snapshot path changes, so bump iOS from 0.5.6 (22) to 0.5.7 (23). The Band bundle changes, so bump RPK from 0.6.8 (23) to 0.6.9 (24).

Build the RPK with the repository's Docker/Make workflow. Build the IPA only through GitHub Actions. After both artifacts are verified, replace the old IPA/RPK files in `artifacts/handoff` and retain only the current handoff set.

## Verification

- Red/green tests for 2× Vietmap scale and 2× source normalization.
- Decoded PNG is 212×520, indexed colour, and no larger than 8192 bytes.
- High-entropy 8×8 fallback still fits within 8192 bytes.
- iPhone preview no longer requests nearest-neighbour interpolation.
- Marker test proves the new path, 30×38 RGBA format, dark-green-only RGB, no white border, cursor notch, and centre-aligned tip/notch axis.
- Edge destination tests prove the complete 24×24 resource stays inside the physical mask with exactly 2 px visual margin.
- Bundle test proves the wider street label and absence of gradient/panel additions.
- `make test`, `make lint`, `git diff --check`, RPK build verification, artifact verification, and GitHub Actions IPA build must pass.

Hardware acceptance remains a manual handoff gate: compilation and deterministic tests do not prove Smart Band display behaviour.
