# Live Background Navigation Guidance Design

**Date:** 2026-09-02
**Status:** Approved

## Goal

Keep the accepted heading-up Vietmap raster, route, self marker, and destination marker unchanged while making maneuver guidance correct and live, removing the artificial turn dot, and sustaining coalesced map refreshes while the iPhone is locked.

## Confirmed baseline

- `main` is clean at `5ab4fcd19b5c4364f70dc8b819446ba3cd29e210`.
- Source versions are iOS `0.5.8 (24)` and RPK `0.6.10 (25)`.
- The hardware report confirms that map rotation, route geometry, self marker, and destination marker are visually accepted.
- The supplied debug export was captured during `state=transferring` and ends midway through instruction 6, so it proves the provider instruction shape but does not prove any moving/background update.

## Root causes

### Maneuver and street mismatch

Vietmap Route v4 defines an instruction's `distance` as the distance covered until the following instruction, while `street_name` is the street entered by that instruction. The wearable header must therefore pair the current instruction's remaining distance with the following instruction's maneuver and street.

The current selector finds the active instruction solely with `interval.upperBound > matchedSegmentIndex`. The observed response contains zero-length and overlapping intervals such as `0...0`, `0...1`, and repeated `1...1`. At route start this skips the `straight / 37 m` instruction and pairs 37 m with a later left turn. Progress and instruction boundaries must instead use cumulative route distance, with interval geometry retained only as a camera hint.

Street names are currently copied without trimming. Normalize provider whitespace once when constructing `RouteInstruction`.

### Frozen header during map refresh

The Band already resolves maneuver images dynamically from `body.maneuver`. During a refresh, however, `render.prepare.preview` replaces the visible header and subsequent `nav.update` messages for the confirmed scene are only saved for rollback. Since a refreshed JPEG takes several seconds to render and transfer, this freezes the visible maneuver for most of continuous navigation.

The first map keeps its staged preview. A refresh with a confirmed map keeps showing live `nav.update` guidance until the new scene is confirmed. The protocol body and topic set do not change.

### Artificial blue turn dot

`VietmapRouteOverlay.draw` explicitly strokes a 9 px ellipse at `nextManeuver`. Remove that command. Keep round line caps/joins and the accepted active route geometry, so bends remain ordinary connected route corners.

### No locked-iPhone updates

The application is explicitly foreground-only, has no `UIBackgroundModes`, and uses a 12-second/175-metre snapshot threshold. iOS can therefore suspend both location processing and Bluetooth work after lock.

An active navigation session will enable Core Location background activity and declare `location` plus `bluetooth-central`. Prewarming remains foreground-only. Starting navigation owns the background session; stopping navigation releases it. This covers ordinary lock/background navigation, not force-quit or guaranteed relaunch after OS termination.

## Refresh and rotation contract

- Marker remains fixed at `(106, 374)` with heading bucket `0`.
- Every snapshot is rendered by iOS with the latest coalesced `bearingDegrees`; the bitmap itself is heading-up before JPEG encoding.
- A course change of at least 30 degrees or matched movement of at least 1 metre becomes refresh-eligible after 1 second.
- Only one snapshot render/transfer may be active. New GPS fixes replace one pending request; after a turn or U-turn the pending request therefore contains the newest route progress and bearing.
- The next completed scene is atomically published. No partial map or overlay is exposed.
- `RenderProtocol.formatVersion`, all message topics/bodies, `212x520` dimensions, maximum payload `8192`, ACK/window behavior, Xiaomi transport bytes, and authentication remain unchanged.
- The hardware target is a displayed refresh based on a recent GPS fix within 5 seconds while navigation is active and iOS continues background execution. This is a hardware acceptance target, not a simulator guarantee.

## RPK idle interface

The RPK no longer exposes the echo log, `ECHO PING`, or `CLEAR EVENTS` controls. Before interconnect is ready it shows the existing loading/connection screen. Once ready and before a navigation command, it shows a clean `CHỜ LỆNH TỪ IPHONE…` state. The internal `system.echo` protocol handler remains for compatibility and diagnostics; only its user-facing screen is removed.

## Versions and handoff

Both installed components change:

- iOS `0.5.9 (25)`
- RPK `0.6.11 (26)`

The IPA is built only by GitHub Actions. Final handoff deletes the stale `0.5.7/0.6.9` files from `artifacts/handoff` and keeps only the new IPA, RPK, checksums, and Vietnamese manual test guide.

## Verification boundary

Automated checks prove selection semantics, whitespace normalization, no maneuver ellipse, refresh/heading thresholds, unchanged render/navigation contracts, RPK live-header behavior, background metadata, package integrity, and payload rejection. Only a real iPhone plus Xiaomi Smart Band 10 can accept locked-screen latency, continuous BLE delivery, map rotation after turns/U-turns, and visual behavior.

## Primary references

- [Vietmap Route v4](https://maps.vietmap.vn/docs/vi/map-api/route-version/route-v4/)
- [Vietmap iOS navigation progress and reroute events](https://maps.vietmap.vn/docs/vi/sdk-mobile/sdk-ios/navigation/)
- [Apple background location updates](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [Apple Core Bluetooth background processing](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
