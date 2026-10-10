# Automatic navigation smoke and callback containment

## Intent and evidence

The user wants a repeatable test of the complete map path without moving the
phone, with automatic diagnostics, Stop and export preparation. Existing Start
uses device GPS; the Replay measurement picker is only metadata. The supplied
capture contains two unfinished sessions. The installed phone identifies itself
as 0.5.24 (40), while the Band identifies build 31, not the delivered build 34.
The longer session includes 1,041 `map.cell.decoded` messages and only 20 completed
cell transfers. These facts justify a version gate and a repeated-callback
regression test, not a claim that the apparent Band exit was a crash.

## Scope

1. Make completion of an already decoded mounted cell idempotent. Preserve
   valid remounts, replacement files, promotion and late callback ownership.
2. Provide an explicit automatic test button in the iPhone app. It uses a fixed
   public demonstration origin/destination, calls the real route API, follows
   the returned polyline with synthetic timestamped fixes, and uses the normal
   guidance/render/transport/confirmation path. No fake map acknowledgements.
3. Require a matching, complete live Band diagnostic reply before automatic
   playback. Display the actual reported RPK identity on rejection and retain
   the rejected run. A connected/trusted peer alone is not compatible evidence.
4. Replay is an explicit test source. Real CLLocation callbacks cannot mix into
   it, and ending a test restores the real source. No system-wide fake GPS or
   Developer Mode is required. Source metadata is derived from active behavior.
5. Automatically mark startup, movement and changes in course/coverage; retain
   scheduled and emitted timing separately. Cadence is 1 Hz, bounded speed and
   finite duration. Delayed ticks skip stale fixes rather than burst old fixes.
6. At arrival, timeout, error or cancellation, preserve the result, request
   bounded diagnostics when possible, stop local navigation and prepare JSONL
   for a single export action. Export/storage failure remains visible and
   retryable. No new run is required just to export.
7. Keep Stop reachable in a persistent toolbar; noninteractive previews must
   not receive taps. Record Stop intent before cancelling work. Local Stop must
   not wait for a Band reply. Report local stop truthfully: an old Band frame
   is not proof that updates continue, and no unverified remote clear is claimed.

## Boundaries

Do not change Xiaomi transport bytes, crypto, retry windows or ACK formats.
Suppressing redundant application notifications changes no wire schema. Do not
send invented `nav.stop`/clear messages. Automatic replay exercises the app
pipeline and physical Bluetooth/Band, but does not validate Core Location or
force physical Band sleep/exit or iPhone lock. Those remain explicit hardware
cases, never silently marked passed. Compilation is not hardware acceptance.

The fixed demo origin/destination reuse the public coordinate fixture already
in VietmapRouteTests. Do not copy the user's private coordinates or raw trace
into source, commits or CI. Keep analysis artifacts outside the repository.

## Acceptance

- Repeating each image completion 100 times produces one notification per
  actual mount and no reactive array churn after the first completion.
- A remounted/replaced cell still completes; callbacks after destroy/reset
  cannot resurrect a stream or send messages.
- An old/missing/malformed Band version rejects automatic playback with a
  recorded reason and an exportable trace, within the diagnostic deadline.
- A synthetic route moves without CLLocation callbacks, has bounded 1 Hz
  emission and finishes or times out automatically; cancellation cannot emit
  into a later run or restore stale settings.
- The real renderer/transport are used in production; injected test doubles
  only prove deterministic behavior. Start/route/render/ACK timing stays measured.
- Stop remains available while waiting for GPS, transferring, recovering and
  finishing diagnostics. A stopped session records its terminal reason.
- `make test`, iOS simulator tests and `git diff --check` pass before handoff.
  Installation/latency/crash claims await the next correctly identified device
  run; no request for outdoor movement is needed for the automatic smoke.
