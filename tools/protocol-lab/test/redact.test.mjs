import assert from "node:assert/strict"
import test from "node:test"

import { redactFixture } from "../src/redact.mjs"

test("redacts secret and device identifier fields without mutating input", () => {
  const source = {
    authKey: "secret",
    nested: {
      sessionKey: "secret",
      nonce: "secret",
      hmac: "secret",
      serial: "secret",
      deviceId: "secret",
      status: 0
    }
  }

  const output = redactFixture(source)

  assert.equal(source.authKey, "secret")
  assert.deepEqual(output, {
    authKey: "[REDACTED]",
    nested: {
      sessionKey: "[REDACTED]",
      nonce: "[REDACTED]",
      hmac: "[REDACTED]",
      serial: "[REDACTED]",
      deviceId: "[REDACTED]",
      status: 0
    }
  })
})

test("rejects decrypted payload containing a configured secret byte sequence", () => {
  assert.throws(
    () => redactFixture(
      { decryptedPayloadHex: "0011deadbeef2233" },
      { denylistedHex: ["deadbeef"] }
    ),
    /denylisted bytes/
  )
})

test("normalizes hex before checking denylist", () => {
  assert.throws(
    () => redactFixture(
      { decryptedPayloadHex: "AA BB CC" },
      { denylistedHex: ["aabb"] }
    ),
    /denylisted bytes/
  )
})

test("allows a clean decrypted payload when denylist is present", () => {
  assert.deepEqual(
    redactFixture(
      { decryptedPayloadHex: "00 11 22 33" },
      { denylistedHex: ["deadbeef"] }
    ),
    { decryptedPayloadHex: "00 11 22 33" }
  )
})
