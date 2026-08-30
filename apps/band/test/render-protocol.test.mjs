import assert from "node:assert/strict"
import test from "node:test"
import { LIMITS, validateAssetBegin, validatePrepare } from "../src/common/render-protocol.js"

function prepare(overrides = {}) {
  return {
    runId: "h1-run-0123456789",
    sceneId: "scene-0123456789",
    renderer: "vector",
    format: "application/vnd.blueband.map-vector-v1",
    formatVersion: 1,
    width: 212,
    height: 360,
    bytes: 128,
    sha256: "a".repeat(64),
    primitives: 20,
    ...overrides
  }
}

test("prepare validator exposes every stable bounded rejection", () => {
  const cases = [
    [{ renderer: "canvas" }, "unsupportedRenderer"],
    [{ formatVersion: 2 }, "unsupportedFormatVersion"],
    [{}, "busy"],
    [{ bytes: LIMITS.payloadBytes + 1 }, "payloadTooLarge"],
    [{ primitives: LIMITS.maximumPrimitives + 1 }, "tooManyPrimitives"],
    [{ width: 211 }, "invalidDimensions"],
    [{}, "insufficientStorage"]
  ]
  for (const [overrides, expected] of cases) {
    const options = expected === "busy" ? { prepared: {} } :
      expected === "insufficientStorage" ? { availableStorageBytes: 64 } : {}
    const result = validatePrepare(prepare(overrides), options)
    assert.deepEqual(result, { ok: false, code: expected })
  }
})

test("matching prepare admits begin and stale or missing preparation is rejected", () => {
  const body = prepare()
  const result = validatePrepare(body)
  assert.equal(result.ok, true)
  assert.deepEqual(validateAssetBegin({ ...body, run: body.runId, scene: body.sceneId }, result.prepared), { ok: true })
  assert.equal(validateAssetBegin({ ...body, run: body.runId, scene: body.sceneId }, null).code, "notPrepared")
  assert.equal(validateAssetBegin({ ...body, run: "h1-run-stale", scene: body.sceneId }, result.prepared).code, "notPrepared")
})
