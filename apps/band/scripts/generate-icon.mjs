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

function indexedPNG(imageWidth, imageHeight, palette, alpha, indices) {
  const header = Buffer.alloc(13)
  header.writeUInt32BE(imageWidth, 0)
  header.writeUInt32BE(imageHeight, 4)
  header[8] = 8
  header[9] = 3
  const rows = Buffer.alloc((imageWidth + 1) * imageHeight)
  for (let y = 0; y < imageHeight; y += 1) {
    rows[y * (imageWidth + 1)] = 0
    Buffer.from(indices.subarray(y * imageWidth, (y + 1) * imageWidth)).copy(rows, y * (imageWidth + 1) + 1)
  }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", header),
    chunk("PLTE", Buffer.from(palette.flat())),
    chunk("tRNS", Buffer.from(alpha)),
    chunk("IDAT", deflateSync(rows, { level: 9 })),
    chunk("IEND", Buffer.alloc(0))
  ])
}

async function writeIndexed(name, imageWidth, imageHeight, palette, alpha, indices) {
  await writeFile(new URL(`../src/common/${name}`, import.meta.url), indexedPNG(
    imageWidth, imageHeight, palette, alpha, indices
  ))
}

const hudPalette = [[4, 12, 20], [4, 12, 20], [4, 12, 20], [4, 12, 20]]
const shade = new Uint8Array(212 * 96)
for (let y = 0; y < 96; y += 1) {
  const shadeIndex = y < 42 ? 3 : y < 64 ? 2 : y < 82 ? 1 : 0
  shade.fill(shadeIndex, y * 212, (y + 1) * 212)
}
await writeIndexed("nav-shade.png", 212, 96, hudPalette, [0, 72, 150, 225], shade)

function paintCircle(bitmap, imageWidth, imageHeight, centerX, centerY, radius, color) {
  for (let y = Math.floor(centerY - radius); y <= Math.ceil(centerY + radius); y += 1) {
    for (let x = Math.floor(centerX - radius); x <= Math.ceil(centerX + radius); x += 1) {
      if (x >= 0 && x < imageWidth && y >= 0 && y < imageHeight &&
        (x - centerX) ** 2 + (y - centerY) ** 2 <= radius ** 2) bitmap[y * imageWidth + x] = color
    }
  }
}

function paintLine(bitmap, imageWidth, imageHeight, from, to, radius, color) {
  const steps = Math.max(Math.abs(to[0] - from[0]), Math.abs(to[1] - from[1]))
  for (let step = 0; step <= steps; step += 1) {
    const ratio = steps ? step / steps : 0
    paintCircle(bitmap, imageWidth, imageHeight,
      from[0] + (to[0] - from[0]) * ratio,
      from[1] + (to[1] - from[1]) * ratio,
      radius, color)
  }
}

function paintGlyph(lines, circles = []) {
  const bitmap = new Uint8Array(44 * 56)
  for (const color of [1, 2]) {
    const radius = color === 1 ? 5 : 3
    for (const [from, to] of lines) paintLine(bitmap, 44, 56,
      [from[0] + 1, from[1] + 1], [to[0] + 1, to[1] + 1], radius, color)
    for (const [x, y, size] of circles) paintCircle(bitmap, 44, 56, x + 1, y + 1, size + (color === 1 ? 2 : 0), color)
  }
  return bitmap
}

function paintRoundabout() {
  const bitmap = new Uint8Array(44 * 56)
  for (const color of [1, 2]) {
    const thickness = color === 1 ? 5 : 3
    for (let y = 8; y < 41; y += 1) {
      for (let x = 5; x < 39; x += 1) {
        if (Math.abs(Math.hypot(x - 22, y - 24) - 11) <= thickness) bitmap[y * 44 + x] = color
      }
    }
    paintLine(bitmap, 44, 56, [22, 48], [22, 35], thickness, color)
    paintLine(bitmap, 44, 56, [30, 13], [37, 19], thickness, color)
    paintLine(bitmap, 44, 56, [37, 19], [30, 25], thickness, color)
  }
  return bitmap
}

