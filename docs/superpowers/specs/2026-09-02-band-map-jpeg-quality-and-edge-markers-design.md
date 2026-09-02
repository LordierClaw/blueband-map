# Band Map JPEG Quality And Edge Markers Design

**Date:** 2026-09-02

## Problem

The Vietmap snapshot is already rotated on iOS at 2x scale before it is downsampled and transferred. The Band does not rotate the map. The visible jagged diagonal roads and unreadable road names come from the final 212x520 fixed 16-colour PNG, not from a missing iOS rotation step. A recent hardware log measured an 8,165-byte 16-colour PNG, leaving no room for a richer palette or larger labels under the 8,192-byte protocol limit.

The accepted cursor geometry is correct but blends into the blue route without a white outline. The 24x24 destination chevron is also clamped by the generic 12px safe inset, so its visible stroke remains too far from the physical straight edge.

## Compression decision

A deterministic 424x1040 representative navigation scene was downsampled to 212x520 and visually compared:

| Candidate | Bytes | Result |
| --- | ---: | --- |
| Reference RGB PNG | 44,025 | Sharp, over budget |
| Current fixed 16-colour PNG | 9,333 | Hard diagonal steps, over budget |
| Adaptive 16-colour PNG | 10,485 | Better colour fidelity, over budget |
| Adaptive 32-colour PNG | 11,119 | Better again, over budget |
| JPEG q25, 4:4:4 | 7,267 | Under budget, readable but softer |
| JPEG q30, 4:4:4 | 8,112 | Best tested balance under budget |

PNG filter/Deflate tuning cannot restore colours removed by 4-bit quantisation. Adaptive quantisation improves fidelity but increases entropy and still misses the payload limit. Vela documents both PNG and JPEG support for `<image>`, so JPEG is the selected primary transport format.

The encoder will downsample once with high-quality interpolation, try a descending native ImageIO JPEG quality ladder, and accept only the highest candidate in `1...8192` bytes. If no JPEG candidate fits or ImageIO cannot encode it, the existing indexed PNG encoder runs with bounded 1/2/4/8 pixel-block fallback. The asset MIME and Band file extension follow the actual bytes. This preserves the hard payload guard and avoids both `MAP_PAYLOAD_TOO_LARGE` and format/path mismatch failures.

## Map readability

The source map layers stay intact under the existing full-label profile; the byte-pressure loop must no longer re-render reduced-label or reduced-land-use profiles. Road-label symbol layers receive a 14-point minimum text size and a 1.25-point dark halo before the Vietmap snapshot is produced. Rotation, route overlay, label layout, downsampling, and compression therefore all happen on iOS.

## Overlay changes

- Regenerate the accepted 30x38 dark-green cursor at a cache-busted `marker-cursor-v4.png` path. Preserve the exact polygon, tip/notch axis, fixed lower-centre position, and add only a one-pixel white exterior outline.
- Use a destination-edge mask with zero straight-edge inset and zero visual margin. The curved top and bottom contour still contains the complete 24x24 resource, while a middle-left/right chevron can reach the physical edge.
- Mirror the same destination mask rule in Swift validation and RPK validation so an accepted preview cannot later fail `BAND_DISPLAY_FAILED` because iOS and Band disagree.

## Protocol and release

Raster format becomes an explicit `image/png` or `image/jpeg` value while keeping format version 1 as an additive format capability. The Band stores JPEG as `.jpg` and PNG as `.png`; transfer correlation, SHA-256, atomic publication, dimensions, and the 8,192-byte ceiling are unchanged. The wire change requires an ADR, independent Swift/JavaScript vectors, and hardware acceptance cases.

Both products change: iOS becomes `0.5.8 (24)` and RPK becomes `0.6.10 (25)`. The IPA is built only by GitHub Actions. Final handoff keeps only the current IPA/RPK pair in `artifacts/handoff` and includes a basic Vietnamese manual test.

## Evidence boundary

Automated tests prove codec admission, decode dimensions, protocol agreement, resource geometry, and bundle contents. They do not prove Smart Band rendering. Hardware acceptance must confirm readable rotated road labels, successful JPEG display without `BAND_DISPLAY_FAILED`, the outlined cursor, and the closer destination chevron.
