const LIMITS = Object.freeze({
  width: 212,
  height: 360,
  maximumSegments: 40,
  headerBytes: 22,
  segmentBytes: 9
})

const MAGIC = Object.freeze([0x42, 0x42, 0x4d, 0x56])
const COLORS = Object.freeze({
  0: "#7897b8",
  1: "#d7e7f7",
  2: "#5dffb0"
})

function asBytes(value) {
  if (value instanceof Uint8Array) return value
  if (value instanceof ArrayBuffer) return new Uint8Array(value)
  if (value && value.buffer instanceof ArrayBuffer && typeof value.byteLength === "number") {
    return new Uint8Array(value.buffer, value.byteOffset || 0, value.byteLength)
  }
  return null
}

function readUInt16(bytes, offset) {
  return bytes[offset] | (bytes[offset + 1] << 8)
}

function readUInt32(bytes, offset) {
  return (bytes[offset] | (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0
}

function reject(code) {
  return { ok: false, code }
}

function inside(point) {
  return point.x < LIMITS.width && point.y < LIMITS.height
}

function decodeBBMV(value) {
  const bytes = asBytes(value)
  if (!bytes || bytes.length < LIMITS.headerBytes) return reject("invalidLength")
  for (let index = 0; index < MAGIC.length; index += 1) {
    if (bytes[index] !== MAGIC[index]) return reject("invalidMagic")
  }
  if (bytes[4] !== 1) return reject("unsupportedVersion")

  const width = readUInt16(bytes, 5)
  const height = readUInt16(bytes, 7)
  if (width !== LIMITS.width || height !== LIMITS.height) return reject("invalidViewport")

  const roadCount = bytes[9]
  const routeCount = bytes[10]
  const segmentCount = roadCount + routeCount
  if (segmentCount > LIMITS.maximumSegments) return reject("tooManySegments")
  if (bytes.length !== LIMITS.headerBytes + segmentCount * LIMITS.segmentBytes) return reject("invalidLength")

  const currentPosition = { x: readUInt16(bytes, 11), y: readUInt16(bytes, 13) }
  if (!inside(currentPosition)) return reject("outOfViewport")
  const heading = readUInt16(bytes, 15)
  if (heading > 359) return reject("invalidHeading")
  const maneuver = bytes[17]
  if (maneuver > 4) return reject("invalidManeuver")

  const segments = []
  let offset = LIMITS.headerBytes
  for (let index = 0; index < segmentCount; index += 1) {
    const start = { x: readUInt16(bytes, offset), y: readUInt16(bytes, offset + 2) }
    const end = { x: readUInt16(bytes, offset + 4), y: readUInt16(bytes, offset + 6) }
    const lineClass = bytes[offset + 8]
    if (lineClass > 2) return reject("invalidSegmentClass")
    if (!inside(start) || !inside(end)) return reject("outOfViewport")
    segments.push({ start, end, lineClass })
    offset += LIMITS.segmentBytes
  }

  return {
    ok: true,
    scene: {
      currentPosition,
      heading,
      maneuver,
      distanceMeters: readUInt32(bytes, 18),
      roadSegmentCount: roadCount,
      routeSegmentCount: routeCount,
      segments
    }
  }
}

function sceneToNativeSegments(scene) {
  if (!scene || !Array.isArray(scene.segments) || scene.segments.length > LIMITS.maximumSegments) return []
  return scene.segments.map((segment, index) => {
    const dx = segment.end.x - segment.start.x
    const dy = segment.end.y - segment.start.y
    const length = Math.max(1, Math.round(Math.sqrt(dx * dx + dy * dy)))
    const angle = Math.round(Math.atan2(dy, dx) * 180 / Math.PI * 10) / 10
    const color = COLORS[segment.lineClass] || COLORS[0]
    const thickness = segment.lineClass === 2 ? 3 : (segment.lineClass === 1 ? 2 : 1)
    return {
      key: "segment-" + index,
      left: segment.start.x,
      top: segment.start.y,
      width: length,
      height: thickness,
      angle,
      color,
      style: "position:absolute;left:" + segment.start.x + "px;top:" + segment.start.y +
        "px;width:" + length + "px;height:" + thickness + "px;background-color:" + color +
        ";transform-origin:0 50%;transform:rotate(" + angle + "deg);"
    }
  })
}

function sceneToNativeMarker(scene) {
  if (!scene || !inside(scene.currentPosition)) return null
  const x = scene.currentPosition.x
  const y = scene.currentPosition.y
  return {
    left: x - 4,
    top: y - 4,
    style: "position:absolute;left:" + (x - 4) + "px;top:" + (y - 4) +
      "px;width:8px;height:8px;border-radius:4px;background-color:#168cff;"
  }
}

export { LIMITS, decodeBBMV, sceneToNativeMarker, sceneToNativeSegments }
export default { LIMITS, decodeBBMV, sceneToNativeMarker, sceneToNativeSegments }
