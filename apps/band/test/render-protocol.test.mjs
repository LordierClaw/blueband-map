import assert from "node:assert/strict"
import test from "node:test"
import { LIMITS, validateAssetBegin, validatePrepare } from "../src/common/render-protocol.js"

function prepare(overrides = {}) {
  return {
    runId: "nav-run-0123456789",
    sceneId: "scene-0123456789",
    renderer: "raster",
    format: "image/png",
    formatVersion: 1,
    width: 212,
    height: 520,
    bytes: 128,
    sha256: "a".repeat(64),
    primitives: 0,
    ...overrides
  }
}

test("prepare validator exposes every stable bounded rejection", () => {
  assert.equal(LIMITS.width, 212)
  assert.equal(LIMITS.height, 520)
  assert.equal(LIMITS.payloadBytes, 8192)
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
  assert.equal(validateAssetBegin({ ...body, run: "nav-run-stale", scene: body.sceneId }, result.prepared).code, "notPrepared")
})
