# Band Overlay Icons Design

## Goal

Fix the three remaining hardware-visible navigation overlay defects without changing route selection, map projection, camera framing, transfer, or protocol behavior:

- render the fixed lower-centre self marker without a missing or indented corner;
- render off-screen destinations as a clean, larger outward chevron at the Band contour;
- give the maneuver header a clearly visible dark panel instead of the imperceptible `nav-shade.png`.

## Confirmed causes

The delivered RPK contains the same marker, destination, and shade bytes as the source tree, so packaging did not substitute the assets.

The marker generator centres odd-width pixel rows on integer pixel `x = 23` in a 46-pixel canvas. Those rows mirror around index sum `46`, while a 46-pixel image must mirror around index sum `45`. The existing test asserts the wrong value and preserves the one-pixel deformation.

The destination edge asset is a layered filled polygon with a bright dot on its outward tip. Once clipped at the display contour, these layers collapse into a small blob rather than a readable chevron.

The shade uses RGB `(4, 12, 20)` over a map background around RGB `(5, 14, 22)`. Its nearly identical colour cannot produce a visible panel boundary even when the PNG renders correctly.

## Design

Keep the existing `<image>` overlay architecture for markers. Generate deterministic true-colour RGBA PNGs with the repository's existing PNG writer pattern; add no dependency.

The self marker is the approved upright navigation pointer: a long, closed triangle with a white outline and green fill. Every RGBA pixel must equal its mirror at `width - 1 - x`. It remains fixed at `left:83px; top:347px`, centred at map coordinate `(106, 374)`, and all eight compatibility filenames remain byte-identical.

Generate eight 34×34 RGBA destination edge icons. Each is a thick amber two-segment chevron with a dark outline, rotated offline in 45-degree increments. There is no filled body and no tip dot. The overlay keeps the current destination direction and contour projection, but centres the larger asset using a 17-pixel offset.

Remove `nav-shade.png` from the page and bundle. Add a native `nav-panel` div behind `nav-header`, inset from the screen edge, with an explicit dark background and rounded corners. Draw the visible shadow with a second offset black div behind the panel. Header content and maneuver icons remain unchanged.

Keep `minAPILevel: 1` and forbid `box-shadow`. RPK `0.6.6 (21)` raised the minimum to API Level 3 and the Band rejected it with AstroBox `InstallFailed`; the two-div panel preserves the visual without that compatibility gate.

## Non-goals

- No changes to iOS, Vietmap requests, route decoding, route geometry, camera selection, or raster snapshot rendering.
- No changes to BLE framing, navigation messages, or map publication lifecycle.
- No runtime SVG, canvas, CSS rotation, or new image dependency.

## Verification

Tests first establish the correct mirror invariant, RGBA asset format, simple chevron topology, native panel structure, absence of the shade asset, and the larger contour-centred edge style. Packaging verification checks the same contracts inside the produced RPK.

Repository verification is `make test`, `make lint`, and `git diff --check`. These prove deterministic code and package behavior only; final visual acceptance still requires the physical Band.

## Version and handoff

Only the Band component changes. The compatible correction is RPK `0.6.7 (22)`; do not ship rejected `0.6.6 (21)`. Do not bump or rebuild the unchanged iOS component. Merge and push the completed work to `main`, replace the old handoff RPK with the new one, and retain the current GitHub-Actions-built IPA.
