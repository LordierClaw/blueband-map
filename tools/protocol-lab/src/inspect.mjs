import { decodeFields } from "./protobuf-wire.mjs"
import { parseSppFrames } from "./spp-v2.mjs"

const [mode, rawHex] = process.argv.slice(2)

try {
  if (mode !== "proto" && mode !== "spp") {
    throw new Error("mode must be 'proto' or 'spp'")
  }
  const hex = String(rawHex ?? "").replaceAll(/\s/g, "").toLowerCase()
  if (hex.length === 0 || hex.length % 2 !== 0 || !/^[0-9a-f]+$/.test(hex)) {
    throw new Error("input must be an even-length hexadecimal string")
  }
  const bytes = Buffer.from(hex, "hex")
  const output = mode === "proto" ? decodeFields(bytes) : parseSppFrames(bytes)
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`)
} catch (error) {
  process.stderr.write(`inspect failed: ${error.message}\n`)
  process.exitCode = 1
}
