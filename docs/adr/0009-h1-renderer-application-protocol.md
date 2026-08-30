# ADR 0009: H1 renderer application protocol

**Status:** Accepted
**Date:** 2026-08-30
**Scope:** H1 iPhone-to-Band renderer comparison

## Decision

H1 adds a small renderer protocol above the verified BlueBand application envelope. The iPhone explicitly selects one renderer, prepares the Band with bounded metadata, waits for semantic readiness, transfers one payload with the existing stop-and-wait asset flow, and records one aggregate result. Raster and vector are separate test modes; a failed vector run never silently falls back to raster.

The protocol is deliberately bounded:

- viewport: exactly 212×360 pixels;
- payload: at most 64 KiB after encoding;
- vector primitives: 0–40 fixed records;
- application envelope: at most 512 encoded bytes;
- one prepared renderer and one active transfer per run.

The renderer format is either `image/png` for raster or `application/vnd.blueband.map-vector-v1` for the fixed-record vector scene. Every message carries a bounded `runId` and `sceneId`; payload identity is a lowercase SHA-256 digest.

## Sequence

1. The existing authenticated session reaches its current readiness proof.
2. The iPhone builds, hashes, and validates the selected payload locally.
3. The iPhone sends `render.prepare` and does not send asset bytes yet.
4. The Band validates renderer support, format version, dimensions, byte count, primitive count, and available storage.
5. The Band sends `render.ready` or `render.reject`.
6. Only `render.ready` admits `map.asset.begin`, `map.asset.chunk`, and `map.asset.end`.
7. The Band validates and publishes the selected native renderer, then sends one `render.result` containing `prepareMs`, `validateMs`, `renderMs`, and an eight-character SHA-256 prefix.
8. The iPhone closes the run on success, rejection, timeout, cancellation, or disconnect.

Semantic messages may arrive before their transport acknowledgement. The iPhone therefore buffers a matching `render.ready`, `render.reject`, or `render.result` until the corresponding send/transfer operation has completed. A different run or scene is stale and ignored.

The result is emitted only after the Band's publication and cleanup callback has completed. The iPhone accepts an error result only when its code is bounded and asset-scoped (`ASSET_*`). A successful result must match the current asset kind, format version, byte count, primitive count, and hash prefix.

## Stable rejection codes

`unsupportedRenderer`, `unsupportedFormatVersion`, `busy`, `payloadTooLarge`, `tooManyPrimitives`, `invalidDimensions`, and `insufficientStorage` are stable machine-readable codes. They are not replaced by free-form diagnostic text on the wire.

## Consequences

This decision preserves every verified Xiaomi BLE, SPP, authentication, encryption, ThirdPartyApp, and transport-ACK byte. It changes only application topics and payload contracts. Existing cleanup, deduplication, disconnect invalidation, and acknowledged delivery behavior remain required invariants.

The 64 KiB ceiling is a test limit, not a measured Band maximum. H1 automated tests prove serialization, bounds, and ordering only. Compilation and deterministic tests do not prove Smart Band 10 hardware support; hardware runs must measure readiness, transfer, render, readability, hangs, and disconnect recovery.
