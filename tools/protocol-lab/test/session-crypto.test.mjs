import assert from "node:assert/strict"
import test from "node:test"

import { cryptXiaomiCtr, deriveSessionKeys } from "../src/session-crypto.mjs"

test("derives the independently verified synthetic Xiaomi session keys", () => {
  const keys = deriveSessionKeys({
    authKey: Buffer.from("000102030405060708090a0b0c0d0e0f", "hex"),
    phoneNonce: Buffer.from("202122232425262728292a2b2c2d2e2f", "hex"),
    watchNonce: Buffer.from("303132333435363738393a3b3c3d3e3f", "hex")
  })

  assert.equal(keys.decryptKey.toString("hex"), "e58c7a55b44ceba4d831383e2e284c08")
  assert.equal(keys.encryptKey.toString("hex"), "7a05cade77011d75292b2889496a71b2")
  assert.equal(keys.decryptNonce.toString("hex"), "85ba506d")
  assert.equal(keys.encryptNonce.toString("hex"), "d77bae53")
})

test("Xiaomi CTR transform restores a partial protobuf payload", () => {
  const key = Buffer.from("00112233445566778899aabbccddeeff", "hex")
  const plaintext = Buffer.from("0801120762617474657279", "hex")
  const ciphertext = cryptXiaomiCtr(plaintext, key)

  assert.notDeepEqual(ciphertext, plaintext)
  assert.deepEqual(cryptXiaomiCtr(ciphertext, key), plaintext)
})

test("rejects secret and nonce lengths that cannot belong to v2 auth", () => {
  assert.throws(() => deriveSessionKeys({
    authKey: Buffer.alloc(15),
    phoneNonce: Buffer.alloc(16),
    watchNonce: Buffer.alloc(16)
  }), /AuthKey must be 16 bytes/)
  assert.throws(() => cryptXiaomiCtr(Buffer.alloc(1), Buffer.alloc(15)), /AES key/)
})
