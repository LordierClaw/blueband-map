# Realtime navigation completion and handoff

**Request:** Continue from the accepted map/route/marker presentation; deliver moving guidance and map updates during a user-started locked-screen navigation session, targeting capture-to-Band-display latency below five seconds. Preserve the UI, 8192-byte image ceiling, atomic scene publication, and verified Xiaomi wire bytes.

**Execution:** Inline on `main`. The explicit request to finish and deliver extends the earlier CPU experiment into a background-only native implementation. Device visual approval and latency acceptance remain manual gates, not claims inferred from tests.

## Baseline recovered

- Latest preceding task: `Thêm realtime map GPS` was interrupted before doing work. The older `Triển khai thiết kế map atomic` task and current repository show the accepted UI and later location repairs.
- Starting HEAD: `f50fa8211130463718f0e29d239f5ccb720d31eb`.
- Existing delivered artifacts: IPA 0.5.9 (25), RPK 0.6.11 (26). Unreleased location repairs used iOS 0.5.10 (26).
- Starting workspace included an unfinished `VietmapMapStyle` and two failing style tests; these were completed in place.
- Confirmed RED: two `VietmapStyleClientTests` failures in `make test-swift`; Actions run 33699106201 reproduced `MAP_BACKGROUND_UNAVAILABLE` for a locked-screen render. That run also exposed a late Core Location callback over-fulfilling a test expectation.

## Implementation and boundaries

- Retain the SDK renderer in foreground. On inactive/background execution, use Core Graphics bitmap contexts and Core Text with the same provider DM style selection, camera projection, route overlay geometry/strokes, and existing final image encoder.
- Fetch only tiles intersecting the rotated viewport plus a 24-pixel label margin, capped at nine. Reuse decoded tiles between movement updates. Cache at most 16 tiles and an estimated 24 MiB of decoded geometry/properties; invalidate on key change. Responses remain bounded and restricted to the existing Vietmap host.
- Bound individual map HTTP calls to two seconds and background rendering to a three-second cancellation deadline. Keep GPS and rerouting independent of rendering. Existing latest-pending scheduling and one-second refresh cooldown continue to bound the scene queue.
- Preserve the accepted marker `(106,374)`, overlay assets, Band layout, JPEG/PNG encoder, 212x520 transfer size, scene protocol, and Xiaomi authentication/transport.
- Use the existing location lifecycle fixes: When-In-Use authorization, temporary precise-location request, background location and Bluetooth modes, session ownership, transient `locationUnknown` recovery, service checks away from the main actor, and actionable GPS health.
- Native background labels use system Vietnamese font fallback and the longest visible near-straight source-geometry run. This is an explicit difference from the SDK label placement and needs device comparison on curved streets. No bitmap rotation of a previous frame is used.
- Foreground/background switches cancel pending SDK work before background rendering. CPU work checks cancellation and cannot publish after the navigation generation changes.

## Verification and acceptance

- Portable tests cover real style layer selection/filter interpretation, width interpolation, text tokens, and credential-host rejection.
- iOS tests exercise actual background CPU rendering with an injected HTTP fixture, repeated-frame cache reuse, five headings, polygon holes, road labels, final encoded payload bounds, camera anchoring, and moving GPS while rendering is slow. The decoded transfer images are exported from the test result for visual inspection.
- A fresh bounded live-provider probe resolves the current DM style and decodes nine actual Vietmap tiles. Provider responses and keys remain under ignored `local/`.
- Canonical local gate: `make test`, `make lint`, `scripts/verify-no-secrets.sh`, `git diff --check`.
- Delivery gate: successful GitHub Actions simulator tests, arm64 build, built-app plist verification, valid IPA ZIP and SHA-256. iOS version 0.5.11 (27); RPK stays 0.6.11 (26).
- Physical acceptance is not established by the above. Test at least two minutes foreground and ten minutes locked, with turns, tile crossings, reroute, poor GPS/network, and repeated lock/unlock and stop/start. Inspect `band.displayed.fixAgeMs`, publication gaps, UI continuity, and error counts. Every sample at or above 5000 ms is a target violation; a lack of display events is also a failure.

References: [Apple background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background), [Apple OpenGL ES background restriction](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/OpenGLES_ProgrammingGuide/ImplementingaMultitasking-awareOpenGLESApplication/ImplementingaMultitasking-awareOpenGLESApplication.html).
