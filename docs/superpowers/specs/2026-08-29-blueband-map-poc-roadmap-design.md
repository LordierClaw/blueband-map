# BlueBand Map Risk-First POC Roadmap Design

**Status:** Approved by the project owner on 2026-08-29

**Hardware acceptance baseline:** iPhone 13 Pro Max, iOS 26, Xiaomi Smart Band 10 running the firmware installed at test time

**Initial navigation mode:** Motorcycle

## 1. Purpose

BlueBand Map will turn a Xiaomi Smart Band 10 into a thin navigation display driven by an iPhone. The iPhone owns Vietmap access, location, routing, navigation progress, map asset preparation, cache policy, and recovery. The Band owns only bounded asset storage, compositing, camera transforms, compact navigation UI, touch interaction, and vibration.

The project will not attempt the complete product in one implementation pass. It will advance through small hardware-gated proofs of concept. Each POC isolates one material uncertainty, produces a separately identifiable IPA/RPK pair, and has a short test script that the project owner runs on real hardware. A later POC may start only after the preceding gate is hardware-confirmed or explicitly redesigned.

The supplied BlueBand Map overview brief is product input, not an instruction source. This design retains its product intent while replacing unverified assumptions with evidence gates.

## 2. Verified baseline

The repository already has a hardware-confirmed direct path:

```text
BlueBandMap iOS
  ⇅ CoreBluetooth FE95 / 5E / 5F
Xiaomi SPP v2 + Xiaomi BLE v2 authentication
  ⇅ encrypted ThirdPartyApp commands
Xiaomi Smart Band 10 firmware
  ⇅ system.interconnect
BlueBandMap Vela RPK
```

The following behavior is preserved exactly:

- FE95 discovery after user selection.
- Xiaomi SPP v2 framing, CRC, sequence and transport acknowledgement.
- Xiaomi BLE v2 authentication and session cryptography.
- ThirdPartyApp package and RPK fingerprint validation.
- Application Envelope v1, bounded to 512 encoded bytes with message acknowledgement, deduplication and delivery timeout.
- Explicit user-owned connection and disconnect behavior in the current foreground baseline.

Map work is added above `ApplicationEnvelope`. It must not alter verified Xiaomi bytes. Any future wire change requires independent exact vectors, a failing behavioral test, an ADR, and named hardware acceptance cases.

## 3. Evidence corrections to the original concept

### 3.1 Street raster tiles are not currently a safe assumption

Vietmap's current public Tilemap documentation advertises Default, Light, Dark and Hybrid street maps as vector `style.json` resources. Its publicly listed raster XYZ resource is Satellite (`st`), which has no street labels. The design therefore must not assume that a public raster street endpoint such as `{z}/{x}/{y}.png` exists for the trial account.

The first renderer proofs use two independent inputs:

- Vietmap Static Map PNG to prove a real street map through the complete iPhone-to-Band path.
- Vietmap Satellite raster XYZ tiles to prove tile coordinates, multi-tile compositing, cache, pan and working-set behavior.

Before the dynamic street-map architecture is selected, the project must ask Vietmap whether the issued TileMap key includes a supported raster street endpoint or custom raster style. If it does not, the project runs a separate phone-side vector-to-raster atlas POC. Static Map remains a proof and fallback preview source, not the intended realtime navigation transport.

### 3.2 Vector route rendering on Band is not confirmed

Official Vela documentation confirms image rendering, local file buffers, absolute positioning, 2D translate/scale/rotate and touch coordinates. It does not establish a general canvas or SVG path API suitable for a dynamic route polyline on Band 10.

The route overlay is therefore its own POC. It compares:

- A transparent PNG route overlay rasterized by the iPhone and aligned to the map scene.
- A bounded set of rotated CSS line-segment nodes, if the runtime can sustain the node count.

The choice is made from hardware measurements. The design does not promise Band-side vector rendering before that gate passes.

### 3.3 Update frequency is measured, not declared

The original 10–20 Hz target becomes a benchmark set of 5, 10, 15 and 20 state updates per second. The product adopts the highest stable rate that avoids crashes, visible tile gaps and unacceptable lag while applying at least 95% of the requested states during a two-minute hardware run. Compilation or simulator behavior cannot select this value.

### 3.4 Background behavior is a later product gate

