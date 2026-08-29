import { stdin } from "node:process"

import { cryptXiaomiCtr, deriveSessionKeys } from "./session-crypto.mjs"

if (process.argv.length !== 2) {
  process.stderr.write("decrypt failed: provide the private JSON through stdin, never command arguments\n")
  process.exitCode = 1
} else {
  try {
    const chunks = []
    for await (const chunk of stdin) chunks.push(chunk)
    const input = JSON.parse(Buffer.concat(chunks).toString("utf8"))
    const authKey = parseHex(input.authKeyHex, 16, "AuthKey")
    const phoneNonce = parseHex(input.phoneNonceHex, 16, "phone nonce")
    const watchNonce = parseHex(input.watchNonceHex, 16, "watch nonce")
    const ciphertext = parseHex(input.ciphertextHex, undefined, "ciphertext")
    if (input.direction !== "phone-to-band" && input.direction !== "band-to-phone") {
      throw new Error("direction must be phone-to-band or band-to-phone")
    }

    const keys = deriveSessionKeys({ authKey, phoneNonce, watchNonce })
    const key = input.direction === "phone-to-band" ? keys.encryptKey : keys.decryptKey
    const plaintext = cryptXiaomiCtr(ciphertext, key)
    process.stdout.write(`${JSON.stringify({ direction: input.direction, plaintextHex: plaintext.toString("hex") })}\n`)
  } catch (error) {
    process.stderr.write(`decrypt failed: ${safeMessage(error)}\n`)
    process.exitCode = 1
  }
}

function parseHex(value, byteLength, name) {
  const hex = typeof value === "string" ? value.replaceAll(/\s/g, "").toLowerCase() : ""
  if (hex.length === 0 || hex.length % 2 !== 0 || !/^[0-9a-f]+$/.test(hex)) {
    throw new Error(`${name} must be hexadecimal`)
  }
  const bytes = Buffer.from(hex, "hex")
  if (byteLength !== undefined && bytes.length !== byteLength) {
    throw new Error(`${name} must be ${byteLength} bytes`)
  }
  return bytes
}

function safeMessage(error) {
  const allowed = [
    "Unexpected end of JSON input",
    "direction must be phone-to-band or band-to-phone",
    "AuthKey must be hexadecimal",
    "AuthKey must be 16 bytes",
    "phone nonce must be hexadecimal",
    "phone nonce must be 16 bytes",
    "watch nonce must be hexadecimal",
    "watch nonce must be 16 bytes",
    "ciphertext must be hexadecimal"
  ]
  return allowed.includes(error?.message) ? error.message : "invalid private input"
}
