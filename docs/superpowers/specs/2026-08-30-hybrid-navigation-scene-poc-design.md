# BlueBand Map Hybrid Navigation Scene POC Design

**Status:** Approved in conversation on 2026-08-30, including the two-batch delivery revision

**Target hardware acceptance:** iPhone 13 Pro Max, iOS 26, Xiaomi Smart Band 10 with the firmware installed at test time

**Initial navigation content:** Current position and heading, nearby major roads, active route, and next maneuver. Points of interest, buildings, minor labels, and free map browsing are excluded.

## 1. Purpose

BlueBand Map must discover the lightest reliable way to show useful navigation context on Xiaomi Smart Band 10. It must not assume that a map has to be an image, and it must not assume that fewer BLE bytes automatically means less work for the Band.

The project will compare two independent renderers fed by one phone-side navigation scene:

- a simplified raster renderer that delegates decode and display to Vela's native image component; and
- a compact vector renderer that sends a bounded set of road and route primitives for Band-side composition.

The current M1 Vietmap Static Map PNG path remains the measured raster baseline. Existing transfer recovery and reliability work remains in the repository. The project adds explicit limits and hardware measurements rather than deleting that work.

This design also reduces wasted CI work. Existing tests are retained, but routine automation becomes path-aware and live Vietmap calls remain explicit, bounded manual actions.

## 2. Relationship to existing designs

This document refines the renderer, transfer-measurement, and CI portions of:

- `2026-08-29-blueband-map-poc-roadmap-design.md`; and
- `2026-08-30-poc-handoff-artifacts-design.md`.

The earlier roadmap remains authoritative for verified Xiaomi protocol invariants, configuration persistence, provider boundaries, routing, background behavior, safety, and evidence labels. The handoff design remains authoritative for artifact packaging. Where phase names or renderer assumptions differ, this document controls the hybrid-renderer experiment.

The sibling `/home/hainn/blue/code/blueband-ios` repository remains a read-only protocol baseline. No hybrid-renderer POC changes FE95 discovery, Xiaomi BLE v2 authentication, Xiaomi SPP v2 framing, encryption, transport acknowledgements, or verified Xiaomi bytes.

## 3. Current evidence and corrections

### 3.1 Provider smoke evidence

On 2026-08-30, one bounded live request used the locally stored Vietmap Service key with the documented Static Map multipart contract. The response was:

- HTTP 200;
- `Content-Type: image/png`;
- 21,567 bytes;
- 212 by 360 pixels, RGBA PNG;
- SHA-256 `c267280ac269b98acf1245065ffef6562838426a861a29ae43c5bc61c0fe4373`.

Visual inspection confirmed a real street map rather than an empty or error image. This is **provider-smoke-confirmed** evidence for the current Static Map contract. It does not prove Band rendering, transfer stability, vector-tile access, route behavior, or production quota.

The live response remains outside Git. Automated tests use sanitized deterministic fixtures. A live smoke command may make at most one request per invocation and must read its key from ignored local storage or an explicitly configured CI secret.

### 3.2 Vela rendering evidence

Current official Vela component documentation lists native `image`, `div`, `stack`, and `chart` components but does not document a general Canvas or SVG path component for Smart Band 10. The chart component accepts sequential values and is not an arbitrary two-dimensional polyline renderer.

Therefore:

- native image decode is the conservative path;
- free-form Band-side vector drawing is unverified;
- rotated native layout primitives are a bounded experiment, not a product assumption; and
- custom binary image decoders or general geometry engines on the Band are excluded because they move CPU and allocation work into the weakest device.

### 3.3 Current CI evidence

The current Linux workflow runs all Docker-capable suites on every push and pull request, including documentation-only changes. Its Gitleaks history scan currently identifies the exact synthetic AuthKey fixture in `tests/scripts/verify-no-secrets.test.sh`, so the security gate produces a false failure after the functional suites finish.