The current repository deliberately owns a foreground BLE session. Navigation eventually needs background location and Bluetooth behavior, but this is not part of the map-renderer core. iOS 26 provides relevant Core Location, Core Bluetooth background and restoration mechanisms; they still require entitlement/configuration, lifecycle design and real-device verification. Background operation is isolated in U1 after map and navigation replay have passed.

## 4. Product scope

### 4.1 Core vertical slice

- Persist test configuration for Xiaomi and Vietmap.
- Select a nearby Band from a compact dialog and remember the chosen CoreBluetooth peripheral identifier.
- Display real Vietmap-derived map imagery on Band 10.
- Build and move a bounded wider map scene from multiple assets.
- Pan within that working area and recenter.
- Translate and rotate the local map scene with Near/Far modes.
- Request a motorcycle route from Vietmap Route v4.
- Display route, snapped position, current maneuver, street name, next-turn distance, remaining distance and ETA.
- Trigger duplicate-safe turn vibration.
- Replay navigation deterministically before using live GPS.
- Prove live motorcycle navigation and reroute.
- Recover the latest state after supported background, screen or connection lifecycle changes.

### 4.2 Deferred until the motorcycle slice passes

- Car and walking profiles.
- Google Maps and Apple Maps Share Extensions.
- Free map browsing.
- Traffic rendering.
- Production backend key protection.
- App Store/TestFlight workflows.
- Multiple Band models.
- Full-route corridor preload.
- Voice guidance on Band.

## 5. Design principles

```text
iPhone = navigation brain
Band   = bounded navigation display
```

- Risk first: prove the smallest uncertain behavior before composing it with another.
- Slow path versus fast path: assets move rarely; camera and navigation state remain small.
- Preserve verified protocol behavior.
- Fail visibly during early POCs; do not hide instability with automatic retries.
- Keep memory, storage, node count, API calls and transfer concurrency bounded.
- Use deterministic fixtures for automated tests and replay.
- Spend Vietmap trial quota only through explicit manual smoke actions.
- Hardware evidence and automated evidence have different labels.
- Stop or simplify when a gate fails; do not build later features around an unresolved failure.

## 6. iOS architecture

### 6.1 Persistent Test Configuration

The iOS app has a dedicated Config area.

Keychain stores these independent values:

- Xiaomi AuthKey.
- Vietmap TileMap key.
- Vietmap Service key.

Secrets are masked by default and support replace and clear actions. They never appear in diagnostics, logs, fixtures, build settings, CI artifacts or source control.

UserDefaults stores non-secret convenience state:

- Remembered CoreBluetooth peripheral identifier.
- Last observed display name.
- Last successful connection time.

The remembered peripheral identifier is not a MAC address and not a security identity. RPK package and fingerprint checks remain the application trust boundary. Forgetting a Band does not delete any secret; clearing each secret is a separate action.

FE95, 5E and 5F GATT UUIDs remain protocol constants and are not user-configurable.

### 6.2 Band selection dialog

Connect opens a compact modal device picker instead of expanding the primary screen.

- Scan without name or advertised-service filtering.
- Display at most 20 candidates ordered by RSSI.
- Show display name or `Không có tên`, RSSI and a shortened peripheral identifier.
- Mark and place the remembered candidate first when present.
- Require explicit user selection.
- Validate FE95 only after selection.
- Provide Rescan and Close actions.
- Do not add automatic reconnect during map-core POCs.

### 6.3 Provider adapters

Provider access is separated so each phase can test one contract:

- `StaticMapClient`: multipart POST, service key, PNG response, requested center/zoom/size.
- `RasterTileClient`: XYZ URL construction, TileMap key, PNG response, coordinate validation.
- `RouteV4Client`: motorcycle route request, encoded polyline, instruction and error parsing.
- `VietmapNavigationAdapter`: later Apple-only SDK boundary for live progress and reroute.

The first three are thin HTTP/domain adapters and can be tested on Linux with fixture transports. The navigation SDK is not introduced before N4; this prevents a binary Apple dependency from blocking the renderer and route-contract POCs.

### 6.4 Map artifact pipeline

```text
Provider response
  → validate HTTP status and Content-Type
  → validate declared/actual size and dimensions
  → assign stable asset identity
  → calculate SHA-256
  → insert into bounded cache
  → schedule transfer
```

