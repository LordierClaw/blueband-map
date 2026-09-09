# 0018 — Geometry-derived roundabout direction

Status: implemented; physical acceptance pending.

Route v4 supplies sign 6, interval and geometry, but the observed response has no `degrees` and heading=0 is not usable direction evidence. Vietmap's separate navigation SDK consumes `degrees` in MBVisualInstruction; its existence does not establish a Route v4 field. Exit number is not an angle.

Derive a relative direction once when constructing RoutePlan. Inspect at most the last 96 segments of the instruction, recognize a short counter-clockwise arc bounded by rightward entry/exit transitions, and compare the approach before the arc with the outlet after it. Ignore sub-metre duplicate segments. Reject missing outlet, invalid coordinates, sparse/clockwise/irregular geometry and excessive arc length. Geometry confidence takes precedence over showing a directional arrow. The current conservative classifier supports clearly sampled right-hand-traffic circles; it is not a universal road-topology reconstruction.

2026-09-10 boundary correction: the user's frozen fake-GPS route ends its sign-6 interval after a roughly 76 m outlet, not at the circle edge. Treating the following segment as the outlet yields a -4.2° transition and incorrectly returns unknown. Search for the arc/outlet boundary within the bounded instruction tail, with one segment beyond it when available. Compare the approach (~343°) with the actual outlet (~327°): straight. A translated E5-offset fixture preserves the exact sampled shape without committing the raw provider capture. Tests cover end-at-circle, one/two outlet segments inside the interval, and all four circle directions with rotated approaches. Missing-outlet rejection now removes the actual outlet rather than assuming interval end means circle end.

Application v1 preview and live update gain optional `roundaboutDirection`: `straight`, `left`, `right`, `uTurn`, only with `maneuver=roundabout`. Absent fields preserve old bodies and numbered neutral fallback. Invalid strings/types are rejected before path construction. Geometry direction selects the standard pinned Mapbox directional roundabout assets; U-turn reuses the existing Material icon. HUD text and all map/cursor geometry remain unchanged.

Independent application-body vectors (not proprietary-wire captures):

```json
{"maneuver":"roundabout","roundaboutExit":2,"roundaboutDirection":"straight","distanceM":80,"street":"Road","x":106,"y":374,"heading":0,"destinationMode":"hidden","destinationX":0,"destinationY":0}
{"scene":"scene-1","seq":1,"maneuver":"roundabout","roundaboutExit":2,"roundaboutDirection":"left","distanceM":80,"street":"Road","x":106,"y":374,"heading":0,"status":"navigating","destinationMode":"hidden","destinationX":0,"destinationY":0}
```

Tests independently construct radial-exit circles rotated at 0/73/181/350 degrees and reconstruct the Nguyen Khuyen approach/arc/exit shape from rounded headings/lengths. Band tests cover preview/live precedence, all four allowed values, malformed values and unchanged fallback. Xiaomi BLE/SPP/authentication/fragmentation/ACK bytes are unchanged.

Physical acceptance: straight-through, first/right exit, left exit, full return, and ambiguous/small circle; compare the relative exit with the actual approach. Confirm no extra text, legible 44x56 assets, and identical map/route/marker geometry. Install both changed components; an older RPK can ignore the optional field and retain its neutral fallback.

Sources: [Route v4](https://maps.vietmap.vn/docs/vi/map-api/route-version/route-v4/), [VietMapDirections model](https://github.com/vietmap-company/maps-sdk-directions-ios/blob/3e2f1b0547c18bb3ebb2f9b999ba24c433084639/VietMapDirections/MBVisualInstruction.swift), [standard assets](https://github.com/mapbox/directions-icons/tree/9016ba92176cf1a8207cc1c4005b951fe49d59cb).
