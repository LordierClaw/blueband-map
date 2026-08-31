# ADR 0011: Vietmap SDK snapshot route map

**Status:** Accepted  
**Date:** 2026-08-31  
**Scope:** Foreground motorcycle navigation on iPhone and Xiaomi Smart Band 10

## Decision

Render one 212×520, scale-1, zero-pitch, heading-up map on iPhone with the official `VietMap` package pinned to revision `649eabcb21a36c3d0cfd871c07ccea641924fcdd`. The adapter removes nonessential style layers after style load, then draws the traveled route, upcoming halo/fill, and next maneuver with Core Graphics in the SDK snapshot overlay.

Reduce the snapshot to a native 8-bit indexed PNG using fixed 32- or 16-color palettes. Admit only payloads at or below 8,192 bytes. The Band displays the image full-screen, keeps maneuver text and the moving position marker native, and retains the previously confirmed image until the replacement image has decoded successfully.

Foreground location prewarms on the navigation screen. A cached fix is reusable only at accuracy 0–25 m and age 0–10 seconds. A map refresh occurs only when the marker leaves the safe viewport, the maneuver context changes, rerouting succeeds, or the maneuver falls outside the current zoom. Pending location input keeps only the newest fix.

The application transfer supports acknowledgement windows 1, 2, and 4; begin and end remain ordered barriers. Window 1 is the default until hardware measurement selects another value.

## Boundaries and consequences

The previous tile/line route-card implementation remains compilable as historical POC evidence but is no longer composed by the app. There is no fallback to it when SDK rendering or PNG admission fails. A first-map failure is terminal; a refresh failure preserves the confirmed map and reports `LIMITED MAP`.

No Xiaomi FE95/5E/5F, SPP framing, authentication, encryption, ThirdPartyApp, TOFU, transport ACK, or verified wire byte changes. Tiled Band composition, traffic, terrain, satellite, 3D, POIs, free pan, and free zoom remain deferred. Simulator and deterministic tests do not establish hardware timing, readability, or stability.
