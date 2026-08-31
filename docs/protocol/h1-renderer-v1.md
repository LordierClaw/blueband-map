# H1 renderer protocol v1 (historical)

This comparison protocol is retained as test evidence only. Runtime uses the
single raster route-card contract in [route-card-v1](route-card-v1.md).

These are application-envelope topics. They do not modify the Xiaomi wire protocol.

## Common limits

| Field | Contract |
|---|---|
| `runId`, `sceneId` | 1–24 printable ASCII bytes |
| viewport | `width=212`, `height=360` |
| payload | 1–65,536 bytes |
| `sha256` | exactly 64 lowercase hexadecimal bytes |
| format version | integer `1` |
| vector primitives | integer `0` through `60` |

## Topics and bodies

`render.prepare` (iPhone → Band) declares the payload before transfer:

```json
{
  "runId": "h1-run-...",
  "sceneId": "scene-...",
  "renderer": "raster|vector",
  "format": "image/png|application/vnd.blueband.map-vector-v1",
  "formatVersion": 1,
  "width": 212,
  "height": 360,
  "bytes": 1234,
  "sha256": "lowercase-64-hex",
  "primitives": 0
}
```

`render.ready` (Band → iPhone) echoes the accepted run, scene, renderer, format version, dimensions, bytes, and primitive count. It is the sole permission to begin the existing `map.asset.*` transfer.

`render.reject` (Band → iPhone) contains only `runId`, `sceneId`, and one stable `code` from the seven-code rejection set in ADR 0009. It is sent before any payload allocation or asset begin.

`render.result` (Band → iPhone) contains `runId`, `sceneId`, `renderer`, `formatVersion`, `status`, `bytes`, `primitives`, `prepareMs`, `validateMs`, `renderMs`, and `sha256Prefix`. `status` is exactly the string `"ok"` or `"error"`; a JSON Boolean `success` is not part of v1. Failed results may add one bounded `errorCode` with the `ASSET_` prefix. The Band sends one aggregate result rather than per-chunk logs:

```json
{
  "runId": "h1-run-...",
  "sceneId": "scene-...",
  "renderer": "raster|vector",
  "formatVersion": 1,
  "status": "ok",
  "bytes": 1234,
  "primitives": 0,
  "prepareMs": 4,
  "validateMs": 8,
  "renderMs": 12,
  "sha256Prefix": "lowercase-8-hex"
}
```

`render.result` is emitted only after the Band has completed its native publication/cleanup path. A vector failure is terminal for that run; it must not be converted into a raster result.

The bounded status string is intentional at the Vela native interconnect boundary. [Xiaomi's interconnect documentation](https://iot.mi.com/vela/quickapp/en/features/network/interconnect.html) exercises string and number fields, while the device callback crosses a native bridge. Keeping result state string-valued also matches the hardware-proven M1 result convention. Automated fakes must not infer Boolean support merely because JavaScript preserves it in-process.

## Transfer

The existing `map.asset.begin`, `map.asset.chunk`, and `map.asset.end` topics are reused. H1 adds `scene`, `renderer`, `format`, `formatVersion`, and `primitives` to the begin body while retaining `asset`, `bytes`, `mime`, `sha256`, `width`, `height`, and `run`. Chunks remain Base64 inside the 512-byte envelope, the iPhone sends at most one unacknowledged application message at a time, and a run is rejected locally if it would require more than 60 data chunks.

## Evidence boundary

The protocol tests prove exact JSON fields, SHA and identifier validation, envelope size, payload reconstruction, the 60-chunk transfer gate, and vector limits through 60 records. They do not prove that a current Smart Band 10 firmware creates 60 vector nodes or renders either mode at a useful rate. Those claims require the H1 hardware packet and explicit owner feedback.
