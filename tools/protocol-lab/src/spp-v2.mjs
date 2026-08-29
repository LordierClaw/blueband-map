export function crc16Arc(input) {
  const bytes = Buffer.from(input)
  let crc = 0
  for (const byte of bytes) {
    crc ^= byte
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) === 1 ? (crc >>> 1) ^ 0xa001 : crc >>> 1
    }
  }
  return crc & 0xffff
}

export function parseSppFrames(input) {
  const bytes = Buffer.from(input)
  const frames = []
  let offset = 0

  while (offset < bytes.length) {
    if (bytes.length - offset < 8) {
      throw new Error(`truncated SPP header at offset ${offset}`)
    }
    if (bytes[offset] !== 0xa5 || bytes[offset + 1] !== 0xa5) {
      throw new Error(`invalid SPP magic at offset ${offset}`)
    }

    const payloadLength = bytes.readUInt16LE(offset + 4)
    const frameLength = 8 + payloadLength
    if (bytes.length - offset < frameLength) {
      throw new Error(`truncated SPP payload at offset ${offset}`)
    }
    const expectedCrc = bytes.readUInt16LE(offset + 6)
    const payload = bytes.subarray(offset + 8, offset + frameLength)
    const actualCrc = crc16Arc(payload)
    if (actualCrc !== expectedCrc) {
      throw new Error(`SPP CRC mismatch at offset ${offset}`)
    }

    frames.push({
      type: bytes[offset + 2] & 0x0f,
      sequence: bytes[offset + 3],
      payloadHex: payload.toString("hex")
    })
    offset += frameLength
  }

  return frames
}
