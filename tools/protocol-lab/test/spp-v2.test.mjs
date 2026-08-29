import assert from "node:assert/strict"
import test from "node:test"

import { crc16Arc, parseSppFrames } from "../src/spp-v2.mjs"

test("CRC-16/ARC matches the standard check value", () => {
  assert.equal(crc16Arc(Buffer.from("123456789")), 0xbb3d)
})

test("parses a literal frame and masks upper type flags", () => {
  const bytes = Buffer.from("a5a583070400963c01010801", "hex")

  assert.deepEqual(parseSppFrames(bytes), [
    { type: 3, sequence: 7, payloadHex: "01010801" }
  ])
})

test("parses coalesced frames in order", () => {
  const data = Buffer.from("a5a503070400963c01010801a5a5010700000000", "hex")

  assert.deepEqual(parseSppFrames(data), [
    { type: 3, sequence: 7, payloadHex: "01010801" },
    { type: 1, sequence: 7, payloadHex: "" }
  ])
})

test("rejects truncated frames and CRC mismatch", () => {
  assert.throws(() => parseSppFrames(Buffer.from("a5a5030704", "hex")))
  assert.throws(() => parseSppFrames(Buffer.from("a5a503070400963cfe010801", "hex")))
})
