import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const ASSET = "m1-0123456789abcdef"
const URI = `internal://files/${ASSET}.png`
const DIGEST = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

async function loadPage(connection, file, crypto) {
  const ux = await readFile(new URL("../src/pages/index/index.ux", import.meta.url), "utf8")
  const script = ux.match(/<script>([\s\S]*?)<\/script>/)[1]
    .replace(/import interconnect from ["']@system\.interconnect["']/, "")
    .replace(/import file from ["']@system\.file["']/, "")
    .replace(/import crypto from ["']@system\.crypto["']/, "")
    .replace("export default", "return")
  const component = new Function("interconnect", "file", "crypto", script)(
    { instance() { return connection } }, file, crypto
  )
  const page = structuredClone(component.private)
  for (const [name, value] of Object.entries(component)) if (name !== "private") page[name] = value
  page.onReady()
  return page
}

function envelope(id, topic, body) {
  return { v: 1, id, src: "ios", type: "message", topic, body }
}

function beginBody(overrides = {}) {
  return {
    asset: ASSET,
    bytes: 8,
    width: 212,
    height: 360,
    mime: "image/png",
    sha256: DIGEST,
    ...overrides
  }
}

function fakeCrypto(digest = DIGEST) {
  const hashCalls = []
  return {
    hashCalls,
    atob(value) { return Buffer.from(value, "base64").toString("binary") },
    hashDigest(options) { hashCalls.push(options); return digest }
  }
}

function memoryFile(initial = new Map()) {
  const storage = new Map(initial)
  const writes = []
  const deletes = []
  return {
    storage,
    writes,
    deletes,
    access({ uri, success, fail }) { storage.has(uri) ? success() : fail() },
    delete({ uri, success }) { deletes.push(uri); storage.delete(uri); success() },
    writeArrayBuffer({ uri, buffer, position, success }) {
      writes.push({ uri, buffer, position })
      const existing = storage.get(uri) || new Uint8Array(0)
      const combined = new Uint8Array(Math.max(existing.length, position + buffer.length))
      combined.set(existing)
      combined.set(buffer, position)
      storage.set(uri, combined)
      success()
    }
  }
}

async function readyHarness(file = memoryFile(), crypto = fakeCrypto()) {
  const sent = []
  const page = await loadPage({ send(options) { sent.push(options.data) } }, file, crypto)
  page.unlock()
  return { page, sent, file, crypto }
}

async function pendingPublicationHarness(file = memoryFile(), crypto = fakeCrypto()) {
  const harness = await readyHarness(file, crypto)
  harness.page.receiveMessage({ data: envelope("begin-1", "map.asset.begin", beginBody({ bytes: 4 })) })
  harness.page.receiveMessage({ data: envelope("chunk-1", "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" }) })
  harness.page.receiveMessage({ data: envelope("end-1", "map.asset.end", { asset: ASSET }) })
  return harness
}

test("valid iOS echo is ACKed every time but rendered once", async () => {
  const sent = []
  const page = await loadPage({ send(options) { sent.push(options.data) } })
  page.unlock()
  const message = { v: 1, id: "i-1", src: "ios", type: "message", topic: "system.echo", body: { text: "PING" } }
  page.receiveMessage({ data: message })
  page.receiveMessage({ data: message })
  assert.equal(sent.length, 2)
  assert.deepEqual(sent[0], { v: 1, id: "i-1", src: "band", type: "ack" })
  assert.equal(page.logRows.length, 1)
})

test("rejects invalid source, topic, shape, id and envelopes over 512 bytes", async () => {
  const sent = []
  const page = await loadPage({ send(options) { sent.push(options.data) } })
  page.unlock()
  for (const message of [
    { v: 1, id: "x", src: "band", type: "ack" },
    { v: 1, id: "", src: "ios", type: "ack" },
    { v: 1, id: "x", src: "ios", type: "message", topic: "System.echo", body: {} },
    { v: 1, id: "x", src: "ios", type: "message", topic: "system.echo" },
    { v: 1, id: "x", src: "ios", type: "message", topic: "system.echo", body: { text: "x".repeat(600) } }
  ]) page.receiveMessage({ data: message })
  assert.equal(sent.length, 0)
  assert.equal(page.logRows.length, 0)
})

test("band message uses system.echo and iOS ACK updates its row", async () => {
  const sent = []
  const page = await loadPage({ send(options) { sent.push(options.data) } })
  page.unlock()
  page.sendPing()
  const outgoing = sent[0]
  assert.equal(outgoing.src, "band")
  assert.equal(outgoing.topic, "system.echo")
  page.receiveMessage({ data: { v: 1, id: outgoing.id, src: "ios", type: "ack" } })
  assert.match(page.logText, /✓/)
})

test("receives two ordered chunks, verifies SHA-256 synchronously and publishes M1", async () => {
  const sent = []
  const access = []
  const deletes = []
  const writes = []
  const stored = new Uint8Array(8)
  const crypto = fakeCrypto()
  const file = {
    access(options) { access.push(options) },
    delete(options) { deletes.push(options) },
    writeArrayBuffer(options) {
      writes.push({
        ...options,
        success() {
          stored.set(options.buffer, options.position)
          options.success()
        }
      })
    }
  }
  const page = await loadPage({ send(options) { sent.push(options.data) } }, file, crypto)
  page.unlock()

  page.receiveMessage({ data: envelope("begin-1", "map.asset.begin", beginBody()) })
  assert.equal(sent.length, 0, "begin must wait for access/delete preparation")
  access[0].success()
  assert.equal(sent.length, 0)
  deletes[0].success()
  assert.deepEqual(sent.at(-1), { v: 1, id: "begin-1", src: "band", type: "ack" })
  page.receiveMessage({ data: envelope("begin-1", "map.asset.begin", beginBody()) })
  assert.equal(access.length, 1)
  assert.equal(deletes.length, 1)
  assert.equal(sent.filter(message => message.id === "begin-1").length, 2)

  page.receiveMessage({ data: envelope("chunk-1", "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" }) })
  assert.equal(sent.length, 2, "chunk must wait for write success")
  assert.equal(writes[0].uri, URI)
  assert.equal(writes[0].position, 0)
  assert.ok(writes[0].buffer instanceof Uint8Array)
  assert.deepEqual([...writes[0].buffer], [0, 1, 2, 3])
  writes[0].success()
  assert.deepEqual(sent.at(-1), { v: 1, id: "chunk-1", src: "band", type: "ack" })

  page.receiveMessage({ data: envelope("chunk-2", "map.asset.chunk", { asset: ASSET, offset: 4, data: "+vv8/Q==" }) })
  assert.equal(writes[1].position, 4)
  assert.deepEqual([...writes[1].buffer], [250, 251, 252, 253])
  assert.equal(sent.length, 3)
  writes[1].success()

  page.receiveMessage({ data: envelope("end-1", "map.asset.end", { asset: ASSET }) })
  assert.deepEqual([...stored], [0, 1, 2, 3, 250, 251, 252, 253])
  assert.deepEqual(crypto.hashCalls, [{ uri: URI, algo: "SHA256" }])
  assert.equal(page.mapReady, true)
  assert.equal(page.mapPath, URI)
  assert.equal(page.mapHashPrefix, "01234567")
  assert.deepEqual(sent.at(-1), { v: 1, id: "end-1", src: "band", type: "ack" })
  assert.equal(sent.some(message => message.topic === "map.asset.result"), false)
  page.mapComplete()
  assert.deepEqual(sent.at(-1).body, {
    asset: ASSET,
    status: "ok",
    bytes: 8,
    sha256Prefix: "01234567"
  })
  assert.equal(sent.at(-1).topic, "map.asset.result")
  assert.match(sent.at(-1).id, /^b-[0-9]+-[0-9]+$/)
  const resultCount = sent.filter(message => message.topic === "map.asset.result").length
  page.mapComplete()
  page.mapError()
  assert.equal(sent.filter(message => message.topic === "map.asset.result").length, resultCount)
})

test("deduplicates successful and in-flight asset messages without repeating side effects", async () => {
  const writes = []
  const file = memoryFile()
  file.writeArrayBuffer = options => writes.push(options)
  const { page, sent, crypto } = await readyHarness(file)
  page.receiveMessage({ data: envelope("begin-1", "map.asset.begin", beginBody({ bytes: 4 })) })
  const chunk = envelope("chunk-1", "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" })
  page.receiveMessage({ data: chunk })
  page.receiveMessage({ data: chunk })
  assert.equal(writes.length, 1)
  assert.equal(sent.filter(message => message.id === "chunk-1").length, 0)
  writes[0].success()
  assert.equal(sent.filter(message => message.id === "chunk-1").length, 1)
  page.receiveMessage({ data: chunk })
  assert.equal(writes.length, 1)
  assert.equal(sent.filter(message => message.id === "chunk-1").length, 2)

  page.receiveMessage({ data: envelope("end-1", "map.asset.end", { asset: ASSET }) })
  const resultCount = sent.filter(message => message.topic === "map.asset.result").length
  page.receiveMessage({ data: envelope("end-1", "map.asset.end", { asset: ASSET }) })
  assert.equal(crypto.hashCalls.length, 1)
  assert.equal(sent.filter(message => message.topic === "map.asset.result").length, resultCount)
  assert.equal(sent.filter(message => message.id === "end-1").length, 2)
  page.mapComplete()
  assert.equal(sent.filter(message => message.topic === "map.asset.result").length, 1)
})

test("serializes distinct chunks while coalescing the same in-flight ID", async () => {
  const file = memoryFile()
  const writes = []
  file.writeArrayBuffer = options => writes.push(options)
  const { page, sent } = await readyHarness(file)
  page.receiveMessage({ data: envelope("begin-1", "map.asset.begin", beginBody()) })
  const chunkA = envelope("chunk-a", "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" })
  const busyChunkB = envelope("chunk-b", "map.asset.chunk", { asset: ASSET, offset: 0, data: "+vv8/Q==" })
  page.receiveMessage({ data: chunkA })
  page.receiveMessage({ data: chunkA })
  page.receiveMessage({ data: busyChunkB })
  assert.equal(writes.length, 1)
  assert.equal(writes[0].position, 0)
  assert.equal(sent.at(-1).body.code, "ASSET_BUSY")
  assert.equal(sent.some(message => message.type === "ack" && message.id === "chunk-b"), false)
  writes[0].success()
  assert.equal(page.activeMapOperationID, "")

  page.receiveMessage({
    data: envelope("chunk-b", "map.asset.chunk", { asset: ASSET, offset: 4, data: "+vv8/Q==" })
  })
  assert.equal(writes.length, 2)
  assert.equal(writes[1].position, 4)
  writes[1].success()
  assert.equal(sent.filter(message => message.type === "ack" && message.id === "chunk-b").length, 1)
})

test("connection unlock does not release a held map operation", async () => {
  const file = memoryFile()
  const writes = []
  file.writeArrayBuffer = options => writes.push(options)
  const { page, sent } = await readyHarness(file)
  page.receiveMessage({ data: envelope("begin-1", "map.asset.begin", beginBody()) })
  page.receiveMessage({
    data: envelope("chunk-a", "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" })
  })
  page.unlock()
  page.receiveMessage({
    data: envelope("chunk-b", "map.asset.chunk", { asset: ASSET, offset: 0, data: "+vv8/Q==" })
  })
  assert.equal(writes.length, 1)
  assert.equal(sent.at(-1).body.code, "ASSET_BUSY")
  writes[0].success()
  assert.equal(page.activeMapOperationID, "")
})

test("reports ASSET_RENDER only when image rendering fails and consumes lifecycle once", async () => {
  const { page, sent, file } = await pendingPublicationHarness()
  assert.equal(sent.some(message => message.topic === "map.asset.result"), false)
  page.mapError()
  const results = sent.filter(message => message.topic === "map.asset.result")
  assert.equal(page.mapReady, false)
  assert.equal(results.length, 1)
  assert.deepEqual(results[0].body, {
    asset: ASSET,
    status: "error",
    bytes: 4,
    sha256Prefix: "01234567",
    code: "ASSET_RENDER"
  })
  assert.equal(file.deletes.filter(uri => uri === URI).length, 1)
  page.mapError()
  page.mapComplete()
  assert.equal(sent.filter(message => message.topic === "map.asset.result").length, 1)
  assert.equal(file.deletes.filter(uri => uri === URI).length, 1)
})

test("new begin, lock and destroy discard pending render publication", async () => {
  const newBegin = await pendingPublicationHarness()
  newBegin.page.receiveMessage({
    data: envelope("begin-2", "map.asset.begin", beginBody({ asset: "m1-fedcba9876543210" }))
  })
  newBegin.page.mapComplete()
  assert.equal(newBegin.sent.some(message => message.topic === "map.asset.result"), false)

  const locked = await pendingPublicationHarness()
  locked.page.lock("IOS LINK CLOSED")
  locked.page.mapComplete()
  assert.equal(locked.sent.some(message => message.topic === "map.asset.result"), false)

  const destroyed = await pendingPublicationHarness()
  destroyed.page.onDestroy()
  destroyed.page.mapComplete()
  assert.equal(destroyed.sent.some(message => message.topic === "map.asset.result"), false)
})

test("rejects chunk offset, Base64 and overflow with stable results and no ACK", async () => {
  for (const [id, body, code] of [
    ["bad-offset", { asset: ASSET, offset: 1, data: "AA==" }, "ASSET_OFFSET_INVALID"],
    ["bad-base64", { asset: ASSET, offset: 0, data: "@@@=" }, "ASSET_BASE64_INVALID"],
    ["overflow", { asset: ASSET, offset: 0, data: "AAECAwQ=" }, "ASSET_OVERFLOW"]
  ]) {
    const { page, sent, file } = await readyHarness()
    page.receiveMessage({ data: envelope("begin-1", "map.asset.begin", beginBody({ bytes: 4 })) })
    page.receiveMessage({ data: envelope(id, "map.asset.chunk", body) })
    assert.equal(file.writes.length, 0)
    assert.equal(page.mapReady, false)
    assert.equal(sent.some(message => message.type === "ack" && message.id === id), false)
    assert.equal(sent.at(-1).body.code, code)
  }
})

test("rejects wrong final length, digest mismatch and thrown hash with stable results", async () => {
  for (const scenario of [
    { name: "length", bytes: 8, digest: DIGEST, code: "ASSET_LENGTH_MISMATCH" },
    { name: "digest", bytes: 4, digest: "f".repeat(64), code: "ASSET_DIGEST_MISMATCH" },
    { name: "hash", bytes: 4, digest: null, code: "ASSET_HASH_FAILED" }
  ]) {
    const file = memoryFile()
    const crypto = fakeCrypto(scenario.digest || DIGEST)
    if (scenario.digest === null) crypto.hashDigest = options => { crypto.hashCalls.push(options); throw new Error("hash") }
    const { page, sent } = await readyHarness(file, crypto)
    page.receiveMessage({ data: envelope("begin-1", "map.asset.begin", beginBody({ bytes: scenario.bytes })) })
    page.receiveMessage({ data: envelope("chunk-1", "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" }) })
    page.receiveMessage({ data: envelope(`end-${scenario.name}`, "map.asset.end", { asset: ASSET }) })
    assert.equal(page.mapReady, false)
    assert.equal(sent.at(-1).body.code, scenario.code)
    assert.equal(sent.some(message => message.type === "ack" && message.id === `end-${scenario.name}`), false)
  }
})

