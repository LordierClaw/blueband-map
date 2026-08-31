import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { readFile } from "node:fs/promises"
import { fileURLToPath } from "node:url"
import test from "node:test"

const root = new URL("../", import.meta.url)

test("manifest pins BlueBandMap identity and a single Band 10 page", async () => {
  const manifest = JSON.parse(await readFile(new URL("src/manifest.json", root), "utf8"))
  assert.equal(manifest.package, "dev.lordierclaw.bluebandmap.band")
  assert.equal(manifest.name, "BlueBandMap")
  assert.equal(manifest.versionName, "0.3.0")
  assert.equal(manifest.versionCode, 12)
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
  assert.match(page, /MAX_ENVELOPE_BYTES:\s*512/)
  assert.match(page, /MAX_RECENT_IDS:\s*64/)
  assert.match(page, /MAX_ASSET_BYTES:\s*8192/)
  assert.match(page, /MAP_WIDTH:\s*212/)
  assert.match(page, /MAP_HEIGHT:\s*520/)
  assert.match(page, /import interconnect from ["']@system\.interconnect["']/)
  assert.match(page, /import file from ["']@system\.file["']/)
  assert.doesNotMatch(page, /@system\.crypto|crypto\.atob|crypto\.hashDigest/)
  assert.doesNotMatch(page, /transform:rotate\(|transform-origin:/)
  assert.doesNotMatch(page, /transform:\s*JSON\.stringify\(\{\s*rotate:/)
  assert.match(page, /RPK 0\.3\.0/)
  assert.match(page, /<input[^>]+\/>/)
  assert.match(page, /<image[^>]+src="\{\{ mapPath \}\}"[^>]+\/>/)
  assert.match(page, /<image[^>]+src="\{\{ pendingMapPath \}\}"[^>]+@complete="mapComplete\(pendingMapToken\)"[^>]+@error="mapError\(pendingMapToken\)"[^>]+\/>/)
  assert.doesNotMatch(page, /<image[^>]+for="\{\{ renderItems \}\}"/)
  assert.doesNotMatch(page, /<image[^>]+object-fit=/)
  assert.match(page, /\.map\s*\{[^}]*object-fit:\s*contain;/s)
  assert.match(page, /\.map-frame\s*\{[^}]*width:\s*212px;[^}]*height:\s*520px;/s)
  assert.match(page, /\.nav-header\s*\{[^}]*width:\s*184px;[^}]*height:\s*12[0-8]px;[^}]*rgba\(4,\s*12,\s*20,\s*0\.68\)/s)
  assert.match(page, /navStatusVisible\s*=\s*body\.status\s*!==\s*["']navigating["']/)
  assert.match(page, /navStatus\s*=\s*["']LOADING MAP["']/)
  assert.match(page, /\.nav-marker\s*\{[^}]*border-color:\s*#00e5ff;[^}]*background-color:\s*#ffffff;/s)
})

test("normal npm build keeps the Band entry firmware-safe", { timeout: 120000 }, async () => {
  const result = spawnSync("npm", ["run", "build"], {
    cwd: fileURLToPath(root),
    encoding: "utf8"
  })
  const diagnostics = result.stdout + result.stderr
  assert.equal(result.status, 0, diagnostics)
  assert.doesNotMatch(diagnostics, /unsupport(?:ed)? attribute|unsupported (?:attribute|property)/i)
  assert.match(result.stdout, /verified .*\.0\.3\.0\.rpk/)

  const compiledEntry = await readFile(new URL("build/pages/index/index.js", root), "utf8")
  assert.doesNotMatch(compiledEntry, /\.\/src\/common\/(?:render-protocol|vector-scene)\.js/, "page load must not start a custom module graph")
  assert.doesNotMatch(compiledEntry, /exports\.(?:validIdentifier|decodeBBMV)|Object\.freeze\(/, "page entry must not evaluate imported helper modules")
})