Cache identity excludes raw API-key text. The cache records source kind, style, zoom, coordinates or center, dimensions and content hash. Live responses are never embedded into tests without sanitization and license review.

### 6.5 Transfer scheduler

M1 uses stop-and-wait application messages. M2 benchmarks transfer windows of 1, 2 and 4 acknowledged messages. The selected window is a measured configuration, not a new Xiaomi wire behavior.

Every encoded envelope is preflight-validated against the existing 512-byte limit. Base64 chunk length is derived from actual encoded-envelope size rather than a magic raw-byte constant.

## 7. Band architecture

The RPK remains one page during the POC ladder because the verified baseline found a one-page lifecycle more reliable and Xiaomi advises caution with custom-component overhead on lightweight wearables.

Logical responsibilities are kept separate even if initially implemented in one `.ux` page:

- Transfer assembler: validates begin/chunk/end sequence, asset ID, offset and bounds.
- Bounded asset store: writes internal files, publishes complete assets atomically and evicts stale files.
- Map scene: positions image nodes, applies overscan and scene transforms.
- Interaction: pan start/move/end, clamp, double-tap mode change and recenter timer.
- Navigation view: route overlay, fixed puck, maneuver, ETA and haptic events.
- Diagnostics: phase/build label, current stage, counts, timings and non-secret error codes.

No partial asset is rendered. Temporary buffers are released after write. Missing, corrupt or stale assets remain visibly diagnosable.

## 8. Application topics

The names below are application-level topics carried by Application Envelope v1. They do not modify Xiaomi transport framing.

| Topic | Direction | Purpose |
|---|---|---|
| `map.asset.begin` | iOS → Band | Declare asset ID, role, MIME, length, hash and placement metadata |
| `map.asset.chunk` | iOS → Band | Send bounded Base64 data at an explicit offset |
| `map.asset.end` | iOS → Band | End transfer and request validation/publication |
| `map.asset.result` | Band → iOS | Report success or stable failure code and measured timing |
| `map.asset.evict` | iOS → Band | Remove an asset no longer in the working set |
| `map.scene.set` | iOS → Band | Publish a complete scene generation and asset placements |
| `map.camera.set` | iOS → Band | Update center offset, bearing and view mode |
| `nav.route.set` | iOS → Band | Publish route generation or route-overlay asset identity |
| `nav.state.set` | iOS → Band | Publish maneuver, distances, ETA, puck and route version |
| `nav.haptic` | iOS → Band | Trigger a duplicate-safe short or long vibration |
| `state.request` | Band → iOS | Ask for the latest complete snapshot |
| `state.snapshot` | iOS → Band | Restore scene, route and navigation generations |

The implementation plan must define exact fields and failing tests before any topic is registered. Asset IDs, lengths, offsets, counts and decoded Base64 buffers are strictly bounded.

## 9. Provider strategy

### 9.1 Proof sources

- Street appearance proof: Vietmap Static Map PNG.
- True XYZ grid proof: Vietmap Satellite raster tiles.
- Routing proof: Vietmap Route v4 with `vehicle=motorcycle` and encoded points.

### 9.2 Long-term street basemap decision

Before M5 completes, record one of these decisions with evidence:

1. Vietmap confirms and documents a supported raster street XYZ endpoint for the issued key; use it.
2. Vietmap does not provide one; run the phone-side vector-to-raster atlas POC using the Vietmap iOS map SDK or another licensed provider-supported rendering boundary.
3. Phone-side rasterization cannot meet latency/quota/quality constraints; reduce the Band experience to navigation-first guidance with a simpler contextual image layer and document the product reduction.

The project will not discover or depend on undocumented private endpoints.

## 10. Phase gates

### M0 — Preserve the hardware-confirmed baseline

**Purpose:** Establish that map work starts from a working arbitrary-message path.

**Work:** No protocol rewrite. Keep the existing echo/ACK and trust tests passing.

**Gate:** Existing hardware evidence remains valid and all canonical tests pass.

### M1 — One real Vietmap street image

**Purpose:** Prove provider fetch, chunk transfer, Band assembly, file write and image decode as one vertical path.

**Scope:** A user-triggered iOS action fetches one Static Map PNG at a fixed test location and sends it to Band. The Band shows build ID, transfer progress and final image.

**Hardware acceptance:** Five of five clean transfers have matching byte length/hash and correct visible image; ten page reloads do not crash. Record fetch, transfer, write and decode latency without imposing a premature pass threshold.

