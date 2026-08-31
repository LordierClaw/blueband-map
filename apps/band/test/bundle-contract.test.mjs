import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { readFile } from "node:fs/promises"
import { fileURLToPath } from "node:url"
import test from "node:test"
import { inflateSync } from "node:zlib"

const root = new URL("../", import.meta.url)

test("manifest pins BlueBandMap identity and a single Band 10 page", async () => {
  const manifest = JSON.parse(await readFile(new URL("src/manifest.json", root), "utf8"))
  assert.equal(manifest.package, "dev.lordierclaw.bluebandmap.band")
  assert.equal(manifest.name, "BlueBandMap")
  assert.equal(manifest.versionName, "0.4.0")
  assert.equal(manifest.versionCode, 13)
  assert.equal(manifest.config.designWidth, 212)
  assert.deepEqual(Object.keys(manifest.router.pages), ["pages/index"])
  assert.deepEqual(manifest.features, [
    { name: "system.interconnect" },
    { name: "system.file" }
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
  assert.match(page, /MAX_ENVELOPE_BYTES:\s*1024/)
  assert.match(page, /MAX_RECENT_IDS:\s*64/)
  assert.match(page, /MAX_ASSET_BYTES:\s*8192/)
  assert.match(page, /MAP_WIDTH:\s*212/)
  assert.match(page, /MAP_HEIGHT:\s*520/)
  assert.match(page, /import interconnect from ["']@system\.interconnect["']/)
  assert.match(page, /import file from ["']@system\.file["']/)
  assert.doesNotMatch(page, /@system\.crypto|crypto\.atob|crypto\.hashDigest/)
  assert.doesNotMatch(page, /transform:rotate\(|transform-origin:/)
  assert.doesNotMatch(page, /transform:\s*JSON\.stringify\(\{\s*rotate:/)
  assert.match(page, /RPK 0\.4\.0/)
  assert.match(page, /<input[^>]+\/>/)
  assert.match(page, /<image[^>]+src="\{\{ mapPath \}\}"[^>]+\/>/)
  assert.match(page, /<image[^>]+src="\{\{ pendingMapPath \}\}"[^>]+@complete="mapComplete\(pendingMapToken\)"[^>]+@error="mapError\(pendingMapToken\)"[^>]+\/>/)
  assert.doesNotMatch(page, /<image[^>]+for="\{\{ renderItems \}\}"/)
  assert.doesNotMatch(page, /<image[^>]+object-fit=/)
  assert.match(page, /\.map\s*\{[^}]*object-fit:\s*contain;/s)
  assert.match(page, /\.map-frame\s*\{[^}]*width:\s*212px;[^}]*height:\s*520px;/s)
  assert.match(page, /<image class="nav-shade"[^>]+src="\/common\/nav-shade\.png"/)
  assert.match(page, /<image class="nav-arrow"[^>]+src="\{\{ navArrowPath \}\}"/)
  assert.match(page, /<image class="nav-marker"[^>]+src="\{\{ navMarkerPath \}\}"/)
  assert.match(page, /class="diagnostics" if="\{\{ showDiagnostics && !preparedRender \}\}"/)
  assert.doesNotMatch(page, /<div class="nav-marker"/)
  assert.match(page, /\.nav-header\s*\{[^}]*left:\s*0;[^}]*top:\s*0;[^}]*width:\s*212px;[^}]*height:\s*96px;/s)
  assert.doesNotMatch(page, /\.nav-header\s*\{[^}]*background-color:/s)
  assert.match(page, /statusVisible:\s*body\.status\s*!==\s*["']navigating["']/)
  assert.match(page, /navStatus\s*=\s*["']LOADING MAP["']/)
  assert.match(page, /\.nav-arrow\s*\{[^}]*left:\s*34px;[^}]*top:\s*20px;[^}]*width:\s*38px;[^}]*height:\s*48px;/s)
  assert.match(page, /\.nav-distance\s*\{[^}]*left:\s*78px;[^}]*top:\s*16px;[^}]*width:\s*100px;/s)
  assert.match(page, /\.nav-street\s*\{[^}]*left:\s*78px;[^}]*width:\s*100px;/s)
  assert.match(page, /\.nav-marker\s*\{[^}]*width:\s*38px;[^}]*height:\s*44px;/s)
  assert.match(page, /Math\.max\(30,\s*Math\.min\(182,\s*body\.x\)\)/)
  assert.match(page, /Math\.max\(130,\s*Math\.min\(478,\s*body\.y\)\)/)
})

test("generated HUD resources are indexed PNGs at their display size", async () => {
  const expected = {
    "nav-shade.png": [212, 96],
    "maneuver-right.png": [42, 54],
    "marker-0.png": [38, 44],
    "marker-7.png": [38, 44]
  }
  for (const [name, dimensions] of Object.entries(expected)) {
    const png = await readFile(new URL(`src/common/${name}`, root))
    assert.deepEqual([png.readUInt32BE(16), png.readUInt32BE(20)], dimensions)
    assert.equal(png[24], 8)
    assert.equal(png[25], 3)
  }
})

test("direction markers keep a transparent margin in every heading", async () => {
  for (let heading = 0; heading < 8; heading += 1) {
    const png = await readFile(new URL(`src/common/marker-${heading}.png`, root))
    const width = png.readUInt32BE(16), height = png.readUInt32BE(20)
    const compressed = []
    for (let offset = 8; offset < png.length;) {
      const length = png.readUInt32BE(offset)
      if (png.toString("ascii", offset + 4, offset + 8) === "IDAT") compressed.push(png.subarray(offset + 8, offset + 8 + length))
      offset += length + 12
    }
    const rows = inflateSync(Buffer.concat(compressed))
    const pixel = (x, y) => rows[y * (width + 1) + x + 1]
    assert.ok(Array.from({ length: width }, (_, x) => pixel(x, 0) + pixel(x, height - 1)).every(value => value === 0))
    assert.ok(Array.from({ length: height }, (_, y) => pixel(0, y) + pixel(width - 1, y)).every(value => value === 0))
  }
})

test("normal npm build keeps the Band entry firmware-safe", { timeout: 120000 }, async () => {
  const result = spawnSync("npm", ["run", "build"], {
    cwd: fileURLToPath(root),
    encoding: "utf8"
  })
  const diagnostics = result.stdout + result.stderr
  assert.equal(result.status, 0, diagnostics)
  assert.doesNotMatch(diagnostics, /unsupport(?:ed)? attribute|unsupported (?:attribute|property)/i)
  assert.match(result.stdout, /verified .*\.0\.4\.0\.rpk/)

  const compiledEntry = await readFile(new URL("build/pages/index/index.js", root), "utf8")
  assert.doesNotMatch(compiledEntry, /\.\/src\/common\/(?:render-protocol|vector-scene)\.js/, "page load must not start a custom module graph")
  assert.doesNotMatch(compiledEntry, /exports\.(?:validIdentifier|decodeBBMV)|Object\.freeze\(/, "page entry must not evaluate imported helper modules")
})
