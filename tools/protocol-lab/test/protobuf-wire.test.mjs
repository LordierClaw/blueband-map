import assert from "node:assert/strict"
import test from "node:test"

import { decodeFields } from "../src/protobuf-wire.mjs"

test("decodes varint and recursively valid length-delimited fields", () => {
  const bytes = Buffer.from("0802220408011002", "hex")

  assert.deepEqual(decodeFields(bytes), [
    { number: 1, wireType: 0, value: 2 },
    {
      number: 4,
      wireType: 2,
      hex: "08011002",
      children: [
        { number: 1, wireType: 0, value: 1 },
        { number: 2, wireType: 0, value: 2 }
      ]
    }
  ])
})

test("keeps opaque bytes as hex without inventing field names", () => {
  assert.deepEqual(decodeFields(Buffer.from("0a02aabb", "hex")), [
    { number: 1, wireType: 2, hex: "aabb" }
  ])
})

test("decodes fixed32 and fixed64 in little-endian order", () => {
  assert.deepEqual(decodeFields(Buffer.from("0d78563412110807060504030201", "hex")), [
    { number: 1, wireType: 5, hex: "78563412", value: 0x12345678 },
    { number: 2, wireType: 1, hex: "0807060504030201", value: "72623859790382856" }
  ])
})

test("rejects field zero, unsupported groups, and truncation", () => {
  assert.throws(() => decodeFields(Buffer.from("00", "hex")))
  assert.throws(() => decodeFields(Buffer.from("0b", "hex")))
  assert.throws(() => decodeFields(Buffer.from("0a02aa", "hex")))
})
