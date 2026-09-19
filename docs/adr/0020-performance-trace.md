# 0020 — Bounded performance measurements

Status: implemented for local verification; hardware timing and memory acceptance pending.

## Decision

Preserve Xiaomi framing, authentication, segmentation, ACKs, error 204 handling,
hash checks, transfer scheduling and publication ownership. Add optional application
`body.perf` objects with `v:1` to existing Band replies. Old peers can ignore them.
No payload/chunk logging, periodic probes, extra rendering or sampling timers.

Every duration uses two observations of the Band's own `Date.now()`. Never
subtract a Band timestamp from an iPhone timestamp. The sampled Band wall clock
is not a proven monotonic clock: an observed regression makes `clockValid:false`
sticky for the lifetime of the page, and subsequent duration fields are `null`.
A missing endpoint or duration outside 0...60000 ms is also `null`, never a
fabricated zero. Integer zero is otherwise a valid measured duration. Missing
optional fields mean unavailable telemetry, not zero work.

## Stage definitions

| Existing reply | Optional `perf` fields | Meaning |
| --- | --- | --- |
| `map.cell.result` | `v,clockValid,writeMs` | Start of native `file.writeArrayBuffer` call to its first completion/failure callback. Only an attempted native write has this field; cached/accepted replies do not invent a sample. |
| `map.cell.decoded` | `v,clockValid,decodeMs` | Mounting that URI in the page's image list to the first owned image-complete callback. Includes UI scheduling and native image work; it is not a pure decoder CPU benchmark or panel scanout timestamp. Duplicate callbacks retain existing reply behavior but carry no second decode measurement. |
| `map.stream.state` | `v,clockValid,applyMs,files,nodes,pendingDeletes,inFlight,nativeMemory` | JavaScript request/promotion and image/navigation property assignment, then a resource snapshot. `seq`/`displayedSeq` in the existing body identify requested/published state. A missing-cell state does not prove display. |
| `render.result` | `v,clockValid,writeMs,decodeMs,applyMs,cleanupMs` | Native full-file write; pending image mount to owned complete/error callback; synchronous JS publication/rollback; then the wait for prior/failed full-file retirement before the result. |

Full-frame `prepareMs`, `validateMs`, and `renderMs` retain their legacy meanings
for compatibility. In particular, `validateMs` includes transfer and writing, and
`renderMs` includes cleanup. They must not be relabeled as write/decode timings.
Image callback measurements establish native callback arrival, not visible panel
latency. A full-frame failure before mounting has `decodeMs:null`.

`files` counts distinct cell URIs owned by the page: cached records, old and
staging versions, known retired garbage, and a current write URI. It excludes
the separate full-frame PNG and is not an OS filesystem census. `nodes` is the
current mounted cell list, bounded by the existing 24-node limit; the separate
full-frame fallback may remain mounted. `pendingDeletes` counts native deletions
currently awaiting callbacks, including full frames. `inFlight` counts active
cell/full-frame pipelines (including the pending image callback), not chunks.
`nativeMemory:null` explicitly means Vela decoder/cache memory is not measured.
Failed/stale callbacks keep their existing ownership and cleanup guards.

Only one latest full-frame timing aggregate is retained. Each mounted cell owns
one timing record, discarded when its URI unmounts; remounting starts a new
sample. No history grows with journey length.

## Diagnostics and filming

`diagnostics.get` keeps its existing `body.request` correlation token
(`[a-z0-9-]{1,32}`). Its report adds `versionName`, `perfVersion:1`, and the current
resource `perf`; the existing numeric `rpk` is the actual build code. The
self-contained page's `rpkVersion`/`rpkBuild` constants must match the manifest;
an actual-page test enforces this on every version bump. No custom page imports
or new native module-loader dependencies are introduced.

Optional `body.render:true` returns the latest full-frame `perf` instead of
resources, useful if the regular result omitted optional measurements for size.
Before any full-frame result, it returns resources. Use separate bounded requests
when both snapshots are needed. Replies contain no file paths, route coordinates,
payloads or retained identifiers.

