# Snapshot route-map application protocol v1

This protocol is above the unchanged Xiaomi transport and application envelope v1.

## Asset contract

| Field | Value |
|---|---|
| Renderer / MIME | `raster` / `image/png` |
| Format version | `1` |
| Dimensions | `212×520` |
| Payload | `1…8,192` bytes |
| Primitives | `0` |
| Envelope ceiling | 512 encoded bytes |
| Transfer window | 1, 2, or 4 application ACKs |

The iPhone sends `render.prepare` and waits for matching `render.ready`; then sends ordered `map.asset.begin`, windowed `map.asset.chunk` messages, and ordered `map.asset.end`. Each chunk has a unique message ID and the exact next byte offset. Base64 chunk size is selected from the real encoded envelope, not a fixed data size.

Run ID, scene ID, asset ID, total bytes, dimensions, format, SHA-256, offsets, and primitives must match the prepared generation. A wrong offset, stale run/scene, invalid Base64, overflow, timeout, digest mismatch, disconnect, or file failure aborts the generation. Duplicate message IDs are ACKed without applying twice.

The Band preallocates one bounded buffer, validates the complete SHA-256, writes a new URI, and exposes it as a pending image. `render.result(status=ok)` is emitted only after the image completion callback atomically promotes it. Until then the prior confirmed URI remains visible. Image failure deletes the pending URI and preserves the confirmed one.

## Navigation update

`nav.update` retains the existing bounded fields: confirmed `scene`, monotonic `seq`, `x/y`, maneuver, distance, street, and status. It is sent no faster than 1 Hz; while one update awaits an ACK, only the newest pending update is retained. Coordinates are inside 212×520.

Normal `navigating` status text is hidden. `gpsLow`, `limitedMap`, `rerouting`, and `arrived` remain visible; asset preparation/publication uses `LOADING MAP`.

## Security and diagnostics

The protocol never carries Vietmap keys. Diagnostics may contain bounded durations, byte/count values, palette size, retained layer counts, cache state, window size, ACK percentiles, and stable error codes. They must omit keys, exact locations, full device identifiers, raw captures, encrypted data, nonces, signing material, and credentials.