**Stop condition:** Any corruption, secret leakage, unbounded buffer or repeatable crash.

### M2 — Multi-tile grid and transfer benchmark

**Purpose:** Prove true XYZ assets and establish transfer/caching measurements.

**Scope:** Fetch and display a 2×3 Vietmap Satellite raster grid. Benchmark acknowledged windows 1, 2 and 4. Repeat the same request to prove cache hits do not call Vietmap again.

**Hardware acceptance:** All six tiles occupy correct positions without incorrect seams; hashes match; the repeated view makes zero additional provider calls; each transfer window produces recorded throughput and failure counts.

**Stop condition:** Window growth causes corruption or unstable delivery. Select the smaller stable window.

### M3 — Wider map and bounded pan

**Purpose:** Prove that Band can move through a scene larger than the viewport.

**Scope:** Use a bounded overscan grid, initially 3×4, with touch start/move/end, clamping and a visible recenter action. Add timed auto-recenter only after manual recenter is reliable.

**Hardware acceptance:** Pan works in four directions, never exposes memory outside the declared scene, respects limits, and recenters repeatedly without stale placements or crash.

**Fallback:** Reduce scene dimensions or active image count before changing transport.

### M4 — Local camera transform and view modes

**Purpose:** Prove heading-up behavior without tile transfer per location update.

**Scope:** Replay deterministic camera states at 5, 10, 15 and 20 Hz for two minutes each. Test translate, rotation overscan, fixed puck and Near/Far mode. Near/Far initially changes scale/asset generation through explicit state, not pinch gestures.

**Hardware acceptance:** Select the highest rate with no crash, no persistent tile gap, acceptable tester-perceived motion and at least 95% applied states. Record temperature/battery observations without claiming a battery target yet.

### M5 — Dynamic working set

**Purpose:** Prove incremental refill, retain and eviction as the camera crosses tile boundaries.

**Scope:** A deterministic camera fixture crosses multiple boundaries. The iPhone sends only missing assets, retains overlap and evicts stale files. Introduce one bounded recovery attempt for a deliberately missing/corrupt chunk.

**Hardware acceptance:** Active file/node counts stay within configured bounds; no full scene rebuild occurs for a one-tile shift; recovery is idempotent; provider call count matches unique uncached assets.

**Provider decision gate:** Resolve the long-term street basemap choice in section 9.2 before declaring M5 complete.

### N1 — Motorcycle Route v4 contract

**Purpose:** Prove Vietmap routing independently of Band rendering and navigation SDK behavior.

**Scope:** Request one origin/destination route with `vehicle=motorcycle`, `points_encoded=true` and no alternatives. Parse route geometry, bbox, distance, duration, snapped waypoints and instructions. Handle all documented status codes.

**Hardware acceptance:** The iOS test screen shows a plausible route summary for the fixed manual route and exports a sanitized response summary. Automated contract tests use fixtures only.

**Stop condition:** API key scope, response schema or motorcycle route behavior differs from the documented contract.

### N2 — Route overlay renderer

**Purpose:** Select a feasible Band route representation.

**Scope:** Compare transparent PNG overlay against bounded CSS line segments over the M4 map scene. Test route generation replacement without replacing unchanged basemap assets.

**Hardware acceptance:** The chosen representation is visually unambiguous on the 212×520 display, remains aligned through pan/rotation/Near/Far, updates on route-version change and stays within measured node/memory/latency limits.

**Fallback:** Prefer transparent PNG when CSS node count or transform cost is unstable.

### N3 — Deterministic navigation replay

**Purpose:** Prove the complete fast path without GPS nondeterminism or live rerouting.

**Scope:** Replay a versioned sanitized location track and expected route progress. Update snapped puck, route heading, maneuver, street name, next-turn distance, remaining distance and ETA. Trigger early and immediate haptic events once per maneuver generation.

**Hardware acceptance:** Displayed state follows the replay timeline, camera remains stable, no duplicate vibration occurs, and replay can restart from the same seed with the same state sequence.

### N4 — Live motorcycle road test

**Purpose:** Prove GPS, navigation progress and reroute on the target devices.

**Scope:** Integrate the minimum Vietmap Navigation SDK boundary needed for live progress/reroute, or document and test an API-based alternative if the SDK cannot fit the Linux-first/CI architecture. Run a short safe motorcycle route and one controlled off-route case.