The macOS workflow currently exposes a real cross-toolchain issue: `weak let` is accepted by the Linux Swift toolchain but rejected by Xcode because a weak reference must be mutable. This validates retaining a relevant macOS gate while making it path-aware.

The CI redesign must fix those signals rather than suppressing whole rule families or deleting useful tests.

## 4. Product boundary

The Band is a bounded navigation display, not a general map engine. The approved minimum scene contains only:

- current position;
- current heading;
- nearby major roads needed for orientation;
- active route emphasis;
- next maneuver direction and distance.

The following are not part of the hybrid-renderer decision:

- points of interest;
- buildings and land parcels;
- traffic layers;
- arbitrary labels;
- free browsing;
- arbitrary pitch or 3D view;
- offline regional map storage;
- automatic renderer selection before hardware evidence exists.

## 5. Architecture

```text
Vietmap
  -> iPhone MapSource
  -> NavigationScene
       -> RasterEncoder -> Raster transfer -> Native image renderer
       -> VectorEncoder -> Vector transfer -> Bounded primitive renderer
  -> POC metrics and sanitized run record
```

### 5.1 MapSource

`MapSource` owns provider access and response validation. Vietmap keys remain on the iPhone. Provider adapters validate HTTP status, MIME type, dimensions, schema, and configured call budget before creating scene input.

The first raster experiments use the already smoke-confirmed Static Map PNG. Real vector-scene work uses only a documented Vietmap vector resource available to the issued TileMap key. The project does not discover or depend on private endpoints.

### 5.2 NavigationScene

`NavigationScene` is independent of transfer format and Band renderer. It contains:

- stable scene and route generation identifiers;
- viewport width and height;
- geographic center, zoom class, and orientation mode;
- major-road polylines with a small road-class enum;
- active-route polyline;
- current-position point and heading;
- next-maneuver kind and distance.

Geographic coordinates are converted, clipped, simplified, and quantized on the iPhone. The Band never parses vector tiles, performs map projection, calls Vietmap, or runs route matching.

### 5.3 RasterEncoder

The raster path has two profiles:

- **Baseline raster:** the current validated Vietmap PNG, used to measure existing behavior.
- **Optimized raster:** a phone-produced, palette-reduced navigation image sized for the visible Band map area.

The baseline is deliberately the one exception that does not originate as `NavigationScene`; it exists to measure the already-built provider-to-image path. The optimized profile renders `NavigationScene`, removes information outside the approved content, uses a small controlled palette, and preserves visual contrast between background, major roads, route, and current position. It remains a normal image that Vela's native component can decode. The first hard payload ceiling is 64 KiB.

### 5.4 VectorEncoder

The vector path encodes a versioned, bounded binary scene with quantized integer coordinates. It includes only road segments, active-route segments, current position, and maneuver data. Counts and decoded bytes are validated before allocation.

Version 1 is a fixed-record format: a magic/version header, viewport dimensions, road/route segment counts, fixed-width segment records (`x1`, `y1`, `x2`, `y2`, class), current-position coordinates, heading, maneuver enum, and distance. All multibyte integers use one declared byte order. Variable-length labels, JSON geometry objects, projection metadata, and provider fields are excluded. The exact bytes are frozen in the required ADR and independent vectors before implementation.

The vector POC begins with deterministic synthetic scenes of 8, 20, and 40 line segments. A real Vietmap-derived vector scene is attempted only after those fixtures identify a stable primitive range. The selected hard limit is the largest lower range that passes hardware acceptance, not the first range that renders once.

The encoded binary application payload uses the existing bounded asset-transfer mechanism and does not alter Xiaomi transport framing. Exact vectors, an ADR, failing behavioral tests, and named hardware acceptance cases are required before registering the format.

### 5.5 TransferCoordinator

Raster and vector transfers are separate use cases. They share only the authenticated application envelope, acknowledged delivery, deduplication, checksum support, and bounded transfer coordinator.

The coordinator enforces:

- one prepared renderer and one active transfer at a time;
- stop-and-wait delivery for the initial hardware comparison;
- payload and message-count ceilings;
- no chunk-size or transfer-window increase before measurements justify it;
- explicit cancellation and disconnect cleanup; and
- sparse Band state changes with detailed phone-side timing.

Existing recovery logic remains available. During renderer benchmarking it is explicit in the run record and cannot silently turn a failed vector run into a raster success.

### 5.6 BandRenderer

The Band has independent raster and vector renderer state machines.

The raster renderer receives one bounded image asset, validates it, publishes it atomically, displays it through the native image component, and releases transfer buffers.

The vector renderer receives one bounded scene, validates all counts and coordinates, creates only the accepted primitive count, renders it once, reports a summary, and releases decoded transfer buffers. It does not create custom component trees, animate every chunk, or retain raster and vector scenes simultaneously.

## 6. Renderer selection and preparation handshake

Renderer selection is explicit in the iPhone test UI. Automatic selection is deferred until the comparison gate has passed.

One test run follows this sequence:

1. The iPhone and Band complete the existing authenticated session readiness proof.
2. The tester selects **Raster Map Test** or **Vector Map Test**.
3. The iPhone builds the selected payload but does not transmit its bytes.
4. The iPhone sends `render.prepare`.
5. The Band validates renderer support, format version, dimensions, decoded bytes, and primitive count.
6. The Band clears the previous renderer state and returns `render.ready` or `render.reject`.
7. Only `render.ready` permits asset transfer.
8. The Band validates the completed payload, renders it, and sends one `render.result` summary.
9. The iPhone closes and persists the test run.

### 6.1 Application messages

These are application-envelope topics, not Xiaomi wire changes.

| Topic | Direction | Required purpose |
|---|---|---|
| `render.prepare` | iPhone to Band | Declare run, renderer, format, dimensions, decoded bytes, checksum, and primitive count |
| `render.ready` | Band to iPhone | Confirm prepared renderer and accepted limits |
| `render.reject` | Band to iPhone | Reject before transfer with one stable reason |
| Existing bounded asset topics | iPhone to Band | Transfer the selected raster or vector payload |
| `render.result` | Band to iPhone | Report validation/render outcome and aggregate Band timings |

Every message carries `runId`, `sceneId`, renderer kind, and format version where applicable. A result for another run or generation is stale and ignored.

### 6.2 Stable preparation failures

The initial reject set is:

- `unsupportedRenderer`;
- `unsupportedFormatVersion`;
- `busy`;
- `payloadTooLarge`;
- `tooManyPrimitives`;
- `invalidDimensions`;
- `insufficientStorage`.

In benchmark mode, a vector reject or render failure ends that run. It does not automatically fall back to raster because hidden fallback would invalidate the comparison.

## 7. Diagnostics and test-run records

Detailed telemetry is collected on the iPhone. The Band keeps only bounded counters and timestamps in memory and sends one summary at completion or failure. It does not append per-chunk logs or update progress UI for every chunk.

On iPhone, runs are written under the app's Application Support `test-runs` directory. A selected run is exported as a sanitized bundle through the iOS share sheet. After the owner returns that export, the developer imports it into the Git-ignored workspace path below:

