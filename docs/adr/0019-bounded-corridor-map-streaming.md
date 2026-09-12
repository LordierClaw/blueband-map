# 0019 — Bounded corridor map streaming

Status: released in iOS 0.5.21 / Band 0.6.16; device feedback reports insufficient cadence. Follow-up repair in progress; near-realtime hardware acceptance is not met.

## Decision

Keep the current 212×520 full-frame bootstrap/recovery path and unchanged Xiaomi framing, authentication, segmentation and ACK bytes. A new application-level capability handshake enables raster-cell movement only on an updated peer. A generic unknown-topic ACK does not enable streaming.

Each camera epoch uses the confirmed full map's projection, zoom, heading and top-left origin. Cells are 128×128 PNGs at integer `(column,row)` coordinates in that plane. The fixed cursor remains at (106,374). Small absolute translation updates move the mosaic beneath it. A change of route, zoom or significant heading uses a new confirmed full frame and epoch; files from different epochs cannot compose together. Route/HUD/destination registration must use that same camera and translation.

Demand priority: current viewport, then one viewport shifted along the forthcoming route by at most one cell, then nothing. Do not fetch all neighboring directions. iOS keeps a latest-only request and one cell transfer, using the verified transport window of four; navigation messages remain independent. Band computes coverage itself and pins the current and requested viewport. No blank viewport is promoted; missing/decode-failed cells retain the last complete frame.

Missing forward-margin files precede recoloring already-visible route pixels.
Otherwise a new GPS fix arriving during each recoloring transfer repeatedly
restarts the latest-only drain before it reaches prefetch. Guidance/translation
remain independent; route recoloring uses any capacity left after coverage.

The cell worker must not await completion of the latest-only view worker: when
view ACK latency exceeds GPS cadence, that worker may never drain. Band pins
coverage as each message is admitted; files may safely arrive before the first
view without promoting an incomplete viewport. Cell admission and decode ACKs
remain required.

The iPhone preview uses the same confirmed viewport and sent cell images in a
native clipped SwiftUI stack. It does not re-encode a full PNG or call Map APIs
for translation. Its image cache follows the admitted Band cells (at most 30),
plus the last complete published viewport (at most 18 references, which may
overlap). Keep that complete preview until replacement coverage is available;
clear epoch cache on invalidation and the published preview on Stop or a newly
confirmed full frame. Phone-only publications pause while inactive/backgrounded
and catch up from current coverage on returning active. No background GPU work
is added to cell rendering.

## Bounds and ownership

- Normal file cache: at most 30 PNGs, each at most 8192 bytes. At most one additional file is being written/retired. Cleanup failure blocks further cell admission until resolved.
- A viewport intersects at most 18 cells. Current plus staging image nodes are capped at 24 (1.5 MiB of RGBA pixel data, excluding native decoder overhead). The full-frame fallback can additionally require about 431 KiB. These are application bounds, not measured device RAM usage.
- Only resident nodes count as decoded. Removing an image node invalidates its decoded flag even when its compressed file stays cached. Vela resource reclamation, including native image caching, needs device verification.
- Coordinate offsets are integral and bounded to ±32768 pixels; sequence is 0...2147483647. A move over one cell from a visible viewport or over the decode-node budget requests a fresh full frame instead of speculative allocation.
- Stop, disconnect, new confirmed full frame and close retire the epoch. A recovery close with `retain:true` freezes only the last decoded viewport, discards staging/prefetch, and rejects further updates to that epoch. The next confirmed full frame retires those frozen images; this avoids flashing the initial snapshot while the new camera loads. Late write/decode/delete callbacks must not mutate another epoch. Delete only owned `cell-` files, never directories or provider caches.
- On startup, list the app's files and remove only canonical `cell-*.png` files before accepting a stream. A failed list or deletion keeps streaming disabled; the existing full-frame path remains available.
- A cell key identifies a region, not immutable pixels. The SHA-256 identifies its content. Route-progress changes may replace a cell: retain the old decoded URI until the new URI completes, then retire the old file. Both versions count toward the file/resident bounds. Vela list identity is the URI, not the shared cell key.

Available pending files must mount for decoding even if another file in the target
viewport is missing. Promotion still requires every target file to be decoded.
Waiting to mount until all files arrive creates a circular wait: iOS awaits a
visible replacement's decode reply before sending the missing entering row, while
Band awaits that row before decoding the replacement. The actual-page regression
reproduces this ordering and preserves the old map until full coverage is ready.

