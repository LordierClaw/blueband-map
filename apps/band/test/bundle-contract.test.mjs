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
  assert.equal(manifest.versionName, "0.6.13")
  assert.equal(manifest.versionCode, 28)
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
  assert.match(page, /CHỜ LỆNH TỪ IPHONE…/)
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
  assert.match(page, /RPK 0\.6\.13/)
  assert.doesNotMatch(page, /<input[^>]+\/>|class="diagnostics"|ECHO PING|CLEAR EVENTS/)
  assert.match(page, /<image[^>]+src="\{\{ mapPath \}\}"[^>]+\/>/)
  assert.match(page, /<image[^>]+src="\{\{ pendingMapPath \}\}"[^>]+@complete="mapComplete\(pendingMapToken\)"[^>]+@error="mapError\(pendingMapToken\)"[^>]+\/>/)
  assert.doesNotMatch(page, /<image[^>]+for="\{\{ renderItems \}\}"/)
  assert.doesNotMatch(page, /<image[^>]+object-fit=/)
  assert.match(page, /\.map\s*\{[^}]*object-fit:\s*contain;/s)
  assert.match(page, /\.map-frame\s*\{[^}]*width:\s*212px;[^}]*height:\s*520px;/s)
  assert.doesNotMatch(page, /nav-shade\.png|class="nav-shade"|class="nav-panel(?:-shadow)?"/)
  assert.match(page, /navMarkerPath:\s*["']\/common\/marker-cursor-v4\.png["']/)
  assert.doesNotMatch(page, /marker-cursor-v3\.png/)
  assert.doesNotMatch(page, /\/common\/marker-[0-7]\.png/)
  assert.match(page, /<image class="nav-arrow"[^>]+src="\{\{ navArrowPath \}\}"/)
  assert.match(page, /<image class="nav-marker"[^>]+src="\{\{ navMarkerPath \}\}"/)
  assert.match(page, /<image class="nav-destination"[^>]+src="\{\{ navDestinationPath \}\}"/)
  assert.match(page, /safeMaskContains/)
  assert.doesNotMatch(page, /<div class="nav-marker"/)
  assert.match(page, /\.nav-header\s*\{[^}]*left:\s*0;[^}]*top:\s*0;[^}]*width:\s*212px;[^}]*height:\s*96px;/s)
  assert.doesNotMatch(page, /box-shadow\s*:/)
  assert.doesNotMatch(page, /linear-gradient\s*\(/)
  assert.doesNotMatch(page, /\.nav-panel(?:-shadow)?\s*\{/)
  assert.match(page, /statusVisible:\s*body\.status\s*!==\s*["']navigating["']/)
  assert.match(page, /navStatus\s*=\s*["']LOADING MAP["']/)
  assert.match(page, /if \(!this\.confirmedMap\) \{[\s\S]*this\.navStatus = "LOADING MAP"/)
  assert.match(page, /\.nav-arrow\s*\{[^}]*left:\s*32px;[^}]*top:\s*28px;[^}]*width:\s*44px;[^}]*height:\s*56px;/s)
  assert.match(page, /\.nav-distance\s*\{[^}]*left:\s*78px;[^}]*top:\s*26px;[^}]*width:\s*88px;/s)
  assert.match(page, /\.nav-street\s*\{[^}]*left:\s*72px;[^}]*top:\s*60px;[^}]*width:\s*126px;/s)
  assert.match(page, /\.nav-street\s*\{[^}]*text-align:\s*left;/s,
    "short names such as Yên Bình must start beside the maneuver, not at the far right")
  assert.match(page, /\.nav-status\s*\{[^}]*left:\s*72px;[^}]*top:\s*80px;[^}]*width:\s*94px;/s)
  assert.match(page, /\.nav-marker\s*\{[^}]*width:\s*30px;[^}]*height:\s*38px;/s)
})

test("generated HUD resources use the required PNG format at their display size", async () => {
  const expected = {
    ...Object.fromEntries(["straight", "left", "right", "uTurn", "roundabout", "arrive"]
      .map(name => [`maneuver-${name}.png`, [44, 56, 6]])),
    "marker-cursor-v4.png": [30, 38, 6],
    "destination-pin.png": [28, 34, 3],
    "destination-edge.png": [28, 28, 3],
    ...Object.fromEntries(Array.from({ length: 8 }, (_, direction) => [`destination-edge-${direction}.png`, [24, 24, 6]]))
  }
  for (const [name, [width, height, colorType]] of Object.entries(expected)) {
    const png = await readFile(new URL(`src/common/${name}`, root))
    assert.deepEqual([png.readUInt32BE(16), png.readUInt32BE(20)], [width, height])
    assert.equal(png[24], 8)
    assert.equal(png[25], colorType)
  }
})

test("cursor marker keeps its accepted geometry with a one-pixel white outline", async () => {
  const png = await readFile(new URL("src/common/marker-cursor-v4.png", root))
  assert.equal(png[25], 6)
  const { width, height, pixel } = rgbaPixels(png)
  assert.deepEqual([width, height], [30, 38])
  const opaque = [], white = [], greenPixels = []
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const [red, green, blue, alpha] = pixel(x, y)
      if (alpha !== 0) {
        opaque.push([x, y])
        if (red >= 245 && green >= 245 && blue >= 245) white.push([x, y])
        if (red === 20 && green === 128 && blue === 74) greenPixels.push([x, y])
      }
    }
  }
  assert.ok(pixel(15, 2)[3] > 0, "sharp cursor tip must lie on the route centre")
  assert.ok(pixel(15, 26)[3] > 0, "cursor notch vertex must lie on the route centre")
  assert.equal(pixel(15, 32)[3], 0, "concave cursor notch must remain visibly open")
  assert.ok(white.length > 0, "white outline is required")
  assert.ok(greenPixels.length > white.length, "outline must not replace the green cursor")
  assert.ok(Math.min(...opaque.map(([x]) => x)) >= 0)
  assert.ok(Math.max(...opaque.map(([x]) => x)) <= 29)
  assert.ok(Math.min(...opaque.map(([, y]) => y)) >= 0)
  assert.ok(Math.max(...opaque.map(([, y]) => y)) <= 33)
})

test("destination edge icons are contained 24px two-colour RGBA chevrons", async () => {
  for (let direction = 0; direction < 8; direction += 1) {
    const png = await readFile(new URL(`src/common/destination-edge-${direction}.png`, root))
    assert.equal(png[25], 6)
    const { width, height, pixel } = rgbaPixels(png)
    assert.deepEqual([width, height], [24, 24])
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
    assert.ok(Math.min(...opaque.map(([x]) => x)) >= 1)
    assert.ok(Math.max(...opaque.map(([x]) => x)) <= 22)
    assert.ok(Math.min(...opaque.map(([, y]) => y)) >= 1)
    assert.ok(Math.max(...opaque.map(([, y]) => y)) <= 22)
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
  assert.match(result.stdout, /verified .*\.0\.6\.13\.rpk/)

  const compiledEntry = await readFile(new URL("build/pages/index/index.js", root), "utf8")
  assert.doesNotMatch(compiledEntry, /\.\/src\/common\/(?:render-protocol|vector-scene)\.js/, "page load must not start a custom module graph")
  assert.doesNotMatch(compiledEntry, /exports\.(?:validIdentifier|decodeBBMV)|Object\.freeze\(/, "page entry must not evaluate imported helper modules")
})
