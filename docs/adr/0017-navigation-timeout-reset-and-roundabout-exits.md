# 0017 — Acknowledged map reset and explicit roundabout exits

Status: accepted for implementation; physical Band acceptance pending.

## Context

The 0.5.18 hardware summary has a successful 19-command, window-2 transfer taking 4499 ms and fix-to-display 5454 ms. The supplied file stops at 1025 bytes, before its visibility transition. The code's timeout latch prevents further maps until reconnect, including when the Band merely suspended an image-complete callback. Replaying unverified transfer state would be unsafe.

A bounded live Vietmap Route v4 request for the supplied approximate endpoints returned sign 6 with `Tại vòng xoay, rẽ lối rẽ 2 vào đường Nguyễn Khuyến`, heading 0, and no numeric exit/angle property. A single right-exit graphic misrepresents this instruction.

## Decision

Keep the Xiaomi BLE frames, authentication, fragmentation, checksums, ACK retry and image size/format contracts unchanged. Add the following application-level messages using the existing authenticated v1 envelope:

```json
{"v":1,"id":"reset-1","src":"ios","type":"message","topic":"render.reset","body":{"runId":"run-1","sceneId":"scene-1"}}
{"v":1,"id":"band-1","src":"band","type":"message","topic":"render.reset.ready","body":{"request":"reset-1","runId":"run-1","sceneId":"scene-1"}}
{"v":1,"id":"reset-1","src":"band","type":"ack"}
```

These are independently specified application vectors, exercised by the JS receiver and Swift sender tests. They are not captures or new proprietary-wire vectors. Reset is limited to a matching interrupted run/scene, or an idle receiver. A conflicting live run is untouched. Finish outstanding native file I/O before admitting reset, then invalidate asynchronous callback ownership before replying; preserve the last confirmed image. Retrying the exact reset must repeat its ready response as well as the ACK. The phone needs both the matching request reply and command ACK before releasing its timeout latch. A legacy Band that ACKs unknown topics cannot unlock the sender. Disconnects, invalid results and arbitrary send failures remain gated. Navigation coalesces GPS and retries timeouts with the existing cooldown.

Use the already-supported four-command chunk window in navigation (coordinator default stays one). Keep 8 KiB per frame, existing chunk/envelope limits and one map in flight. The 7,416-byte iOS fixture with 500 ms synthetic ACK delay measured 7.726 s / 4.130 s / 2.092 s for windows 1 / 2 / 4. Band replay covers 100 full-size maps with reordered windows 1/2/4 and exact retries. These timings exclude real BLE scheduling and provider work.

Optional `roundaboutExit` is an integer 1–12, accepted only with maneuver `roundabout`, in both `render.prepare.preview` and `nav.update`. It is omitted for unknown exits and other maneuvers, preserving old message bodies. Example preview:

```json
{"maneuver":"roundabout","roundaboutExit":2,"distanceM":80,"street":"Nguyễn Khuyến","x":106,"y":374,"heading":0,"destinationMode":"hidden","destinationX":0,"destinationY":0}
```

Display the neutral Mapbox CC0 roundabout icon with a number in its center. Do not map exit counts to left/straight/right: junctions can have different numbers and angles of exits. Keep street text one line and center it with distance. Both current packages must be installed for the new recovery contract and numbered assets.

## Hardware acceptance

1. At a real straight-through roundabout, verify the provider exit number and absence of a misleading right-exit arrow; unknown exits use a neutral unnumbered icon.
2. Cover the Band with a notification and allow screen sleep during prepare, chunk transfer and image publication. Wake it and verify a reset handshake and newer GPS scene without Start/reconnect. Repeat with iPhone notification/inactive/locked separately.
3. Delay or lose a reset reply/ACK: no new transfer until both arrive; preserve the prior map and reject stale callbacks/conflicting reset identifiers.
4. Compare repeated warm map fix-to-display latency and frame gaps; no payload-too-large or decode regressions. A sleeping Band may suspend its JS app: this change repairs recovery, not a claim that hidden UI renders continuously.

References: [Vela lifecycle](https://iot.mi.com/vela/quickapp/en/guide/framework/script/lifecycle.html), [background running](https://iot.mi.com/vela/quickapp/en/guide/framework/other/background-running.html), [Route v4](https://maps.vietmap.vn/docs/vi/map-api/route-version/route-v4/), [Mapbox directions-icons](https://github.com/mapbox/directions-icons/tree/9016ba92176cf1a8207cc1c4005b951fe49d59cb).
