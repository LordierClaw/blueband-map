import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import test from "node:test"
import { fileURLToPath } from "node:url"

import { cryptXiaomiCtr, deriveSessionKeys } from "../src/session-crypto.mjs"

const cli = fileURLToPath(new URL("../src/decrypt-ctr.mjs", import.meta.url))

test("decrypt CLI reads secrets only from stdin and returns plaintext", () => {
  const input = {
    authKeyHex: "000102030405060708090a0b0c0d0e0f",
    phoneNonceHex: "202122232425262728292a2b2c2d2e2f",
    watchNonceHex: "303132333435363738393a3b3c3d3e3f",
    direction: "band-to-phone"
  }
  const keys = deriveSessionKeys({
    authKey: Buffer.from(input.authKeyHex, "hex"),
    phoneNonce: Buffer.from(input.phoneNonceHex, "hex"),
    watchNonce: Buffer.from(input.watchNonceHex, "hex")
  })
  input.ciphertextHex = cryptXiaomiCtr(Buffer.from("0801120762617474657279", "hex"), keys.decryptKey).toString("hex")

  const result = spawnSync(process.execPath, [cli], {
    input: JSON.stringify(input),
    encoding: "utf8"
  })

  assert.equal(result.status, 0, result.stderr)
  assert.deepEqual(JSON.parse(result.stdout), { direction: "band-to-phone", plaintextHex: "0801120762617474657279" })
  assert.doesNotMatch(result.stdout + result.stderr, /0001020304050607/)
})

test("decrypt CLI rejects a secret passed as a command argument", () => {
  const result = spawnSync(process.execPath, [cli, "00010203"], { encoding: "utf8" })

  assert.notEqual(result.status, 0)
  assert.match(result.stderr, /stdin/i)
})