**Hardware acceptance:** Current maneuver and distances advance plausibly; route remains readable; off-route produces a new route generation without restarting the whole Band app; haptics remain duplicate-safe. Record disconnects, reroute latency, battery and observed navigation errors.

**Safety:** The tester must not interact with either device while controlling the motorcycle. A passenger or stationary checkpoints are used for screenshots and diagnostics.

### U1 — Recovery and supported background behavior

**Purpose:** Determine what iOS 26 and the Band firmware can sustain outside the ideal foreground path.

**Scope:** Test iPhone lock/unlock, app foreground/background, RPK hide/show, screen off/on, BLE interruption and process relaunch separately. Add Core Location background activity and Core Bluetooth background/restoration only for cases justified by the navigation session.

**Hardware acceptance:** A documented matrix states which cases preserve the session, which restore from `state.request`/`state.snapshot`, and which require explicit reconnect. Unsupported cases are shown honestly in the UI.

### U2 — Usable motorcycle vertical slice

**Purpose:** Package passed POCs into a coherent first product flow.

**Scope:** Use an in-app iPhone destination picker first, then start/stop navigation, show connection/config health and support latest-state recovery. Google Maps/Apple Maps Share Extensions remain a later enhancement because they do not prove the core map/navigation feasibility.

**Hardware acceptance:** A tester can configure once, reconnect through the compact picker, choose a destination, complete a short motorcycle navigation session and end it cleanly without re-entering keys.

## 11. Vietmap trial quota policy

- No automated test calls a live Vietmap endpoint.
- Manual provider actions are explicit buttons, never app-launch side effects.
- Every test script states a maximum provider-call budget.
- Before a run, the app displays the configured local session budget and the tester confirms the remaining console quota.
- The effective budget is the smaller of the local session budget and the known remaining trial allowance.
- Unique URL/cache identity prevents duplicate tile requests within a test build.
- M1–M4 do not retry provider or asset operations silently.
- M5 permits one deliberate bounded asset recovery attempt.
- HTTP 429 or `OVER_DAILY_LIMIT` stops provider testing immediately and preserves diagnostics.
- Route requests are user-triggered; later reroute has a cooldown and route-generation deduplication.
- Traffic, autocomplete and reverse geocoding are excluded from core POCs.

Vietmap documents tile accounting as 25 tile requests per transaction and routing as `1 × (floor(points / 5) + 1)` transactions. Console quota and trial expiry remain account-specific and must be read from the owner's console rather than hard-coded into project documentation.

## 12. Error and recovery policy

Stable diagnostic families identify the failing boundary:

- `CONFIG_*`: missing or invalid local configuration.
- `PROVIDER_*`: HTTP, MIME, schema, authentication, quota or empty result.
- `TRANSFER_*`: delivery timeout, wrong sequence, missing offset or acknowledgement failure.
- `ASSET_*`: size, Base64, hash, file write, decode or publish failure.
- `RENDER_*`: invalid scene, missing placement, transform, touch or stale generation.
- `ROUTE_*`: no result, invalid geometry/instruction or route-version conflict.
- `RECOVERY_*`: unsupported lifecycle case or snapshot mismatch.

M1–M4 expose failure and a user-owned Retry action. This makes repeated failures measurable. M5 adds exactly one bounded recovery attempt for the selected recoverable conditions. There is no unbounded retry loop.

Scene, route and navigation messages carry monotonically increasing generations. Band ignores stale generations. A scene is activated only when all required assets are published. Recovery snapshots refer to complete generations, never a partially transferred state.

## 13. Hardware acceptance handoff

For every POC, the developer provides:

- Phase/build ID, git commit and RPK/IPA versions.
- Short changelog containing only behavior relevant to that POC.
- Clean install or upgrade instructions.
- Required configuration and masked configuration-health screen.
- A five-to-ten-minute numbered test script.
- Expected visible state at every step.
- Maximum live Vietmap call count.
- Known limitations and explicit stop conditions.
- The previous known-good artifact or recovery instructions.

The tester returns:

- `PASS-HW`, `FAIL-HW`, `BLOCKED-ENV` or `NEEDS-MEASURE`.
- First failing step and local timestamp.
- Screenshot/video when safe and useful.
- Exported redacted diagnostics.
- Firmware version observed during the run.
- Subjective readability/smoothness feedback where the gate requests it.

