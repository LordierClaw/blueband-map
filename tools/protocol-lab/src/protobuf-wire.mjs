const MAX_FIELD_NUMBER = 536870911n
const MAX_SAFE_BIGINT = BigInt(Number.MAX_SAFE_INTEGER)

export function decodeFields(input) {
  return parseMessage(Buffer.from(input), 0)
}

function parseMessage(bytes, depth) {
  if (depth > 8) {
    throw new Error("protobuf nesting exceeds limit")
  }

  const cursor = { offset: 0 }
  const fields = []
  while (cursor.offset < bytes.length) {
    const key = readVarint(bytes, cursor)
    const number = key >> 3n
    const wireType = Number(key & 7n)
    if (number < 1n || number > MAX_FIELD_NUMBER) {
      throw new Error("invalid protobuf field number")
    }
    const fieldNumber = Number(number)

    if (wireType === 0) {
      const value = readVarint(bytes, cursor)
      fields.push({
        number: fieldNumber,
        wireType,
        value: value <= MAX_SAFE_BIGINT ? Number(value) : value.toString()
      })
    } else if (wireType === 1) {
      requireBytes(bytes, cursor.offset, 8)
      const raw = bytes.subarray(cursor.offset, cursor.offset + 8)
      cursor.offset += 8
      fields.push({
        number: fieldNumber,
        wireType,
        hex: raw.toString("hex"),
        value: raw.readBigUInt64LE().toString()
      })
    } else if (wireType === 2) {
      const lengthValue = readVarint(bytes, cursor)
      if (lengthValue > MAX_SAFE_BIGINT) {
        throw new Error("protobuf field length exceeds safe range")
      }
      const length = Number(lengthValue)
      requireBytes(bytes, cursor.offset, length)
      const raw = bytes.subarray(cursor.offset, cursor.offset + length)
      cursor.offset += length
      const field = { number: fieldNumber, wireType, hex: raw.toString("hex") }
      if (raw.length > 0 && depth < 8) {
        try {
          const children = parseMessage(raw, depth + 1)
          if (children.length > 0) field.children = children
        } catch {
          // Opaque bytes are expected; a failed nested parse is not an outer-message error.
        }
      }
      fields.push(field)
    } else if (wireType === 5) {
      requireBytes(bytes, cursor.offset, 4)
      const raw = bytes.subarray(cursor.offset, cursor.offset + 4)
      cursor.offset += 4
      fields.push({
        number: fieldNumber,
        wireType,
        hex: raw.toString("hex"),
        value: raw.readUInt32LE()
      })
    } else {
      throw new Error(`unsupported protobuf wire type ${wireType}`)
    }
  }
  return fields
}

function readVarint(bytes, cursor) {
  let value = 0n
  for (let index = 0; index < 10; index += 1) {
    requireBytes(bytes, cursor.offset, 1)
    const byte = bytes[cursor.offset]
    cursor.offset += 1
    if (index === 9 && byte > 1) {
      throw new Error("protobuf varint overflow")
    }
    value |= BigInt(byte & 0x7f) << BigInt(index * 7)
    if ((byte & 0x80) === 0) return value
  }
  throw new Error("protobuf varint overflow")
}

function requireBytes(bytes, offset, count) {
  if (count < 0 || offset + count > bytes.length) {
    throw new Error("truncated protobuf field")
  }
}
