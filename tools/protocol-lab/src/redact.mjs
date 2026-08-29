const SECRET_KEY_PARTS = [
  "authkey",
  "sessionkey",
  "encryptionkey",
  "decryptionkey",
  "nonce",
  "hmac",
  "serial",
  "deviceid"
]

export function redactFixture(input, options = {}) {
  const denylistedHex = (options.denylistedHex ?? [])
    .map(normalizeHex)
    .filter((value) => value.length > 0)

  inspectPayloads(input, denylistedHex)
  return redactValue(input)
}

function inspectPayloads(value, denylistedHex) {
  if (Array.isArray(value)) {
    value.forEach((item) => inspectPayloads(item, denylistedHex))
    return
  }
  if (!value || typeof value !== "object") return

  for (const [key, child] of Object.entries(value)) {
    if (key.toLowerCase() === "decryptedpayloadhex" && typeof child === "string") {
      const payload = normalizeHex(child)
      for (const denied of denylistedHex) {
        if (payload.includes(denied)) {
          throw new Error("decrypted payload contains denylisted bytes")
        }
      }
    }
    inspectPayloads(child, denylistedHex)
  }
}

function redactValue(value) {
  if (Array.isArray(value)) return value.map(redactValue)
  if (!value || typeof value !== "object") return value

  const output = {}
  for (const [key, child] of Object.entries(value)) {
    const normalizedKey = key.toLowerCase().replaceAll("_", "").replaceAll("-", "")
    output[key] = SECRET_KEY_PARTS.some((part) => normalizedKey.includes(part))
      ? "[REDACTED]"
      : redactValue(child)
  }
  return output
}

function normalizeHex(value) {
  const normalized = String(value).replaceAll(/\s/g, "").toLowerCase()
  if (!/^[0-9a-f]*$/.test(normalized) || normalized.length % 2 !== 0) {
    throw new Error("invalid hexadecimal value")
  }
  return normalized
}
