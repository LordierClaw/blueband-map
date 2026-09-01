# Hybrid Heading-Up Guidance Design

**Date:** 2026-09-01

**Status:** Approved in conversation; awaiting written-spec review

## Goal

Make Band guidance behave more like a familiar navigation map without changing Vietmap Route v4, Xiaomi transport bytes, route progress monotonicity, or reroute policy. The visible route must begin at the road-snapped user marker, the HUD must show the nearest useful maneuver, and the snapshot must face the route while stationary and the direction of travel once movement becomes reliable.

This release targets motorcycle navigation from 0 through 50 km/h. It remains a discrete snapshot experience rather than continuously animated phone-map navigation.

## Evidence and current failure

The hardware log reported a 10 m horizontal accuracy while the Band displayed a 2 m straight instruction. The current route overlay splits traveled and upcoming geometry at `progressIndex`, while the native marker uses the fractional `matchedPosition`. When the match lies between two route vertices, the bright upcoming route can begin at the next vertex and leave a dark visual gap between the marker and route. This appears as a GPS/route mismatch even though the marker was snapped to a route segment.

The same log started with `course = -1` and `speed = -1`, which is expected while stationary indoors. A navigation camera must not use that course. Google and Apple navigation patterns instead use a following camera, road-snapped position, and heading-up orientation when reliable heading exists.

## Non-goals

- Do not add the Vietmap Navigation SDK, Google Navigation SDK, or another dependency.
- Do not change the Route v4 endpoint, `vehicle=motorcycle`, response parsing, alternative selection, or encoded polyline format.
- Do not change the three-good-fix off-route rule, 40 m off-route threshold, 15-second reroute cooldown, or monotonic route progress.
- Do not rotate the 212×520 raster continuously on the Band.
- Do not refresh the full map for every GPS fix.
- Do not remove ordinary road hierarchy, buildings, land use, or familiar map context.

## Architecture

The existing `RouteProgressTracker` remains authoritative for route matching, progress, and reroute decisions. Two presentation-only policies sit after it:

1. `GuidancePresentationPolicy` selects the useful maneuver, distance, street, and exact route-overlay split.
2. `GuidanceBearingPolicy` selects a stable snapshot bearing and decides when a bearing change warrants a full refresh.

`AppModel` supplies GPS accuracy, speed, course, route progress, and the previous confirmed snapshot context. `VietmapSnapshotRenderer` receives an exact matched segment/fraction, selected maneuver, and chosen bearing. The RPK continues to receive one raster snapshot plus bounded `nav.update` marker/HUD messages.

No new service, background process, or protocol topic is introduced.

## Road-snapped marker and continuous route

`RouteProgress` gains presentation metadata for the accepted match:

- `matchedSegmentIndex`;
- `matchedFraction` in `0...1`;
- existing `matchedLocation` and `distanceFromRouteMeters` remain unchanged.

These fields describe the already selected segment; they do not alter how the tracker searches or advances.

The renderer splits the route exactly at `matchedLocation`:

- traveled geometry ends at `matchedLocation`;
- the active bright geometry begins at the same `matchedLocation`;
- no segment may be omitted between the marker and bright route;
- the native marker uses that same coordinate and the same snapshot configuration.

When GPS quality is accepted and the match is within the current on-route threshold, the visible marker is road-snapped. When the tracker reports an off-route match, the marker may show the raw accepted GPS coordinate while status becomes `rerouting`; the implementation must not pretend the user remains on the route.

## Useful maneuver selection

Route progress remains unchanged. Guidance presentation may skip only a completed or GPS-indistinguishable instruction.

For each accepted fix, calculate a presentation radius:

```text
passRadiusM = max(8, min(20, horizontalAccuracyM))
```

Start with the first instruction whose interval contains or follows the accepted progress segment. If its remaining along-route distance is no greater than `passRadiusM`, and another instruction exists, display the next instruction instead. Repeat only across zero-length or already-passed instructions; never skip an instruction whose remaining distance exceeds the radius.

This converts misleading output such as “straight 2 m” with 10 m GPS accuracy into the next actionable maneuver, while leaving route progress and reroute state untouched.

The HUD shows:

- maneuver arrow for the selected instruction;
- along-route distance from `matchedLocation` to its maneuver point;
- selected instruction street name;
- exceptional status only for GPS low, rerouting, limited map, or arrival.

## Route emphasis

The familiar dark map remains visible. Route styling becomes three presentation levels:

1. traveled route: subdued blue-gray;
2. active leg from `matchedLocation` through the selected maneuver: flat dark blue with no border;
3. short post-turn continuation: muted blue for enough context to understand the intersection.

The post-turn continuation ends after the first route segment or 80 m beyond the maneuver, whichever provides more intersection context without highlighting the entire remaining route. Remaining route geometry outside that continuation stays subdued rather than disappearing completely.

The selected maneuver point keeps a small ring only when it improves turn recognition. The user marker remains the strongest map element.

## Hybrid heading-up camera

### Stationary and unreliable motion

When speed is invalid or below 1 m/s, derive bearing from the accepted route segment toward the next non-degenerate route point. If that segment has zero length, use the selected instruction heading. This makes the route face the top of the Band even indoors or before movement begins.

### Reliable movement

A movement course becomes eligible after two consecutive accepted GPS fixes satisfy all conditions:

- horizontal accuracy is at most 25 m;
- speed is at least 1 m/s;
- course is finite and within `0...360`.

Once eligible, use course as the preferred bearing. A single invalid or slow fix does not immediately return the camera to route bearing. Return to route-derived bearing only after three consecutive ineligible fixes, preventing stop-and-go camera oscillation.

### Refresh hysteresis

A bearing-driven refresh is requested only when:

