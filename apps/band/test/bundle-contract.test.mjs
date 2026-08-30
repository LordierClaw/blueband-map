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
  assert.match(page, /MAX_ASSET_BYTES:\s*64\s*\*\s*1024/)
  assert.match(page, /MAP_WIDTH:\s*212/)
  assert.match(page, /MAP_HEIGHT:\s*360/)
  assert.match(page, /import interconnect from ["']@system\.interconnect["']/)
  assert.match(page, /import file from ["']@system\.file["']/)
  assert.match(page, /import crypto from ["']@system\.crypto["']/)
  assert.match(page, /hashDigest\s*\(\s*\{\s*uri:\s*transfer\.uri,\s*algo:\s*["']SHA256["']\s*\}\s*\)/)
  assert.doesNotMatch(page, /hashDigest\s*\(\s*\{[^}]*success:/s)
  assert.match(page, /RPK 0\.2\.0/)
  assert.match(page, /<input[^>]+\/>/)
  assert.match(page, /<image[^>]+for="\{\{ renderItems \}\}"[^>]+src="\{\{ \$item\.path \}\}"[^>]+@complete="mapComplete\(\$item\.token\)"[^>]+@error="mapError\(\$item\.token\)"[^>]+\/>/)
  assert.doesNotMatch(page, /<image[^>]+object-fit=/)
  assert.match(page, /\.map\s*\{[^}]*object-fit:\s*contain;/s)
})

test("normal npm build exits successfully through canonical archive verification", { timeout: 120000 }, () => {
  const result = spawnSync("npm", ["run", "build"], {
    cwd: fileURLToPath(root),
    encoding: "utf8"
  })
  const diagnostics = result.stdout + result.stderr
  assert.equal(result.status, 0, diagnostics)
  assert.doesNotMatch(diagnostics, /unsupport(?:ed)? attribute|unsupported (?:attribute|property)/i)
  assert.match(result.stdout, /verified .*\.0\.2\.0\.rpk/)
})