test("write failure is retryable with the same ID and ACKs only corrected success", async () => {
  const file = memoryFile()
  let failFirst = true
  file.writeArrayBuffer = options => {
    file.writes.push(options)
    if (failFirst) {
      failFirst = false
      options.fail()
    } else options.success()
  }
  const { page, sent } = await readyHarness(file)
  page.receiveMessage({ data: envelope("begin-1", "map.asset.begin", beginBody({ bytes: 4 })) })
  const chunk = envelope("retry-1", "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" })
  page.receiveMessage({ data: chunk })
  assert.equal(sent.at(-1).body.code, "ASSET_WRITE_FAILED")
  assert.equal(sent.some(message => message.type === "ack" && message.id === "retry-1"), false)
  page.receiveMessage({ data: chunk })
  assert.equal(file.writes.length, 2)
  assert.equal(sent.filter(message => message.type === "ack" && message.id === "retry-1").length, 1)
})

test("validates every begin field, enforces one transfer and prepares files safely", async () => {
  const invalidBodies = [
    beginBody({ asset: "m1-0123456789abcdeG" }),
    beginBody({ bytes: 0 }), beginBody({ bytes: 1.5 }), beginBody({ bytes: 200 * 1024 + 1 }),
    beginBody({ width: 211 }), beginBody({ width: 212.5 }),
    beginBody({ height: 359 }), beginBody({ height: 360.5 }),
    beginBody({ mime: "image/jpeg" }),
    beginBody({ sha256: "A".repeat(64) }), beginBody({ sha256: "a".repeat(63) })
  ]
  for (const [index, body] of invalidBodies.entries()) {
    let touched = false
    const file = { access() { touched = true } }
    const { page, sent } = await readyHarness(file)
    page.receiveMessage({ data: envelope(`invalid-${index}`, "map.asset.begin", body) })
    assert.equal(touched, false)
    assert.equal(sent.at(-1).body.code, "ASSET_BEGIN_INVALID")
    assert.equal(page.activeTransfer, null)
  }

  const { page, sent } = await readyHarness()
  page.receiveMessage({ data: envelope("begin-1", "map.asset.begin", beginBody()) })
  page.receiveMessage({ data: envelope("begin-2", "map.asset.begin", beginBody({ asset: "m1-fedcba9876543210" })) })
  assert.equal(sent.at(-1).body.code, "ASSET_BUSY")

  const pendingAccess = []
  const pendingFile = { access(options) { pendingAccess.push(options) } }
  const pending = await readyHarness(pendingFile)
  pending.page.receiveMessage({ data: envelope("pending-1", "map.asset.begin", beginBody()) })
  pending.page.receiveMessage({ data: envelope("pending-2", "map.asset.begin", beginBody({ asset: "m1-fedcba9876543210" })) })
  assert.equal(pendingAccess.length, 1)
  assert.equal(pending.sent.at(-1).body.code, "ASSET_BUSY")

  const deleteFile = memoryFile(new Map([[URI, new Uint8Array([9])]]))
  deleteFile.delete = ({ uri, fail }) => { deleteFile.deletes.push(uri); fail() }
  const failed = await readyHarness(deleteFile)
  failed.page.receiveMessage({ data: envelope("delete-1", "map.asset.begin", beginBody()) })
  assert.equal(failed.page.activeTransfer, null)
  assert.equal(failed.sent.at(-1).body.code, "ASSET_DELETE_FAILED")
  assert.equal(failed.sent.some(message => message.type === "ack" && message.id === "delete-1"), false)
})

test("bounds successful deduplication IDs to 64", async () => {
  const { page } = await readyHarness()
  for (let index = 0; index < 66; index += 1) {
    page.receiveMessage({ data: envelope(`echo-${index}`, "system.echo", { text: "PING" }) })
  }
  assert.equal(page.recentIDs.length, 64)
  assert.equal(page.recentIDs[0], "echo-2")
})
