# Google Material Icons Round

Source: https://github.com/google/material-design-icons/tree/0cbb08816df07faaae3dca060d4ebb10b66c214f/src/maps

The six SVGs are unmodified upstream `materialiconsround/24px.svg` files. The Apache-2.0 license ships in `src/common/material-icons-LICENSE.txt` and inside the RPK.

BlueBandMap modifications: tint cyan (#00e5ff), scale to 44x44, centre inside a transparent 44x56 RGBA PNG. Geometry is not redrawn. Mapping: straight, turn_left, turn_right, u_turn_left, roundabout_right (generic roundabout instruction, not an exit number), place (arrival).

Normal builds use the checked-in PNGs; no new runtime or build dependency. For offline artwork regeneration, run `node scripts/generate-maneuvers.cjs` with `@napi-rs/canvas@0.1.100` available to Node. The desktop's bundled graphics runtime supplies it for this release.
