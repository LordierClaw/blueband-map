import { createCipheriv, createHmac } from "node:crypto"

const INFO = Buffer.from("miwear-auth", "utf8")

export function deriveSessionKeys({ authKey, phoneNonce, watchNonce }) {
  requireLength(authKey, 16, "AuthKey")
  requireLength(phoneNonce, 16, "phone nonce")
  requireLength(watchNonce, 16, "watch nonce")

  const salt = Buffer.concat([phoneNonce, watchNonce])
  const prk = createHmac("sha256", salt).update(authKey).digest()
  const okm = hkdfExpand(prk, INFO, 64)
  return {
    decryptKey: okm.subarray(0, 16),
    encryptKey: okm.subarray(16, 32),
    decryptNonce: okm.subarray(32, 36),
    encryptNonce: okm.subarray(36, 40)
  }
}

export function cryptXiaomiCtr(data, key) {
  requireLength(key, 16, "AES key")
  const cipher = createCipheriv("aes-128-ctr", key, key)
  return Buffer.concat([cipher.update(data), cipher.final()])
}

function hkdfExpand(prk, info, length) {
  const blocks = []
  let previous = Buffer.alloc(0)
  for (let index = 1; Buffer.concat(blocks).length < length; index += 1) {
    if (index > 255) throw new Error("HKDF output is too long")
    previous = createHmac("sha256", prk)
      .update(Buffer.concat([previous, info, Buffer.from([index])]))
      .digest()
    blocks.push(previous)
  }
  return Buffer.concat(blocks).subarray(0, length)
}

function requireLength(value, expected, name) {
  if (!Buffer.isBuffer(value) || value.length !== expected) {
    throw new Error(`${name} must be ${expected} bytes`)
  }
}
