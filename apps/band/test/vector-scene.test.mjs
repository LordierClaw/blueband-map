import assert from "node:assert/strict"
import test from "node:test"
import { decodeBBMV, sceneToNativeSegments } from "../src/common/vector-scene.js"

function writeUInt16(bytes, offset, value) {
  bytes[offset] = value & 0xff
  bytes[offset + 1] = (value >> 8) & 0xff
}

function writeUInt32(bytes, offset, value) {
  bytes[offset] = value & 0xff
  bytes[offset + 1] = (value >> 8) & 0xff
  bytes[offset + 2] = (value >> 16) & 0xff
  bytes[offset + 3] = (value >> 24) & 0xff
}

function bbmv(segmentCount = 8, overrides = {}) {
  const roadCount = overrides.roadCount ?? segmentCount
  const routeCount = overrides.routeCount ?? 0
  const bytes = new Uint8Array(22 + (roadCount + routeCount) * 9)
  bytes.set([0x42, 0x42, 0x4d, 0x56, 1])
  writeUInt16(bytes, 5, overrides.width ?? 212)
  writeUInt16(bytes, 7, overrides.height ?? 360)
  bytes[9] = roadCount
  bytes[10] = routeCount
  writeUInt16(bytes, 11, overrides.currentX ?? 106)
  writeUInt16(bytes, 13, overrides.currentY ?? 180)
  writeUInt16(bytes, 15, overrides.heading ?? 90)
  bytes[17] = overrides.maneuver ?? 0
  writeUInt32(bytes, 18, overrides.distance ?? 120)
  for (let index = 0; index < roadCount + routeCount; index += 1) {
    const offset = 22 + index * 9
    writeUInt16(bytes, offset, 8 + index)
    writeUInt16(bytes, offset + 2, 12 + index)
    writeUInt16(bytes, offset + 4, 20 + index)
    writeUInt16(bytes, offset + 6, 20 + index)
    bytes[offset + 8] = index >= roadCount ? 2 : (index % 2)
  }
  return bytes
}

test("decodes the exact BBMV header and bounded scene records", () => {
  const result = decodeBBMV(bbmv(8, { routeCount: 2 }))
  assert.equal(result.ok, true)
  assert.equal(result.scene.segments.length, 10)
  assert.equal(result.scene.roadSegmentCount, 8)
  assert.equal(result.scene.routeSegmentCount, 2)
  assert.deepEqual(result.scene.currentPosition, { x: 106, y: 180 })
  assert.equal(result.scene.heading, 90)
  assert.equal(result.scene.distanceMeters, 120)
})

test("accepts 8, 20 and 40 records but rejects the 41-record boundary", () => {
  for (const count of [8, 20, 40]) {
    const result = decodeBBMV(bbmv(count))
    assert.equal(result.ok, true)
    assert.equal(result.scene.segments.length, count)
  }
  assert.deepEqual(decodeBBMV(bbmv(41)), { ok: false, code: "tooManySegments" })
})

test("rejects malformed BBMV without allocating a scene", () => {
  const cases = [
    ["invalidMagic", bytes => { bytes[0] = 0; return bytes }],
    ["unsupportedVersion", bytes => { bytes[4] = 2; return bytes }],
    ["invalidLength", bytes => bytes.slice(0, -1)],
    ["invalidViewport", bytes => { writeUInt16(bytes, 5, 211); return bytes }],
    ["outOfViewport", bytes => { writeUInt16(bytes, 11, 212); return bytes }],
    ["invalidHeading", bytes => { writeUInt16(bytes, 15, 360); return bytes }],
    ["invalidManeuver", bytes => { bytes[17] = 5; return bytes }],
    ["invalidSegmentClass", bytes => { bytes[30] = 9; return bytes }]
  ]
  for (const [code, mutate] of cases) {
    const bytes = mutate(bbmv(1))
    assert.deepEqual(decodeBBMV(bytes), { ok: false, code })
  }
})

test("converts each accepted segment once to a bounded native style", () => {
  const result = decodeBBMV(bbmv(8, { routeCount: 2 }))
  const segments = sceneToNativeSegments(result.scene)
  assert.equal(segments.length, 10)
  assert.equal(segments.filter(segment => segment.color === "#5dffb0").length, 2)
  assert.ok(segments.every(segment => segment.width >= 1 && segment.width <= 212))
  assert.ok(segments.every(segment => segment.style.includes("position:absolute")))
})