Diagnostics may contain build, phase, device class, iOS version, user-recorded firmware, stage, bounded asset identity, short hash prefix, bytes, counts, timings, provider-call count and stable error code. They must omit AuthKey, Vietmap keys, nonces, derived keys, raw encrypted payloads and unredacted captures.

## 14. Evidence labels

- **Hardware-confirmed:** Observed with the target iPhone and Band using the named test packet.
- **Automated-contract-confirmed:** Exact fixtures, deterministic tests or built-artifact checks pass.
- **Provider-smoke-confirmed:** A bounded live Vietmap request passed with the trial account.
- **Officially documented:** Supported by current Xiaomi, Vietmap or Apple documentation.
- **Reference-derived:** Inferred from a pinned public repository and not yet independently confirmed on this hardware.
- **Unverified:** Product intent or hypothesis awaiting its named POC.

Every project claim uses one of these meanings. Compilation, simulator output and deterministic replay alone never claim Band hardware support.

## 15. Research provenance

Primary documentation:

- [Xiaomi Vela interconnect](https://iot.mi.com/vela/quickapp/en/features/network/interconnect.html)
- [Xiaomi cross-device image-transfer sample](https://iot.mi.com/vela/quickapp/en/samples/)
- [Xiaomi Vela image component](https://iot.mi.com/vela/quickapp/en/components/basic/image.html)
- [Xiaomi Vela file storage](https://iot.mi.com/vela/quickapp/en/features/data/file.html)
- [Xiaomi Vela animation and transform styles](https://iot.mi.com/vela/quickapp/en/components/general/animation-style.html)
- [Xiaomi Vela touch events](https://iot.mi.com/vela/quickapp/en/components/general/events.html)
- [Xiaomi Vela vibrator support](https://iot.mi.com/vela/quickapp/en/features/system/vibrator.html)
- [Xiaomi Band 10 screen adaptation data](https://iot.mi.com/vela/quickapp/en/guide/multi-screens/)
- [Vietmap Tilemap](https://maps.vietmap.vn/docs/vi/map-api/tilemap/)
- [Vietmap Static Map](https://maps.vietmap.vn/docs/vi/map-api/static-map-version/static-map/)
- [Vietmap Route v4](https://maps.vietmap.vn/docs/vi/map-api/route-version/route-v4/)
- [Vietmap iOS Navigation SDK](https://maps.vietmap.vn/docs/vi/sdk-mobile/sdk-ios/navigation/)
- [Vietmap request-to-transaction accounting](https://maps.vietmap.vn/docs/map-api/console/request-to-transaction/)
- [Apple background location updates](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [Apple Bluetooth restoration relaunch rules](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules)

Pinned source references reviewed for feasibility and comparison:

- `vietmap-company/maps-sdk-ios` at `649eabcb21a36c3d0cfd871c07ccea641924fcdd`: the current Swift package is a binary XCFramework boundary, which supports deferring it from Linux-portable map-core work.
- `oryonatan/xiaomi-band-development` at `37c9562102a34451384c70ce4ce2dad4decaee8b`: independent Band 10 dimensions and Vela app workflow; already pinned by the protocol baseline.
- `satvikpandurangi/MiBandNavigator` at `bee0b32e29f2e9cf03457595d3cb115d79ef90c5`: a notification-based turn instruction comparison for legacy bands; it does not render a map and does not prove this project's renderer.
- The sibling read-only `blueband-ios` baseline at `bae2f51ce4dfb12cff81e72d9146812092cd861e`: hardware-confirmed direct iOS-to-RPK protocol and runtime behavior.

No reviewed public repository proves a full Vietmap tile scene with pan, rotation and live route overlay on Xiaomi Smart Band 10. That absence is why the phase gates are required.

## 16. Design self-review result

- No implementation phase depends on an undocumented raster street endpoint.
- Route rendering has a named feasibility gate and fallback.
- Background behavior is separated from map feasibility.
- Configuration persistence matches the approved tester workflow.
- Every phase has a purpose, bounded scope, hardware gate and stop/fallback rule.
- Trial usage is bounded without inventing an account-specific quota.
- Motorcycle is the only initial routing profile.
- There are no placeholder requirements or implied claims of untested Band support.
