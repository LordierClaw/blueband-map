import { inflateRawSync } from "node:zlib"
import { readFile, readdir } from "node:fs/promises"

const dist = new URL("../dist/", import.meta.url)
const rpks = (await readdir(dist)).filter((name) => name.endsWith(".rpk")).sort()
if (rpks.length !== 1) throw new Error(`expected exactly one RPK, found ${rpks.length}`)
const archive = await readFile(new URL(rpks[0], dist))

function entries(bytes) {
  let eocd = -1
  for (let offset = bytes.length - 22; offset >= 0; offset -= 1) {
    if (bytes.readUInt32LE(offset) === 0x06054b50) { eocd = offset; break }
  }
  if (eocd < 0) throw new Error("missing ZIP end record")
  const total = bytes.readUInt16LE(eocd + 10)
  let offset = bytes.readUInt32LE(eocd + 16)
  const result = new Map()
  for (let index = 0; index < total; index += 1) {
    if (bytes.readUInt32LE(offset) !== 0x02014b50) throw new Error("invalid ZIP central directory")
    const method = bytes.readUInt16LE(offset + 10)
    const compressedSize = bytes.readUInt32LE(offset + 20)
    const nameLength = bytes.readUInt16LE(offset + 28)
    const extraLength = bytes.readUInt16LE(offset + 30)
    const commentLength = bytes.readUInt16LE(offset + 32)
    const localOffset = bytes.readUInt32LE(offset + 42)
    const name = bytes.subarray(offset + 46, offset + 46 + nameLength).toString("utf8")
    const localNameLength = bytes.readUInt16LE(localOffset + 26)
    const localExtraLength = bytes.readUInt16LE(localOffset + 28)
    const start = localOffset + 30 + localNameLength + localExtraLength
    const compressed = bytes.subarray(start, start + compressedSize)
    result.set(name, method === 0 ? compressed : method === 8 ? inflateRawSync(compressed) : null)
    offset += 46 + nameLength + extraLength + commentLength
  }
  return result
}

const files = entries(archive)
for (const required of [
  "META-INF/CERT",
  "manifest.json",
  "app.js",
  "pages/index/index.js",
  "common/icon.png",
  "common/maneuver-straight.png",
  "common/maneuver-left.png",
  "common/maneuver-right.png",
  "common/maneuver-uTurn.png",
  "common/maneuver-roundabout.png",
  "common/maneuver-arrive.png",
  "common/destination-pin.png",
  "common/destination-edge.png",
  ...Array.from({ length: 8 }, (_, index) => `common/destination-edge-${index}.png`),
  ...Array.from({ length: 8 }, (_, index) => `common/marker-${index}.png`)
]) {
  if (!files.has(required)) throw new Error(`RPK missing ${required}`)
}
if (files.has("common/nav-shade.png")) throw new Error("RPK must use the native navigation panel instead of nav-shade.png")
const manifest = JSON.parse(files.get("manifest.json").toString("utf8"))
const expectedFeatures = [
  { name: "system.interconnect" },
  { name: "system.file" }
]
if (manifest.package !== "dev.lordierclaw.bluebandmap.band" || manifest.icon !== "/common/icon.png" ||
    manifest.versionName !== "0.6.8" || manifest.versionCode !== 23 || manifest.minAPILevel !== 1 ||
    manifest.config.designWidth !== 212 ||
    JSON.stringify(manifest.features) !== JSON.stringify(expectedFeatures)) {
  throw new Error("compiled manifest does not match Band 10 bundle contract")
}
const icon = files.get("common/icon.png")
if (!icon.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
  throw new Error("compiled launcher icon is not PNG")
}
if (icon.readUInt32BE(16) !== 256 || icon.readUInt32BE(20) !== 256 || icon[25] !== 6) {
  throw new Error("compiled launcher icon must be 256x256 RGBA")
}
for (const name of [
  ...Array.from({ length: 8 }, (_, index) => `marker-${index}.png`),
  ...Array.from({ length: 8 }, (_, index) => `destination-edge-${index}.png`)
]) {
  const asset = files.get(`common/${name}`)
  const marker = name.startsWith("marker-")
  const expectedWidth = marker ? 30 : 24
  const expectedHeight = marker ? 38 : 24
  if (asset.readUInt32BE(16) !== expectedWidth || asset.readUInt32BE(20) !== expectedHeight || asset[25] !== 6) {
    throw new Error(`compiled ${name} must be ${expectedWidth}x${expectedHeight} RGBA`)
  }
  const source = await readFile(new URL(`../src/common/${name}`, import.meta.url))
  if (!asset.equals(source)) throw new Error(`compiled ${name} differs from its source asset`)
}
if (manifest.router.entry !== "pages/index" || Object.keys(manifest.router.pages).length !== 1) {
  throw new Error("compiled manifest must expose exactly one bridge page")
}
const entryCode = files.get("pages/index/index.js").toString("utf8")
if (!entryCode.includes("system.interconnect") || !entryCode.includes("system.file") ||
    entryCode.includes("system.crypto") || entryCode.includes("system.router")) {
  throw new Error("compiled entry must own interconnect and file without unsupported modules")
}
if (files.has("pages/check/check.js")) {
  throw new Error("compiled RPK must not include the obsolete check route")
}
console.log(`verified ${rpks[0]}: ${files.size} entries, one-page gated 212x520 interconnect UI`)
