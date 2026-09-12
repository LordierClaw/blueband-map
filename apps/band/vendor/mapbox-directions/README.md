# Roundabout icon

Unmodified `src/svg/roundabout.svg` from https://github.com/mapbox/directions-icons/tree/9016ba92176cf1a8207cc1c4005b951fe49d59cb (CC0-1.0). License ships in `src/common/mapbox-directions-LICENSE.txt`.

Offline generation uses the existing maneuver script: cyan neutral circulation symbol, optionally a white exit number 1–12 from the provider, in the same 44×56 transparent PNG. There is no right-exit arrow and no assumption that exit 2 means straight. Unknown exits use the unnumbered symbol. Other maneuver icons remain Google Material Icons Round.

Directional `roundabout_straight.svg`, `roundabout_left.svg`, and `roundabout_right.svg` are unmodified files from the same pinned CC0 source. They are rasterized cyan into the existing 44x56 footprint and selected only for a geometry-derived relative direction; no exit number is overlaid. Full return uses the existing Material U-turn icon. Neutral numbered artwork remains the fallback when geometry is insufficient.

Directional rasterization uses an 88x88 source and a rounded 0.7-unit cyan outline
before downsampling to 44x44. This preserves the upstream path while matching the
Material arrows' roughly four-pixel stem and avoiding enlargement of a 20px bitmap.
