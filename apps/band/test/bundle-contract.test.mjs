import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { readFile } from "node:fs/promises"
import { fileURLToPath } from "node:url"
import test from "node:test"
import { inflateSync } from "node:zlib"

const root = new URL("../", import.meta.url)

function rgbaPixels(png) {
  const width = png.readUInt32BE(16), height = png.readUInt32BE(20)
  const compressed = []
  for (let offset = 8; offset < png.length;) {
    const length = png.readUInt32BE(offset)
    if (png.toString("ascii", offset + 4, offset + 8) === "IDAT") compressed.push(png.subarray(offset + 8, offset + 8 + length))
    offset += length + 12
  }
  const rows = inflateSync(Buffer.concat(compressed))
  const stride = width * 4 + 1
  for (let y = 0; y < height; y += 1) assert.equal(rows[y * stride], 0, `row ${y} must use PNG filter 0`)
  return {
    width,
    height,
    pixel: (x, y) => [...rows.subarray(y * stride + 1 + x * 4, y * stride + 1 + x * 4 + 4)]
  }
}

test("manifest pins BlueBandMap identity and a single Band 10 page", async () => {
  const manifest = JSON.parse(await readFile(new URL("src/manifest.json", root), "utf8"))
  assert.equal(manifest.package, "dev.lordierclaw.bluebandmap.band")
  assert.equal(manifest.name, "BlueBandMap")
  assert.equal(manifest.versionName, "0.6.7")
  assert.equal(manifest.versionCode, 22)
  assert.equal(manifest.minAPILevel, 1)
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
  assert.match(page, /ĐANG CHỜ KẾT NỐI…/)
  assert.doesNotMatch(page, /CHECK CONNECTION|CALIBRATE DISPLAY|safe-area-calibration/)
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
  assert.match(page, /RPK 0\.6\.7/)
  assert.match(page, /<input[^>]+\/>/)
  assert.match(page, /<image[^>]+src="\{\{ mapPath \}\}"[^>]+\/>/)
  assert.match(page, /<image[^>]+src="\{\{ pendingMapPath \}\}"[^>]+@complete="mapComplete\(pendingMapToken\)"[^>]+@error="mapError\(pendingMapToken\)"[^>]+\/>/)
  assert.doesNotMatch(page, /<image[^>]+for="\{\{ renderItems \}\}"/)
  assert.doesNotMatch(page, /<image[^>]+object-fit=/)
  assert.match(page, /\.map\s*\{[^}]*object-fit:\s*contain;/s)
  assert.match(page, /\.map-frame\s*\{[^}]*width:\s*212px;[^}]*height:\s*520px;/s)
  assert.doesNotMatch(page, /nav-shade\.png|class="nav-shade"/)
  assert.match(page, /<div class="nav-panel-shadow"[^>]*><\/div>\s*<div class="nav-panel"[^>]*><\/div>/)
  assert.match(page, /<image class="nav-arrow"[^>]+src="\{\{ navArrowPath \}\}"/)
  assert.match(page, /<image class="nav-marker"[^>]+src="\{\{ navMarkerPath \}\}"/)
  assert.match(page, /<image class="nav-destination"[^>]+src="\{\{ navDestinationPath \}\}"/)
  assert.match(page, /safeMaskContains/)
  assert.match(page, /class="diagnostics" if="\{\{ showDiagnostics && !preparedRender \}\}"/)
  assert.doesNotMatch(page, /<div class="nav-marker"/)
  assert.match(page, /\.nav-header\s*\{[^}]*left:\s*0;[^}]*top:\s*0;[^}]*width:\s*212px;[^}]*height:\s*96px;/s)
  assert.doesNotMatch(page, /box-shadow\s*:/)
  assert.match(page, /\.nav-panel-shadow\s*\{[^}]*left:\s*7px;[^}]*top:\s*12px;[^}]*width:\s*198px;[^}]*height:\s*88px;[^}]*border-radius:\s*17px;[^}]*background-color:\s*#000000;/s)
  assert.match(page, /\.nav-panel\s*\{[^}]*left:\s*7px;[^}]*top:\s*7px;[^}]*width:\s*198px;[^}]*height:\s*88px;[^}]*border-radius:\s*17px;[^}]*background-color:\s*#0b2235;/s)
  assert.match(page, /statusVisible:\s*body\.status\s*!==\s*["']navigating["']/)
  assert.match(page, /navStatus\s*=\s*["']LOADING MAP["']/)
  assert.match(page, /\.nav-arrow\s*\{[^}]*left:\s*42px;[^}]*top:\s*28px;[^}]*width:\s*44px;[^}]*height:\s*56px;/s)
  assert.match(page, /\.nav-distance\s*\{[^}]*left:\s*88px;[^}]*top:\s*22px;[^}]*width:\s*88px;/s)
  assert.match(page, /\.nav-street\s*\{[^}]*left:\s*82px;[^}]*width:\s*94px;/s)
  assert.match(page, /\.nav-marker\s*\{[^}]*width:\s*46px;[^}]*height:\s*54px;/s)
})