const glyphs = {
  straight: [
    [[[21, 47], [21, 10]], [[21, 10], [11, 22]], [[21, 10], [31, 22]]]
  ],
  left: [
    [[[27, 47], [27, 26]], [[27, 26], [10, 26]], [[10, 26], [20, 16]], [[10, 26], [20, 36]]]
  ],
  right: [
    [[[15, 47], [15, 26]], [[15, 26], [32, 26]], [[32, 26], [22, 16]], [[32, 26], [22, 36]]]
  ],
  uTurn: [
    [[[29, 47], [29, 24]], [[29, 24], [24, 17]], [[24, 17], [16, 17]], [[16, 17], [11, 24]], [[11, 24], [11, 32]], [[11, 32], [5, 25]], [[11, 32], [18, 25]]]
  ],
  roundabout: [
    [[[21, 47], [21, 39]], [[21, 13], [21, 7]], [[21, 7], [13, 15]], [[21, 7], [29, 15]]], [[21, 26, 11]]
  ],
  arrive: [
    [[[21, 47], [21, 32]]], [[21, 20, 10], [21, 20, 4]]
  ]
}
for (const [name, [lines, circles]] of Object.entries(glyphs)) {
  await writeIndexed(`maneuver-${name}.png`, 44, 56,
    [[0, 0, 0], [0, 33, 46], [0, 229, 255]], [0, 255, 255],
    name === "roundabout" ? paintRoundabout() : paintGlyph(lines, circles))
}

function fillPolygon(bitmap, imageWidth, imageHeight, points, color) {
  for (let y = 0; y < imageHeight; y += 1) {
    for (let x = 0; x < imageWidth; x += 1) {
      var inside = false
      for (let current = 0, previous = points.length - 1; current < points.length; previous = current++) {
        const a = points[current], b = points[previous]
        if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside
      }
      if (inside) bitmap[y * imageWidth + x] = color
    }
  }
}

for (let bucket = 0; bucket < 8; bucket += 1) {
  const marker = new Uint8Array(46 * 54)
  fillPolygon(marker, 46, 54, [[23, 3], [43, 48], [3, 48]], 1)
  fillPolygon(marker, 46, 54, [[23, 7], [39, 45], [7, 45]], 2)
  await writeIndexed(`marker-${bucket}.png`, 46, 54,
    [[0, 0, 0], [4, 19, 10], [102, 255, 122]], [0, 255, 255], marker)
}

const destinationPalette = [[0, 0, 0], [55, 32, 3], [255, 178, 24], [255, 244, 194]]
const destinationPin = new Uint8Array(20 * 24)
paintCircle(destinationPin, 20, 24, 10, 9, 8, 1)
paintCircle(destinationPin, 20, 24, 10, 9, 6, 2)
paintCircle(destinationPin, 20, 24, 10, 9, 2, 3)
fillPolygon(destinationPin, 20, 24, [[6, 14], [14, 14], [10, 22]], 1)
fillPolygon(destinationPin, 20, 24, [[8, 14], [12, 14], [10, 19]], 2)
await writeIndexed("destination-pin.png", 20, 24, destinationPalette, [0, 255, 255, 255], destinationPin)

const destinationEdge = new Uint8Array(20 * 20)
paintCircle(destinationEdge, 20, 20, 10, 10, 9, 1)
paintCircle(destinationEdge, 20, 20, 10, 10, 7, 2)
paintCircle(destinationEdge, 20, 20, 10, 10, 4, 0)
paintCircle(destinationEdge, 20, 20, 10, 10, 1.5, 3)
await writeIndexed("destination-edge.png", 20, 20, destinationPalette, [0, 255, 255, 255], destinationEdge)

const destinationTips = [[10, 1], [16, 4], [19, 10], [16, 16], [10, 19], [4, 16], [1, 10], [4, 4]]
function rotate(points, bucket) {
  const angle = bucket * Math.PI / 4
  return points.map(([x, y]) => [
    10 + (x - 10) * Math.cos(angle) - (y - 10) * Math.sin(angle),
    10 + (x - 10) * Math.sin(angle) + (y - 10) * Math.cos(angle)
  ])
}
for (let direction = 0; direction < 8; direction += 1) {
  const chevron = new Uint8Array(20 * 20)
  fillPolygon(chevron, 20, 20, rotate([[10, 1], [19, 13], [14, 13], [10, 9], [6, 13], [1, 13]], direction), 1)
  fillPolygon(chevron, 20, 20, rotate([[10, 4], [16, 11], [13, 11], [10, 8], [7, 11], [4, 11]], direction), 2)
  paintCircle(chevron, 20, 20, destinationTips[direction][0], destinationTips[direction][1], 1, 3)
  await writeIndexed(`destination-edge-${direction}.png`, 20, 20,
    destinationPalette, [0, 255, 255, 255], chevron)
}