```text
local/test-runs/<timestamp>-<run-id>-<renderer>/
|- run.json
|- events.jsonl
|- metrics.json
|- payload.sha256
|- preview.png
`- replay-payload.bin     # present only when explicitly enabled
```

### 7.1 `run.json`

The run identity records:

- run and scene identifiers;
- Git commit and iOS/RPK versions;
- renderer and format version;
- iPhone model and iOS version;
- user-recorded Band firmware;
- sanitized scene identity;
- start/end timestamps and terminal result.

It stores key presence, never key values. Vietmap keys, Xiaomi AuthKey, Apple credentials, derived keys, nonces, raw encrypted captures, and provisioning data are prohibited.

### 7.2 `events.jsonl`

Events cover connection readiness, prepare, ready/reject, transfer start, acknowledged chunks, retry/cancel, transfer completion, validation, render, disconnect, and terminal result. Payload bytes and secrets are not event fields.

### 7.3 `metrics.json`

The metrics record:

- provider fetch duration and call count;
- encoded and decoded payload bytes;
- message and chunk counts;
- retry count;
- acknowledgement p50, p95, and maximum latency;
- prepare, transfer, validation, render, and total durations;
- primitive count for vector runs;
- stable failure code when unsuccessful.

`preview.png` gives the tester a phone-side expected view for both renderers. Replay payload storage is off by default. A sanitizing export command packages an explicitly selected run for feedback without copying configuration or credentials.

## 8. Runtime failure policy

- Invalid Vietmap status, MIME, dimensions, or schema ends the run before renderer preparation.
- Provider quota or authorization failures are not retried automatically.
- Wrong chunk order or offset is rejected rather than guessed.
- Timeout or disconnect closes the temporary file/decoder, clears active renderer state, and ends the run.
- Checksum mismatch deletes the temporary payload and prevents rendering.
- Rendering failure returns one stable result and releases the selected renderer state.
- Retry counts are finite and visible in telemetry.
- No error path retains both raster and vector assets in Band memory.
- No recovery loop is unbounded.

## 9. Two delivery batches and internal checkpoints

The work is delivered in two implementation batches. Internal checkpoints preserve evidence boundaries but do not cause separate planning, review, IPA, or RPK cycles.

### H1 — Hybrid renderer evaluation build

H1 uses one implementation plan and one continuous development pass for P0 through P2-Gate. It produces one iPhone app containing explicit Raster and Vector test functions, one RPK containing both bounded renderers, one combined hardware test packet, and one immutable artifact handoff.

P0, P1, P2-R1, P2-R2, P2-V0, and P2-V1 are internal checkpoints in that plan. Automated failures stop implementation until fixed, but no additional owner approval is requested between them. Hardware support is not claimed while H1 is being built; all renderer hardware gates are executed together by the owner after the H1 IPA/RPK handoff.

The owner returns the raster/vector test runs and readability feedback once. P2-Gate then selects the renderer for H2.

### P0 — Evidence foundation

**Purpose:** Restore trustworthy, efficient automation before adding renderer behavior.

**Scope:** Make CI path-aware, correct the exact synthetic-secret false positive without disabling generic secret detection, fix known Xcode compatibility failures, and add a one-call manual Vietmap smoke command.

**Gate:** Relevant automated jobs pass for a named commit. A documentation-only change does not start Docker or macOS builds. The live smoke command records status, MIME, dimensions, bytes, and hash without exposing the key.

### P1 — Renderer handshake and telemetry

**Purpose:** Prove explicit renderer selection, Band preparation, stable rejection, and durable run records without adding another map renderer.

**Gate:** Raster and vector selections receive the expected ready/reject response; limits reject before payload transfer; successful and failed runs produce sanitized records.

### P2-R1 — Raster baseline

**Purpose:** Measure the existing real Vietmap PNG path under the new handshake and telemetry system.

**Hardware gate:** Five consecutive transfers show the correct image and matching checksum without Band hang, RPK crash, or restart. The run records expose payload, chunk, retry, acknowledgement, transfer, and render measurements.

### P2-R2 — Optimized raster

**Purpose:** Measure a palette-reduced navigation image against the same scene and device.

**Scope:** Prove encoding first with a deterministic `NavigationScene`. When P2-V1 adds the documented real Vietmap scene source, render that same real scene through raster again before P2-Gate.

**Hardware gate:** Major roads, route, position, and maneuver remain legible. Five consecutive runs are stable. The result is smaller or materially faster than baseline; otherwise baseline remains the raster candidate and the failed optimization is recorded.

### P2-V0 — Synthetic vector

**Purpose:** Find a safe Band primitive range independently of provider parsing.

**Hardware gate:** Run 8, 20, and then 40 segments in order. Stop increasing at the first crash, hang, visible corruption, or unacceptable render delay. A lower range passes only after five consecutive stable runs.

### P2-V1 — Vietmap vector scene

**Purpose:** Replace synthetic geometry with a documented Vietmap-derived scene filtered on the iPhone.

**Scope:** Build one real `NavigationScene`, then feed that exact scene to both optimized raster and compact vector so P2-Gate compares equivalent content.

**Hardware gate:** The real area is recognizable, route/position are unambiguous, checksum matches, and five consecutive runs remain inside the P2-V0 accepted limits.

### P2-Gate — Renderer decision

Compare optimized raster and compact vector using the same viewport and navigation content. The decision order is:

1. no hang, crash, restart, or corruption;
2. bounded Band work and repeatable render behavior;
3. total ready-to-visible time;
4. navigation readability;
5. transfer bytes and message count.

Raster is the default if vector does not clearly improve the complete hardware result. A smaller wire payload alone cannot select vector.

### H2 — Selected navigation renderer build

H2 begins only after the H1 hardware feedback selects a renderer. It uses one implementation plan and one continuous development pass for P3 through P6, followed by one combined IPA/RPK handoff and hardware packet. The rejected renderer remains available only in the H1 evaluation artifact and is not carried into the H2 runtime.

### P3 — Wider area

Use only the selected renderer to show a wider nearby-road scene while retaining the same bounded navigation content.

### P4 — Pan and refresh

Band gestures request a new scene from the iPhone. The first implementation regenerates a bounded viewport instead of retaining a large regional map on the Band. Repeated pan/refresh must not accumulate renderer state.

### P5 — Routing

Integrate the documented Vietmap route contract and populate active route, current position, and next maneuver in `NavigationScene`. Routing is tested independently before live GPS and reroute.

### P6 — View modes

Add only bounded north-up and heading-up modes plus discrete zoom levels. Arbitrary pitch, continuous free zoom, and general map browsing remain excluded.

Only H1 and H2 are delivery-level POCs for artifact and handoff purposes. The P0–P6 names are evidence checkpoints inside those two POCs.

## 10. Initial hardware acceptance limits

- Target ready-to-visible time: at most 15 seconds.
- Stability sample: five consecutive runs for each candidate and threshold.
- Active transfers: one.
- Initial raster payload ceiling: 64 KiB.
- Vector segment progression: 8, 20, then 40; stop on the first unstable level.
- Payload checksum: exact match required.
- Band UI/log updates: no per-chunk updates.

These are conservative initial gates, not production performance claims. Measurements may justify lowering limits immediately. Raising transport or primitive limits requires a separate reviewed change and hardware acceptance.

## 11. Test strategy

### 11.1 Deterministic automation

- `NavigationScene` validation, clipping, simplification bounds, and generation handling.
- Raster and vector encoding with exact byte/hash fixtures.
- Preparation acceptance and every stable reject reason.
- Full prepare/ready/transfer/result contract replay.
- Wrong run, stale generation, offset, checksum, timeout, cancellation, and disconnect behavior.
- Metrics aggregation and secret-safe run export.
- Handoff generation and artifact hash verification.

No deterministic test calls a live Vietmap endpoint.

### 11.2 Manual provider smoke

The manual Vietmap smoke action:

- reads an ignored local key or explicit CI secret;
- displays the endpoint category and maximum call count before execution;
- performs at most one request;
- validates status, MIME, dimensions, and non-empty body;
- records bytes and SHA-256;
- never prints the key or response URL containing it.

### 11.3 Hardware acceptance

The project owner loads the delivered IPA/RPK, runs the numbered packet, and returns `PASS-HW`, `FAIL-HW`, `BLOCKED-ENV`, or `NEEDS-MEASURE` with the first failed step and a sanitized run export where possible.

Compilation, simulator output, deterministic replay, and provider smoke cannot claim Band hardware support.

## 12. CI redesign

Existing tests are preserved but routed by changed paths.

### 12.1 Fast repository checks

Formatting, metadata, tracked-file policy, handoff validation, and secret-safe checks run without starting every language container. Documentation-only changes use this lane and must not allocate a macOS runner.

### 12.2 Impacted Linux suites

- `packages/BlueBandKit/**` runs portable Swift tests.
- `apps/band/**` runs RPK tests, lint, and build.
- `tools/protocol-lab/**` and protocol vectors run protocol-lab tests.
- shared build/test scripts run the suites they affect.

Docker and Make remain canonical locally. CI may invoke the same Make targets or their documented suite-specific targets.

### 12.3 Relevant macOS gate

The macOS/Xcode workflow runs only for iOS, portable Swift shared with iOS, project generation, or its workflow/build scripts. It retains package tests, simulator tests, and one unsigned device build check because Linux cannot prove Xcode compatibility.

Release packaging remains a separate manual/tag workflow and does not duplicate on every push.

### 12.4 Full regression

A manual or scheduled full regression runs every portable suite and relevant macOS checks. It is evidence for release/handoff preparation, not a cost imposed on documentation commits.

### 12.5 Secret scanning

Gitleaks retains full generic secret detection. The exact synthetic fixture is allowlisted narrowly by path and fingerprint or replaced with a deterministic generated fixture that cannot resemble a live generic key. No repository-wide rule suppression is allowed.

## 13. Handoff contract

Every completed POC uses:

```text
artifacts/<poc>/<short-commit>/
```

The handoff includes:

- concise implementation summary;
- exact numbered hardware test steps and expected observations;
- automated, CI, provider-smoke, and hardware evidence labels;
- IPA and RPK paths when built;
- file sizes and SHA-256 hashes;
- explicit reason for every missing artifact;
- stable stop conditions and recovery instructions;
- relevant sanitized run IDs or sample-run paths.

Binary artifacts and raw test runs remain ignored. The committed handoff record contains no secret, peripheral UUID, raw capture, provisioning material, or unredacted location trace.

## 14. Security and privacy

- Xiaomi AuthKey, Vietmap keys, Apple credentials, provisioning profiles, and private signing material never enter source control, logs, run exports, or CI artifacts.
- The locally remembered BLE peripheral identifier stays in configuration storage and is excluded from committed handoffs.
- Exact coordinates and traces are local diagnostic data. A shared export uses a named fixed test scene or redacts location.
- Cache identity and payload hashes never include raw key text.
- Replay payload retention is opt-in and local.
- Provider-call budgets are explicit and finite.

## 15. Definition of done for the hybrid decision

The hybrid-renderer investigation is complete only when:

- P0 and P1 pass their automated gates;
- raster baseline and optimized raster have named hardware results;
- synthetic vector has a measured accepted or rejected primitive range;
- real Vietmap vector is either hardware-measured or rejected with a concrete documented boundary;
- both candidates use the same approved navigation content;
- the P2 decision records stability, time, readability, bytes, messages, and failure evidence;
- one renderer is selected for P3–P6;
- the selected renderer has a complete immutable handoff with IPA/RPK identities when available.

Failure to prove vector does not fail the project. It selects optimized raster. Failure of both candidates stops wider-map and routing work until the Band display boundary is simplified.

## 16. Primary references

- [Xiaomi Vela components](https://iot.mi.com/vela/quickapp/en/components/)
- [Xiaomi Vela chart component](https://iot.mi.com/vela/quickapp/en/components/basic/chart.html)
- [Xiaomi Vela cross-device samples](https://iot.mi.com/vela/quickapp/en/samples/)
- [Xiaomi Smart Band 10 screen adaptation](https://iot.mi.com/vela/quickapp/en/guide/multi-screens/)
- [Vietmap Static Map](https://maps.vietmap.vn/docs/map-api/static-map-version/static-map/)
- [Vietmap Tilemap](https://maps.vietmap.vn/docs/map-api/tilemap/)
- [Vietmap API key registration](https://maps.vietmap.vn/docs/map-api/console/register-api-key/)
- [Vietmap API key management](https://maps.vietmap.vn/docs/map-api/console/manage-api-key/)
