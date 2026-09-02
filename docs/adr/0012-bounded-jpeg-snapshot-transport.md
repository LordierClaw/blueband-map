# ADR 0012: Bounded JPEG snapshot transport

**Status:** Accepted
**Date:** 2026-09-02
**Scope:** Live route-card raster payload between iOS and the Band RPK

## Context

The heading-up Vietmap snapshot is already rendered and rotated at 2x on iOS. Reducing the final 212x520 image to a fixed 16-colour indexed PNG creates hard steps on diagonal roads and text, while a representative full-detail scene measured 9,333 bytes against the 8,192-byte transport ceiling. Adaptive 16/32-colour PNGs measured 10,485/11,119 bytes. A visually inspected JPEG quality-30 candidate measured 8,112 bytes and retained smoother readable labels.

## Decision

Format version 1 accepts two raster MIME values: `image/png` and `image/jpeg`. iOS selects the highest tested JPEG quality whose complete bytes are in `1...8192`. If JPEG cannot be encoded within the bound, iOS uses the existing indexed PNG encoder with its bounded spatial fallback. No payload is prepared or transferred before its final size, dimensions, MIME, and SHA-256 are known.

The RPK derives storage extension from MIME: PNG uses `.png`; JPEG uses `.jpg`. Format, MIME, file extension, prepared metadata, asset-begin metadata, SHA-256, and bytes must agree before the file is allocated. Scene ownership, chunk ordering, atomic image completion, and cleanup are unchanged.

This is an additive application-envelope capability. It does not alter Xiaomi BLE/SPP framing, authentication, encryption, application-envelope encoding, chunk bytes, acknowledgements, or the 8,192-byte limit.

## Independent vectors

Both the portable Swift tests and the independent RPK JavaScript tests cover these values:

```json
{"renderer":"raster","format":"image/png","formatVersion":1,"width":212,"height":520,"bytes":128,"primitives":0}
```

Expected: accepted; asset path ends in `.png`.

```json
{"renderer":"raster","format":"image/jpeg","formatVersion":1,"width":212,"height":520,"bytes":128,"primitives":0}
```

Expected: accepted; `mime` must also be `image/jpeg`; asset path ends in `.jpg`.

```json
{"renderer":"raster","format":"image/webp","formatVersion":1,"width":212,"height":520,"bytes":128,"primitives":0}
```

Expected: rejected before allocation as an unsupported format.

Any accepted vector with `bytes` outside `1...8192`, dimensions other than 212x520, a stale run/scene, a MIME/format mismatch, or a bad SHA-256 remains rejected.

## Hardware acceptance

Automated tests and CI do not prove Smart Band support. On Xiaomi Smart Band 10, acceptance requires:

1. Install RPK 0.6.10 (25) and pair it with iOS 0.5.8 (24).
2. Start a heading-up route whose roads and labels become diagonal.
3. Confirm the JPEG-backed map reaches `render.result status=ok`, displays completely, and produces neither `MAP_PAYLOAD_TOO_LARGE` nor `BAND_DISPLAY_FAILED`.
4. Confirm road names are more legible than RPK 0.6.9 while route geometry and atomic refresh remain correct.
5. Force several refreshes and reconnect once; confirm no stale `.png`/`.jpg` scene is promoted.

If the current firmware fails to decode JPEG, the failure must remain explicit as `BAND_DISPLAY_FAILED`; iOS must not claim hardware support from compilation or simulator evidence. The indexed PNG fallback protects encoder admission, but JPEG firmware compatibility is an acceptance result, not an assumption.
