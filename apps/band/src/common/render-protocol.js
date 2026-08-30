const LIMITS = Object.freeze({
  envelopeBytes: 512,
  payloadBytes: 64 * 1024,
  width: 212,
  height: 360,
  maximumPrimitives: 40,
  formatVersion: 1,
  maximumIdentifierBytes: 24
})

const REJECT_CODES = Object.freeze([
  "unsupportedRenderer",
  "unsupportedFormatVersion",
  "busy",
  "payloadTooLarge",
  "tooManyPrimitives",
  "invalidDimensions",
  "insufficientStorage"
])

function utf8Length(value) {
  if (typeof value !== "string") return 0
  let length = 0
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index)
    if (code < 128) length += 1
    else if (code < 2048) length += 2
    else if (code >= 55296 && code <= 56319 && index + 1 < value.length) {
      index += 1
      length += 4
    } else length += 3
  }
  return length
}

function validIdentifier(value) {
  return typeof value === "string" && utf8Length(value) >= 1 &&
    utf8Length(value) <= LIMITS.maximumIdentifierBytes && /^[\x20-\x7e]+$/.test(value)
}

function validSHA256(value) {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value)
}

function validInteger(value) {
  return Number.isInteger(value) && Number.isFinite(value)
}

function reject(code) {
  return { ok: false, code }
}

function validatePrepare(body, options = {}) {
  if (options.prepared) return reject("busy")
  if (!body || typeof body !== "object" || Array.isArray(body)) return reject("unsupportedRenderer")
  if (body.renderer !== "raster" && body.renderer !== "vector") return reject("unsupportedRenderer")
  if (body.formatVersion !== LIMITS.formatVersion) return reject("unsupportedFormatVersion")
  if ((body.renderer === "raster" && body.format !== "image/png") ||
    (body.renderer === "vector" && body.format !== "application/vnd.blueband.map-vector-v1")) {
    return reject("unsupportedFormatVersion")
  }
  if (body.width !== LIMITS.width || body.height !== LIMITS.height) return reject("invalidDimensions")
  if (!validInteger(body.bytes) || body.bytes <= 0 || body.bytes > LIMITS.payloadBytes) return reject("payloadTooLarge")
  if (!validInteger(body.primitives) || body.primitives < 0 || body.primitives > LIMITS.maximumPrimitives) {
    return reject("tooManyPrimitives")
  }
  if (!validIdentifier(body.runId) || !validIdentifier(body.sceneId) || !validSHA256(body.sha256)) {
    return reject("unsupportedFormatVersion")
  }
  if (options.availableStorageBytes !== undefined && body.bytes > options.availableStorageBytes) {
    return reject("insufficientStorage")
  }
  return {
    ok: true,
    prepared: {
      runId: body.runId,
      sceneId: body.sceneId,
      renderer: body.renderer,
      format: body.format,
      formatVersion: body.formatVersion,
      width: body.width,
      height: body.height,
      bytes: body.bytes,
      sha256: body.sha256,
      primitives: body.primitives
    }
  }
}

function validateAssetBegin(body, prepared) {
  if (!prepared) return reject("notPrepared")
  if (!body || typeof body !== "object" ||
    body.run !== prepared.runId || body.scene !== prepared.sceneId ||
    body.renderer !== prepared.renderer || body.formatVersion !== prepared.formatVersion ||
    body.width !== prepared.width || body.height !== prepared.height ||
    body.bytes !== prepared.bytes || body.sha256 !== prepared.sha256 ||
    body.primitives !== prepared.primitives || body.format !== prepared.format) {
    return reject("notPrepared")
  }
  return { ok: true }
}

export { LIMITS, REJECT_CODES, validIdentifier, validSHA256, validatePrepare, validateAssetBegin }
export default { LIMITS, REJECT_CODES, validIdentifier, validSHA256, validatePrepare, validateAssetBegin }
