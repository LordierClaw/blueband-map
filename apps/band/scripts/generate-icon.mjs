import { deflateSync } from "node:zlib"
import { mkdir, writeFile } from "node:fs/promises"

const width = 256
const height = 256

function crc32(bytes) {
  let crc = 0xffffffff
  for (const byte of bytes) {
    crc ^= byte
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1))
    }
  }
  return (crc ^ 0xffffffff) >>> 0
}

function chunk(type, data) {
  const name = Buffer.from(type, "ascii")
  const length = Buffer.alloc(4)
  length.writeUInt32BE(data.length)
  const checksum = Buffer.alloc(4)
  checksum.writeUInt32BE(crc32(Buffer.concat([name, data])))
  return Buffer.concat([length, name, data, checksum])
}

const pixels = Buffer.alloc((width * 4 + 1) * height)
for (let y = 0; y < height; y += 1) {
  const row = y * (width * 4 + 1)
  for (let x = 0; x < width; x += 1) {
    const offset = row + 1 + x * 4
    const rounded = Math.hypot(Math.max(0, 32 - x, x - 223), Math.max(0, 32 - y, y - 223)) <= 32
    const inB = (x >= 82 && x <= 111 && y >= 55 && y <= 201) ||
      (x >= 105 && x <= 174 && y >= 55 && y <= 84) ||
      (x >= 105 && x <= 174 && y >= 113 && y <= 142) ||
      (x >= 105 && x <= 174 && y >= 172 && y <= 201) ||
      (x >= 155 && x <= 184 && y >= 74 && y <= 123) ||
      (x >= 155 && x <= 184 && y >= 133 && y <= 182)
    pixels[offset] = inB ? 255 : 22
    pixels[offset + 1] = inB ? 255 : 140
    pixels[offset + 2] = inB ? 255 : 255
    pixels[offset + 3] = rounded ? 255 : 0
  }
}

const ihdr = Buffer.alloc(13)
ihdr.writeUInt32BE(width, 0)
ihdr.writeUInt32BE(height, 4)
ihdr[8] = 8
ihdr[9] = 6
const png = Buffer.concat([
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk("IHDR", ihdr),
  chunk("IDAT", deflateSync(pixels, { level: 9 })),
  chunk("IEND", Buffer.alloc(0))
])

const output = new URL("../src/common/icon.png", import.meta.url)
await mkdir(new URL("../src/common/", import.meta.url), { recursive: true })
await writeFile(output, png)