test("generated HUD resources use the required PNG format at their display size", async () => {
  const expected = {
    "maneuver-right.png": [44, 56, 3],
    "marker-0.png": [46, 54, 6],
    "marker-7.png": [46, 54, 6],
    "destination-pin.png": [28, 34, 3],
    "destination-edge.png": [28, 28, 3],
    ...Object.fromEntries(Array.from({ length: 8 }, (_, direction) => [`destination-edge-${direction}.png`, [34, 34, 6]]))
  }
  for (const [name, [width, height, colorType]] of Object.entries(expected)) {
    const png = await readFile(new URL(`src/common/${name}`, root))
    assert.deepEqual([png.readUInt32BE(16), png.readUInt32BE(20)], [width, height])
    assert.equal(png[24], 8)
    assert.equal(png[25], colorType)
  }
})

test("all compatibility marker files contain the same pixel-mirrored closed RGBA pointer", async () => {
  const markers = []
  for (let heading = 0; heading < 8; heading += 1) {
    const png = await readFile(new URL(`src/common/marker-${heading}.png`, root))
    markers.push(png)
    assert.equal(png[25], 6)
    const { width, height, pixel } = rgbaPixels(png)
    const greenX = [], opaqueRows = []
    for (let y = 0; y < height; y += 1) {
      const row = []
      for (let x = 0; x < width; x += 1) {
        assert.deepEqual(pixel(x, y), pixel(width - 1 - x, y), `pixel (${x}, ${y}) must mirror exactly`)
        const [red, green, blue, alpha] = pixel(x, y)
        if (alpha !== 0) row.push(x)
        if (alpha !== 0 && green > red && green > blue) greenX.push(x)
      }
      if (row.length) {
        assert.equal(Math.min(...row) + Math.max(...row), 45, `row ${y} must use the half-pixel centre`)
        assert.equal(row.length, Math.max(...row) - Math.min(...row) + 1, `row ${y} must not contain an indented corner`)
        opaqueRows.push(row.length)
      }
    }
    assert.ok(Math.max(...greenX) - Math.min(...greenX) + 1 >= 28)
    assert.equal(Math.max(...opaqueRows), 36, "approved navigation pointer must stay long instead of becoming the wide triangle")
    for (let row = 1; row < opaqueRows.length; row += 1) assert.ok(opaqueRows[row] >= opaqueRows[row - 1], "closed pointer must widen monotonically")
  }
  for (const marker of markers.slice(1)) assert.deepEqual(marker, markers[0])
})

test("destination edge icons are clean two-colour RGBA chevrons reaching all eight bitmap edges", async () => {
  for (let direction = 0; direction < 8; direction += 1) {
    const png = await readFile(new URL(`src/common/destination-edge-${direction}.png`, root))
    assert.equal(png[25], 6)
    const { width, height, pixel } = rgbaPixels(png)
    assert.deepEqual([width, height], [34, 34])
    const opaque = []
    const colors = new Set()
    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const value = pixel(x, y)
        if (value[3] !== 0) {
          opaque.push([x, y])
          colors.add(value.join(","))
          assert.notDeepEqual(value.slice(0, 3), [255, 244, 194], "chevron must not contain the old tip dot")
        }
      }
    }
    assert.deepEqual([...colors].sort(), ["5,18,25,255", "255,190,50,255"].sort())
    assert.ok(opaque.length < width * height * 0.3, "chevron must remain an open stroke, not a filled blob")
    if (direction === 0 || direction === 1 || direction === 7) assert.equal(Math.min(...opaque.map(([, y]) => y)), 0)
    if (direction === 1 || direction === 2 || direction === 3) assert.equal(Math.max(...opaque.map(([x]) => x)), 33)
    if (direction === 3 || direction === 4 || direction === 5) assert.equal(Math.max(...opaque.map(([, y]) => y)), 33)
    if (direction === 5 || direction === 6 || direction === 7) assert.equal(Math.min(...opaque.map(([x]) => x)), 0)
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
  assert.match(result.stdout, /verified .*\.0\.6\.7\.rpk/)

  const compiledEntry = await readFile(new URL("build/pages/index/index.js", root), "utf8")
  assert.doesNotMatch(compiledEntry, /\.\/src\/common\/(?:render-protocol|vector-scene)\.js/, "page load must not start a custom module graph")
  assert.doesNotMatch(compiledEntry, /exports\.(?:validIdentifier|decodeBBMV)|Object\.freeze\(/, "page entry must not evaluate imported helper modules")
})
