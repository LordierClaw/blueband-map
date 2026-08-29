import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import test from "node:test"
import { fileURLToPath } from "node:url"

const cli = fileURLToPath(new URL("../src/inspect.mjs", import.meta.url))

test("CLI prints decoded protobuf JSON", () => {
  const result = spawnSync(process.execPath, [cli, "proto", "0802"], { encoding: "utf8" })

  assert.equal(result.status, 0, result.stderr)
  assert.deepEqual(JSON.parse(result.stdout), [{ number: 1, wireType: 0, value: 2 }])
})

test("CLI returns nonzero for invalid input", () => {
  const result = spawnSync(process.execPath, [cli, "spp", "not-hex"], { encoding: "utf8" })

  assert.notEqual(result.status, 0)
  assert.match(result.stderr, /hexadecimal/i)
})
