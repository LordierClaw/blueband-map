# Live route-card protocol v1

These topics sit above the verified application envelope and do not alter the
Xiaomi wire protocol.

## Render contract

- viewport: `212×360`
- renderer: `raster`
- format: `image/png`
- format version: `1`
- payload: `1…1,024` bytes
- primitives: `0`
- application envelope: at most `512` encoded bytes
- data chunks: at most `7`

`render.prepare` declares `runId`, `sceneId`, dimensions, SHA-256, and the
fixed raster contract. `render.ready` is required before `map.asset.begin`,
`map.asset.chunk`, and `map.asset.end`. `render.result` reports string status
`ok` or `error` only after Band publication completes.

Asset IDs are `nav-` plus the first 16 lowercase SHA-256 characters. The Band
rejects all other asset prefixes and all unprepared begins.

## Live navigation update

`nav.update` is sent at most once per second and is ACKed even when stale or
invalid. The Band accepts only the confirmed scene and a sequence newer than
the last accepted sequence. `x` and `y` are integer marker coordinates inside
the route-card viewport; `street` is at most 48 UTF-8 bytes.

Maneuvers are `straight`, `left`, `right`, `uTurn`, `roundabout`, `arrive`.
Statuses are `navigating`, `gpsLow`, `limitedMap`, `rerouting`, `arrived`.
While an ACK is pending, the iPhone retains only the newest update.
