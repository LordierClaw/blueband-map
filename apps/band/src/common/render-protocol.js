const LIMITS = Object.freeze({
  envelopeBytes: 1024,
  payloadBytes: 8192,
  width: 212,
  height: 520,
  maximumPrimitives: 0,
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

function safePixel(x, y) {
  if (x < 12 || x > 200 || y < 12 || y > 508) return false
  if (y < 106) return Math.hypot(x - 106, y - 106) <= 94
  if (y > 413) return Math.hypot(x - 106, y - 413) <= 94
  return true
}

function safeCenter(x, y, width, height, margin = 6) {
  const halfWidth = width / 2 + margin, halfHeight = height / 2 + margin
  return safePixel(x - halfWidth, y - halfHeight) && safePixel(x + halfWidth, y - halfHeight) &&
    safePixel(x - halfWidth, y + halfHeight) && safePixel(x + halfWidth, y + halfHeight)
}

function validPreview(preview) {
  return preview && typeof preview === "object" && !Array.isArray(preview) &&
    ["straight", "left", "right", "uTurn", "roundabout", "arrive"].includes(preview.maneuver) &&
    validInteger(preview.distanceM) && preview.distanceM >= 0 &&
    typeof preview.street === "string" && utf8Length(preview.street) <= 48 &&
    validInteger(preview.x) && validInteger(preview.y) && safeCenter(preview.x, preview.y, 46, 54) &&
    validInteger(preview.heading) && preview.heading >= 0 && preview.heading < 8 &&
    ["visible", "edge", "hidden"].includes(preview.destinationMode) &&
    validInteger(preview.destinationX) && validInteger(preview.destinationY) &&
    (preview.destinationMode === "hidden" ? preview.destinationX === 0 && preview.destinationY === 0 :
      safeCenter(preview.destinationX, preview.destinationY, 20,
        preview.destinationMode === "visible" ? 24 : 20, preview.destinationMode === "edge" ? 0 : 6))
}

function validatePrepare(body, options = {}) {
  if (options.prepared) return reject("busy")
  if (!body || typeof body !== "object" || Array.isArray(body)) return reject("unsupportedRenderer")
  if (body.renderer !== "raster") return reject("unsupportedRenderer")
  if (body.formatVersion !== LIMITS.formatVersion) return reject("unsupportedFormatVersion")
  if (body.format !== "image/png") {
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
  if (body.preview !== undefined && !validPreview(body.preview)) return reject("unsupportedFormatVersion")
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
      primitives: body.primitives,
      preview: body.preview
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