Optional `body.visual:true` enables a small filming label, default off and reset
off on disconnect/lifecycle reset. `visual:false` disables it. `v<displayedSeq>`
changes with the published stream viewport; `f<last-six-scene-characters>` marks
a confirmed full frame. The label does not advance for incomplete coverage and
uses the existing publication updates; it adds no production loop. Film the
label together with the map to independently verify visible cadence.

## Envelope bounds and independent vectors

All extended replies fit the existing 512-byte UTF-8 reply envelope. Optional
fields are shed, only when required, in this order: `nativeMemory`,
`pendingDeletes`, `inFlight`, `files`, `nodes`, `cleanupMs`, `writeMs`, `decodeMs`,
`applyMs`, then the whole `perf`. Existing status, missing-cell lists, hashes,
request correlation and ACK fields are never shortened. The complete most recent
full-frame aggregate remains queryable independently of this trimming.

These literal application vectors are independent of the encoder. Values are
examples, including the build/version, and do not assert current hardware results.
Tests verify the complete encoded messages are at most 512 bytes and survive the
actual page's send path unchanged. A separate actual-page test exercises a
maximum 18-cell missing list with long epoch/sequence values.

```json
{"v":1,"id":"d-start","src":"ios","type":"message","topic":"diagnostics.get","body":{"request":"perf-start","visual":false}}
{"v":1,"id":"b-1000-1","src":"band","type":"message","topic":"diagnostics.report","body":{"request":"perf-start","rpk":32,"versionName":"0.6.17","perfVersion":1,"phase":"none","offset":-1,"received":0,"sendCode":0,"perf":{"v":1,"clockValid":true,"files":0,"nodes":0,"pendingDeletes":0,"inFlight":0,"nativeMemory":null}}}
{"v":1,"id":"b-1017-2","src":"band","type":"message","topic":"map.cell.result","body":{"epoch":"e1","cell":"0:0","status":"stored","code":"ok","evicted":[],"request":"ce-0:0","perf":{"v":1,"clockValid":true,"writeMs":17}}}
{"v":1,"id":"b-1040-3","src":"band","type":"message","topic":"map.cell.decoded","body":{"epoch":"e1","cell":"0:0","sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","perf":{"v":1,"clockValid":true,"decodeMs":23}}}
{"v":1,"id":"b-1045-4","src":"band","type":"message","topic":"map.stream.state","body":{"epoch":"e1","seq":9,"displayedSeq":9,"missing":[],"code":"ok","perf":{"v":1,"clockValid":true,"applyMs":5,"files":12,"nodes":10,"pendingDeletes":0,"inFlight":0,"nativeMemory":null}}}
{"v":1,"id":"b-1190-5","src":"band","type":"message","topic":"render.result","body":{"runId":"run-1","sceneId":"scene-1","renderer":"raster","formatVersion":1,"status":"ok","bytes":4096,"primitives":0,"prepareMs":20,"validateMs":117,"renderMs":73,"sha256Prefix":"01234567","perf":{"v":1,"clockValid":true,"writeMs":17,"decodeMs":23,"applyMs":5,"cleanupMs":45}}}
{"v":1,"id":"b-900-6","src":"band","type":"message","topic":"map.cell.result","body":{"epoch":"e1","cell":"0:0","status":"stored","code":"ok","evicted":[],"request":"ce-0:0","perf":{"v":1,"clockValid":false,"writeMs":null}}}
```

## Acceptance

Local actual-page checks: asynchronous write/decode/delete separation; staged
version counting; first-callback-only decode measurement; clock regression;
metadata/manifest equality; default-off filming; reply size including maximal
missing coverage; existing callback ownership, error 204 and atomic map tests.
The normal RPK build must retain its firmware-safe empty custom-module table.

Hardware cases: full PNG write versus image callback versus delayed deletion;
cached stream translation versus entering-cell decode; replacement plus missing
entering row; 24-node/30-file bounds during a long journey; failed deletion and
disconnect/reconnect; locked iPhone and Band blur/resume; optional filming label
versus actual map motion. Verify the receiver still accepts every reply under
the 512-byte cap. Record native memory as unavailable until a supported device
measurement exists. Neither compilation nor deterministic callbacks establish
visible latency, native memory reclamation, or hardware acceptance.