## Independent application vectors

These are new application messages, not proprietary captures. All use the existing v1 envelope with unique IDs and the existing ACK mechanism.

```json
{"topic":"map.stream.open","body":{"scene":"scene-1","epoch":"epoch-1","version":1}}
{"topic":"map.stream.ready","body":{"scene":"scene-1","epoch":"epoch-1","version":1,"cellSize":128,"maximumFiles":30,"maximumResident":24}}
{"topic":"map.stream.view","body":{"epoch":"epoch-1","seq":1,"x":0,"y":0}}
{"topic":"map.stream.state","body":{"epoch":"epoch-1","seq":1,"displayedSeq":-1,"missing":["0:0","1:0","0:1","1:1","0:2","1:2","0:3","1:3","0:4","1:4"],"code":"ok"}}
{"topic":"map.stream.close","body":{"epoch":"epoch-1"}}
{"topic":"map.stream.view","body":{"epoch":"epoch-1","seq":2,"x":0,"y":4,"destinationMode":"visible","destinationX":106,"destinationY":290}}
{"topic":"map.stream.close","body":{"epoch":"epoch-1","retain":true}}
```

Cell transfer contract: `map.cell.begin` carries `epoch`, `cell` (canonical signed decimal `column:row`), `bytes` and lowercase SHA-256. `map.cell.chunk` carries `epoch`, `cell`, integral `offset` and base64 `data`; chunks are 216 bytes except the final chunk. `map.cell.end` carries `epoch` and `cell`. Verify size, coverage, digest, PNG signature/IHDR dimensions before writing or decoding. `map.cell.result` reports stored/error and `request`, the exact begin (cached hit) or end (completed write) command ID; a stale result cannot complete another transfer. Report the evicted key so iOS does not assume a discarded file is resident; a replaced version of the same key is not an eviction. A displayed view is acknowledged only after all its image callbacks succeed, independently of stored results.

`map.cell.decoded` carries `epoch`, `cell`, and the decoded content's `sha256`. Visible replacements wait for that exact content (or a newer confirmed viewport that no longer mounts the cell) before admitting another replacement. A file-write ACK is not a native decode signal. Optional view destination fields use the existing navigation safe-mask validation and promote atomically with the matching viewport; delayed guidance messages cannot move the destination back onto an old camera.

Cell admission replies `map.cell.result status=accepted` for the exact begin command before any payload is sent. A native write/delete still in progress replies `error/busy`; the phone retries admission with fresh command IDs every 100 ms, bounded by the transfer timeout. It does not queue payload into an unaccepted transfer or reset a working map for transient file cleanup.

The iOS CPU renderer retains two 512-pixel base atlases, each rendered with a 128-pixel gutter at 2x (18 MiB retained RGBA, plus at most one in-flight atlas). Source MVT cache remains 16 tiles / 24 MiB, with at most four concurrent HTTP requests. All cells use the same epoch zoom/heading and geometry-anchored labels. Route pixels are composed after cropping; only cells intersecting the changed traveled path plus an 8-pixel stroke margin need recoloring. Cached file hashes suppress byte-identical retransfers. No GPU work is introduced into the locked-screen path.

## Required acceptance

Automated: negative cell coordinates, exact edges, continuous multi-cell route playback, pinning/eviction and bounded resident nodes, corruption/oversize/out-of-order chunks, stale scenes/sequences/callbacks, cancellation and cleanup failure, no full-frame reload for movement inside cached coverage, forward-prefetch priority, shader-free iPhone background rendering, and old-peer fallback.

Hardware: correct clipping and native release of detached image nodes, bounded RAM/file count on a long journey, current-version roundabout icon on the frozen route, map/route/cursor/destination alignment near turns, notifications and Band blur/resume, locked-iPhone GPS, GPS-to-visible offset latency and frame gaps. Target approximately one second for cached-cell movement; full-frame recovery and cold-cache loading must be measured separately. Do not assert success from compilation or simulator callbacks.

Vela documents image list rendering and 2D transforms, but does not support CSS transition on transform. Do not assume browser animation or memory behavior: [list rendering](https://iot.mi.com/vela/quickapp/en/guide/start/user-interface.html), [animation restrictions](https://iot.mi.com/vela/quickapp/en/components/general/animation-style.html).