- the preferred bearing differs from the confirmed snapshot bearing by at least 30 degrees; and
- at least 12 seconds have elapsed since the previous ordinary refresh started.

Angular difference uses the shortest circular distance. Successful reroute continues to bypass the ordinary interval. Existing coalescing remains authoritative: one refresh can run, and only the newest pending request survives.

Initial rendering uses route-derived bearing, so navigation does not require an extra transfer merely to become heading-up. A later GPS-course refresh is discrete and may lag behind the phone because the Band receives a raster, not a live map camera.

## Safe-area RPK layout

All values refer to the 212×520 Band canvas.

### HUD

- Keep the full-width fade, but put readable content within horizontal coordinates 38...174.
- Maneuver arrow display size becomes 44×56 at approximately `left: 38`, `top: 20`.
- Distance begins near `left: 86`, uses width 88, and moves down from the curved top edge.
- Street and exceptional status use the same right boundary of 174.
- Distance remains primary; street remains one line; status remains visually subordinate.

Exact offsets may move by at most 2 px during hardware visual tuning, but content must not move closer to either curved edge than the values above.

### User marker

- Increase marker resource size from 38×44 to 46×54.
- Preserve transparent margins, a dark outline, and bright green fill.
- Keep eight heading buckets.
- Clamp marker center to `x: 38...174` and `y: 148...464` so the larger resource remains away from the curved edge and HUD.
- The marker heading continues to update through `nav.update` without requiring a snapshot refresh.

## Diagnostics

Sanitized navigation debug entries add, for accepted fixes:

- GPS age, horizontal accuracy, speed, and course;
- distance from route, matched segment index, and fraction;
- selected instruction index and remaining distance;
- bearing source (`route` or `course`), confirmed bearing delta, and refresh reason.

Exact coordinates, API keys, device identifiers, and raw captures remain excluded. Debug export must retain the latest events before the instruction list and must not truncate an event mid-line.

## Failure handling

- Poor GPS continues to publish `gpsLow` and does not advance route progress.
- Invalid course falls back to route-derived bearing; it does not fail navigation.
- A failed heading refresh keeps the last confirmed map and continues HUD/marker updates.
- An off-route match does not draw a false bright connector to the old route.
- Disconnect, cancellation, stale scene, and transfer failure behavior remain unchanged.
- If a larger marker resource is missing or invalid, RPK packaging must fail rather than silently using the old size.

## Automated verification

### Portable Swift

- Exact split continuity: traveled end, active-leg start, and matched marker are the same coordinate.
- Fractional matches on both halves of a segment never leave a geometry gap.
- A 2 m instruction with 10 m accuracy advances to the next actionable instruction.
- An instruction outside the pass radius is not skipped.
- Initial stationary bearing follows the route tangent.
- Course becomes active after two eligible fixes and falls back after three ineligible fixes.
- Circular heading differences around 0/360 behave correctly.
- A 29-degree delta does not refresh; a 30-degree delta does after 12 seconds.
- Route progress monotonicity and existing reroute tests remain unchanged.

### iOS/Xcode

- Snapshot configuration uses the selected bearing and retains the user near the lower safe viewport.
- Overlay commands use matched segment/fraction and the three route emphasis levels.
- Marker projection and route split align under bearings 0, 90, 180, and 270 degrees.
- Failed refresh retains the confirmed map.

### RPK

- Generated marker resources are indexed 46×54 PNGs with visible content and transparent margins.
- All eight marker headings remain valid.
- Maneuver resources and CSS render at the new size and safe offsets.
- Marker clamping uses the new center bounds.
- Existing envelope, scene, digest, publication, and disconnect tests remain unchanged.

Run the canonical gates through Make, then run iOS simulator/device build through GitHub Actions.

## Hardware acceptance

Use a safe outdoor route containing a straight section, a left turn, a right turn, and at least one parallel or crossing road.

1. Start while stationary. Confirm the road-snapped marker touches the bright route and the route faces upward.
2. Confirm a sub-accuracy instruction such as 2 m is replaced by the next useful maneuver.
3. Begin moving above 3.6 km/h. Confirm the next confirmed snapshot adopts travel course without oscillating on one poor fix.
4. Pass at least three maneuvers. Confirm distance decreases, turn changes happen once, and the active leg begins at the marker.
5. Stop and resume. Confirm the marker continues rotating through heading buckets while full-map refreshes remain bounded.
6. Deviate from route safely. Confirm rerouting behavior remains unchanged and no false connector is drawn.
7. Check HUD/marker visibility around every curved edge and export the final sanitized debug log.

Compilation, simulator tests, and deterministic fixtures do not establish Smart Band 10 hardware acceptance.

## References

- [Google Navigation SDK camera following modes](https://developers.google.com/maps/documentation/navigation/ios-sdk/camera)
- [Google Navigation SDK road-snapped location and travel-mode course](https://developers.google.com/maps/documentation/navigation/ios-sdk/reference/objc/Classes/GMSMapView)
- [Google top-down heading-up navigation perspective](https://developers.google.com/maps/documentation/navigation/ios-sdk/reference/objc/Enums/GMSNavigationCameraPerspective)
- [Apple MapKit follow-with-heading behavior](https://developer.apple.com/documentation/mapkit/mkusertrackingmode/followwithheading)

## Versioning and artifacts

Both installed components change:

- IPA: bump from 0.4.1 (15) to 0.5.0 (16); build and package only with GitHub Actions.
- RPK: bump from 0.5.0 (14) to 0.6.0 (15); build through the repository Make/Docker workflow.

The final handoff must list artifact paths, byte sizes, SHA-256 hashes, exact IPA/RPK changes, automated evidence, and the manual test plan above.
