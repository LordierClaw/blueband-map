# H1 diagnostics, export, and TileMap hotfix design

**Status:** Approved for implementation  
**Date:** 2026-08-30  
**Scope:** iOS-only H1 diagnostic/export behavior and Vietmap vector-tile acquisition

## Evidence and problem statement

Owner hardware still reports `ASSET_RESULT_INVALID` after raster and synthetic-vector transfers complete with the expected byte and primitive counts. The current coordinator collapses schema, phase, and metadata failures into one terminal code, so the available screenshot and sanitized run record cannot identify the failed boundary. The Export button only rewrites a JSON file inside the app sandbox and displays its path; it does not present an iOS Share Sheet.

The saved TileMap key enabled a bounded live trace. Vietmap returned the Default style with HTTP 200 and an inline `openmaptiles` vector source declaring `maxzoom: 15`. The app ignored that source limit, requested z17, and received HTTP 404. The same coordinate at z15 returned HTTP 200 with a 340,726-byte `.pbf` body labelled `text/plain`. The current client rejects that MIME even though the URL and MVT decoder provide stronger validation boundaries.

## Decision

Only the iOS app changes. The Band RPK and H1 application-envelope contract remain unchanged.

### Shareable sanitized diagnostics

After an H1 run has produced `lastH1ExportURL`, the H1 section exposes a SwiftUI `ShareLink` labelled `Export log H1`. Activating it opens the native iOS Share Sheet with the already-sanitized JSON file. While no export URL exists, the same label is visibly disabled and performs no hidden write.

The export remains limited to `RenderRunRecord`: bounded run/scene identities, renderer, event names, aggregate metrics, and payload digest. It must not add AuthKeys, Vietmap keys, BLE UUIDs, URLs, response bodies, or raw interconnect envelopes.

### Result failure classification

The coordinator preserves strict validation but replaces the ambiguous terminal code at three boundaries:

- `RESULT_SCHEMA_INVALID`: a current-run `render.result` cannot be parsed into the exact H1 schema.
- `RESULT_EARLY`: a successful current-run result arrives before the final application message is awaiting acknowledgement.
- `RESULT_METADATA_INVALID`: the parsed result disagrees with the current asset renderer, format version, byte count, primitive count, or non-empty hash prefix.

Legacy Boolean `success` remains invalid and maps to `RESULT_SCHEMA_INVALID`. Stale run or scene results remain ignored. Error results still require a bounded `ASSET_*` error code; an invalid error body maps to `RESULT_SCHEMA_INVALID`.

### Vietmap source zoom and tile response

`VectorTileTemplate` carries optional bounded `minimumZoom` and `maximumZoom` discovered from the selected vector source. Integer values in the inclusive range 0–22 are accepted; absent values leave the requested zoom unchanged. Invalid, non-integral, or contradictory bounds reject the style as provider data.

The H1 asset factory clamps the configured map zoom into the discovered source range before computing x/y and building the tile URL. For the observed Vietmap style, requested z17 therefore becomes z15 and x/y are recomputed at z15.

The tile response accepts the existing vector MIME types. It also accepts `text/plain` only when all of these conditions hold:

- the final request URL is HTTPS on `maps.vietmap.vn` with no user information;
- its path ends in `.pbf` case-insensitively;
- HTTP status is 200 and the body is non-empty and within the existing MVT cap;
- `MapboxVectorTile.decode` succeeds before any scene is produced.

No generic `text/plain` response or foreign-host response is treated as a vector tile.

Provider failures identify the request stage without exposing the request:

- style or TileJSON HTTP failures: `STYLE_HTTP_<status>`;
- final PBF HTTP failures: `TILE_HTTP_<status>`;
- existing MIME/data categories remain bounded and secret-free.

## Testing

Tests are written before production changes and must cover:

1. project/UI source exposes a `ShareLink` using `lastH1ExportURL` and no longer presents a write-only Export button;
2. exact current-run fixtures independently produce schema, early-phase, and metadata terminal codes;
3. style discovery preserves valid min/max zoom, rejects malformed bounds, and leaves absent bounds optional;
4. z17 is clamped to z15 and x/y are computed from z15;
5. Vietmap HTTPS `.pbf` plus `text/plain` is accepted only after MVT decoding, while foreign paths/hosts and invalid bodies remain rejected;
6. style and tile HTTP failures produce separate bounded codes without keys or URLs;
7. all existing Swift, RPK, protocol-lab, metadata, lint, and secret gates remain green.

Hardware acceptance is still required. Automated tests prove classification and client behavior, not Band rendering.

## Artifact and version policy

The iOS production source changes, so the IPA version/build is bumped once. The RPK source does not change, so it remains `0.2.3 (5)` and the tester does not reinstall it. The final flat `artifacts/h1-hybrid/` bundle contains the latest IPA, the unchanged latest RPK for pair identity, `HANDOFF.md`, and `SHA256SUMS`; the handoff explicitly says that only the IPA must be updated.
