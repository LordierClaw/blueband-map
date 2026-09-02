# Band Navigation Visual Refinement Design

## Goal

Preserve the now-correct Vietmap route and map while correcting four hardware-visible presentation issues: the oversized triangular self marker, route alignment at the fixed marker, cropped destination chevrons, and the rectangular guidance background.

## Self marker

Keep the marker as a native Band `<image>` overlay fixed upright at map coordinate `(106, 374)`. Replace the current 46×54 white-bordered triangle with one deterministic 30×38 RGBA asset shared by all eight compatibility filenames.

The opaque silhouette is the union of two opposed isosceles triangles with a common 28-pixel shoulder: a larger forward triangle from the top tip to the shoulder and a smaller reverse triangle from the shoulder to the bottom tip. The shoulder corners form symmetric obtuse angles greater than 90 degrees, so the result reads as a navigation arrow rather than a plain triangle. Use only dark green `#27c76f`; there is no outline, border, rotation, runtime vector drawing, or asymmetric pixel. Every opaque row is contiguous and mirrors exactly around the half-pixel axis `x = 14.5`.

Render the 30×38 asset at `left:91px; top:355px`, preserving its center at `(106, 374)`.

## Route alignment

Do not change route selection, decoded geometry, matched position, overlay splitting, zoom policy, or destination route.

The camera bearing must follow the immediate non-degenerate forward route tangent at the matched position. It must not aim at the farther selected maneuver point: that chord can cross bends and makes the route under the fixed upright marker appear diagonal. GPS course remains eligible only under the existing accuracy, speed, and stability policy; when route bearing is used, all initial, live, and reroute snapshots use the local tangent.

Add a regression case where the next maneuver lies after a bend. The camera bearing must match the first local segment, and the route point immediately ahead must project vertically above the fixed marker.

## Destination edge marker

Replace the 34×34 edge chevrons with 24×24 RGBA chevrons. Keep the existing eight offline directions and open two-stroke shape, but keep every pixel inside the bitmap.

Calculate the transmitted edge center against the production safe mask using the actual 24×24 resource size and its existing 6-pixel visual margin. Do not use the physical-contour `1×1` shortcut. The Band centres the asset using a 12-pixel offset and explicit 24×24 dimensions. This guarantees the complete chevron remains visible instead of placing its centre on the screen contour.

The normal in-viewport destination pin is unchanged.

## Guidance layout

Remove `nav-panel-shadow`, `nav-panel`, and all associated CSS. The map remains the only background.

Keep the existing maneuver, distance, street, and status elements, with these positions:

- maneuver arrow: `left:32px; top:28px; width:44px; height:56px`
- distance: `left:78px; top:26px; width:88px`
- street: `left:72px; top:60px; width:94px`
- status: `left:72px; top:80px; width:94px`

Long street-name handling is explicitly deferred.

## Compatibility, versions, and handoff

Retain `minAPILevel: 1` and forbid `box-shadow`. Both product components change: bump iOS from `0.5.5 (21)` to `0.5.6 (22)` and RPK from `0.6.7 (22)` to `0.6.8 (23)`.

Build the IPA only through GitHub Actions. Build and verify the RPK through the repository `make` workflow. Merge and push to `main`, delete superseded handoff IPA/RPK files, retain only the current pair in `artifacts/handoff`, and update checksums and the Vietnamese manual-test handoff.

## Verification boundary

Add failing behavioral tests before changing production code. Run `make test`, `make lint`, and `git diff --check`. Inspect the packaged RPK manifest and exact PNG dimensions/bytes. Automated tests and CI establish code and package behavior only; a physical Smart Band photo and successful AstroBox install remain required for visual and hardware acceptance.
