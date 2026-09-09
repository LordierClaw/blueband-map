# 0019 — Bounded corridor map streaming

Status: implementation in progress; not released or hardware-accepted.

## Decision

Keep the current 212×520 full-frame bootstrap/recovery path and unchanged Xiaomi framing, authentication, segmentation and ACK bytes. A new application-level capability handshake enables raster-cell movement only on an updated peer. A generic unknown-topic ACK does not enable streaming.

Each camera epoch uses the confirmed full map's projection, zoom, heading and top-left origin. Cells are 128×128 PNGs at integer `(column,row)` coordinates in that plane. The fixed cursor remains at (106,374). Small absolute translation updates move the mosaic beneath it. A change of route, zoom or significant heading uses a new confirmed full frame and epoch; files from different epochs cannot compose together. Route/HUD/destination registration must use that same camera and translation.

Demand priority: current viewport, then one viewport shifted along the forthcoming route by at most one cell, then nothing. Do not fetch all neighboring directions. iOS keeps a latest-only request and one cell transfer, using the verified transport window of four; navigation messages remain independent. Band computes coverage itself and pins the current and requested viewport. No blank viewport is promoted; missing/decode-failed cells retain the last complete frame.

## Bounds and ownership

- Normal file cache: at most 30 PNGs, each at most 8192 bytes. At most one additional file is being written/retired. Cleanup failure blocks further cell admission until resolved.
- A viewport intersects at most 18 cells. Current plus staging image nodes are capped at 24 (1.5 MiB of RGBA pixel data, excluding native decoder overhead). The full-frame fallback can additionally require about 431 KiB. These are application bounds, not measured device RAM usage.
- Only resident nodes count as decoded. Removing an image node invalidates its decoded flag even when its compressed file stays cached. Vela resource reclamation, including native image caching, needs device verification.
- Coordinate offsets are integral and bounded to ±32768 pixels; sequence is 0...2147483647. A move over one cell from a visible viewport or over the decode-node budget requests a fresh full frame instead of speculative allocation.
- Stop, disconnect, new confirmed full frame and close retire the epoch. Late write/decode/delete callbacks must not mutate another epoch. Delete only owned `cell-` files, never directories or provider caches.

## Independent application vectors

These are new application messages, not proprietary captures. All use the existing v1 envelope with unique IDs and the existing ACK mechanism.

```json
{"topic":"map.stream.open","body":{"scene":"scene-1","epoch":"epoch-1","version":1}}
{"topic":"map.stream.ready","body":{"scene":"scene-1","epoch":"epoch-1","version":1,"cellSize":128,"maximumFiles":30,"maximumResident":24}}
{"topic":"map.stream.view","body":{"epoch":"epoch-1","seq":1,"x":0,"y":0}}
{"topic":"map.stream.state","body":{"epoch":"epoch-1","seq":1,"displayedSeq":-1,"missing":["0:0","1:0","0:1","1:1","0:2","1:2","0:3","1:3","0:4","1:4"],"code":"ok"}}
{"topic":"map.stream.close","body":{"epoch":"epoch-1"}}
```

Cell transfer contract: `map.cell.begin` carries `epoch`, `cell` (canonical signed decimal `column:row`), `bytes` and lowercase SHA-256. `map.cell.chunk` carries `epoch`, `cell`, integral `offset` and base64 `data`; chunks are 216 bytes except the final chunk. `map.cell.end` carries `epoch` and `cell`. Verify size, coverage, digest, PNG signature/IHDR dimensions before writing or decoding. `map.cell.result` reports stored/error, never equates a file write with display. Report the evicted key so iOS does not assume a discarded file is resident. A displayed view is acknowledged only after all its image callbacks succeed.

## Required acceptance

Automated: negative cell coordinates, exact edges, continuous multi-cell route playback, pinning/eviction and bounded resident nodes, corruption/oversize/out-of-order chunks, stale scenes/sequences/callbacks, cancellation and cleanup failure, no full-frame reload for movement inside cached coverage, forward-prefetch priority, shader-free iPhone background rendering, and old-peer fallback.

Hardware: correct clipping and native release of detached image nodes, bounded RAM/file count on a long journey, current-version roundabout icon on the frozen route, map/route/cursor/destination alignment near turns, notifications and Band blur/resume, locked-iPhone GPS, GPS-to-visible offset latency and frame gaps. Target approximately one second for cached-cell movement; full-frame recovery and cold-cache loading must be measured separately. Do not assert success from compilation or simulator callbacks.

Vela documents image list rendering and 2D transforms, but does not support CSS transition on transform. Do not assume browser animation or memory behavior: [list rendering](https://iot.mi.com/vela/quickapp/en/guide/start/user-interface.html), [animation restrictions](https://iot.mi.com/vela/quickapp/en/components/general/animation-style.html).
