import assert from "node:assert/strict"
import { execSync } from "node:child_process"
import { readFile, readdir } from "node:fs/promises"
import { fileURLToPath } from "node:url"
import test from "node:test"
import { inflateRawSync } from "node:zlib"

const root = new URL("../", import.meta.url)

test("manifest pins BlueBandMap identity and a single Band 10 page", async () => {
  const manifest = JSON.parse(await readFile(new URL("src/manifest.json", root), "utf8"))
  assert.equal(manifest.package, "dev.lordierclaw.bluebandmap.band")
  assert.equal(manifest.name, "BlueBandMap")
  assert.equal(manifest.versionName, "0.2.0")
  assert.equal(manifest.versionCode, 2)
  assert.equal(manifest.config.designWidth, 212)
  assert.deepEqual(Object.keys(manifest.router.pages), ["pages/index"])
  assert.deepEqual(manifest.features, [
    { name: "system.interconnect" },
    { name: "system.file" },
    { name: "system.crypto" }
  ])
})

test("page follows one-instance lifecycle and v1 envelope contract", async () => {
  const page = await readFile(new URL("src/pages/index/index.ux", root), "utf8")
  assert.match(page, /interconnect\.instance\(\)/)
  assert.match(page, /result\.status\s*===\s*1/)
  assert.doesNotMatch(page, /result\.data\.status|@system\.router/)
  assert.match(page, /onDestroy\s*\(\)/)
  assert.match(page, /onmessage\s*=\s*null/)
  assert.match(page, /topic:\s*["']system\.echo["']/)
  assert.match(page, /MAX_ENVELOPE_BYTES:\s*512/)
  assert.match(page, /MAX_RECENT_IDS:\s*64/)
  assert.match(page, /MAX_ASSET_BYTES:\s*200\s*\*\s*1024/)
  assert.match(page, /MAP_WIDTH:\s*212/)
  assert.match(page, /MAP_HEIGHT:\s*360/)
  assert.match(page, /import interconnect from ["']@system\.interconnect["']/)
  assert.match(page, /import file from ["']@system\.file["']/)
  assert.match(page, /import crypto from ["']@system\.crypto["']/)
  assert.match(page, /hashDigest\s*\(\s*\{\s*uri:\s*transfer\.uri,\s*algo:\s*["']SHA256["']\s*\}\s*\)/)
  assert.doesNotMatch(page, /hashDigest\s*\(\s*\{[^}]*success:/s)
  assert.match(page, /RPK 0\.2\.0/)
  assert.match(page, /<input[^>]+\/>/)
  assert.match(page, /<image[^>]+if="\{\{ mapReady \}\}"[^>]+src="\{\{ mapPath \}\}"[^>]+object-fit="contain"[^>]+@complete="mapComplete"[^>]+@error="mapError"[^>]+\/>/)
})

function archiveEntries(bytes) {
  let end = -1
  for (let offset = bytes.length - 22; offset >= 0; offset -= 1) {
    if (bytes.readUInt32LE(offset) === 0x06054b50) { end = offset; break }
  }
  assert.notEqual(end, -1, "RPK has a ZIP end record")
  const total = bytes.readUInt16LE(end + 10)
  let offset = bytes.readUInt32LE(end + 16)
  const files = new Map()
  for (let index = 0; index < total; index += 1) {
    assert.equal(bytes.readUInt32LE(offset), 0x02014b50)
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
    files.set(name, method === 0 ? compressed : inflateRawSync(compressed))
    offset += 46 + nameLength + extraLength + commentLength
  }
  return files
}

test("real RPK build passes archive verification", { timeout: 120000 }, async () => {
  execSync("npm run prebuild && npx aiot build", { cwd: fileURLToPath(root), stdio: "pipe", shell: true })
  const dist = new URL("dist/", root)
  const rpks = (await readdir(dist)).filter(name => name.endsWith(".rpk"))
  assert.equal(rpks.length, 1)
  const files = archiveEntries(await readFile(new URL(rpks[0], dist)))
  for (const required of ["META-INF/CERT", "manifest.json", "app.js", "pages/index/index.js", "common/icon.png"]) {
    assert.ok(files.has(required), `RPK contains ${required}`)
  }
  const manifest = JSON.parse(files.get("manifest.json").toString("utf8"))
  assert.equal(manifest.versionName, "0.2.0")
  assert.equal(manifest.versionCode, 2)
  assert.deepEqual(manifest.features, [
    { name: "system.interconnect" },
    { name: "system.file" },
    { name: "system.crypto" }
  ])
  const entryCode = files.get("pages/index/index.js").toString("utf8")
  for (const module of ["system.interconnect", "system.file", "system.crypto"]) assert.match(entryCode, new RegExp(module))
})
