import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { readFile } from "node:fs/promises"
import test from "node:test"

const ASSET = "m1-0123456789abcdef"
const ASSET_B = "m1-fedcba9876543210"
const URI = `internal://files/${ASSET}.png`
const DIGEST = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const RUN = "run-0123456789abcdef"
const RUN_B = "run-fedcba9876543210"

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
  const correlated = topic.startsWith("map.asset.") && !("run" in body) ? { ...body, run: RUN } : body
  return { v: 1, id, src: "ios", type: "message", topic, body: correlated }
}

function beginBody(overrides = {}) {
  return {
    asset: ASSET,
    bytes: 8,
    width: 212,
    height: 360,
    mime: "image/png",
    sha256: DIGEST,
    run: RUN,
    ...overrides
  }
}

test("map transfer requires one bounded run ID and result round-trips it exactly", async () => {
  const { page, sent } = await readyHarness()
  const begin = envelope("run-begin", "map.asset.begin", beginBody({ bytes: 4 }))
  const chunk = envelope("run-chunk", "map.asset.chunk", {
    asset: ASSET, offset: 0, data: "AAECAw==", run: RUN
  })
  const end = envelope("run-end", "map.asset.end", { asset: ASSET, run: RUN })

  page.receiveMessage({ data: begin })
  page.receiveMessage({ data: chunk })
  page.receiveMessage({ data: end })
  page.mapComplete(pendingToken(page))

  const result = sent.findLast(message => message.topic === "map.asset.result")
  assert.equal(result.body.run, RUN)
  assert.deepEqual(begin.body, {
    asset: ASSET, bytes: 4, width: 212, height: 360,
    mime: "image/png", sha256: DIGEST, run: RUN
  })
  assert.deepEqual(chunk.body, { asset: ASSET, offset: 0, data: "AAECAw==", run: RUN })
  assert.deepEqual(end.body, { asset: ASSET, run: RUN })
  assertBoundedBandEnvelopes(page, sent)
})

test("rejects missing invalid or changed map run correlation", async () => {
  for (const run of [undefined, "", "UPPER", "run_under", "é", "r".repeat(25)]) {
    const { page, sent } = await readyHarness()
    page.receiveMessage({ data: envelope("invalid-run", "map.asset.begin", beginBody({ run })) })
    const result = sent.find(message => message.topic === "map.asset.result")
    assert.equal(result?.body.code, "ASSET_BEGIN_INVALID")
  }

  const { page, sent } = await readyHarness()
  page.receiveMessage({ data: envelope("begin", "map.asset.begin", beginBody({ bytes: 4 })) })
  page.receiveMessage({ data: envelope("chunk", "map.asset.chunk", {
    asset: ASSET, offset: 0, data: "AAECAw==", run: RUN_B
  }) })
  const result = sent.findLast(message => message.topic === "map.asset.result")
  assert.equal(result.body.code, "ASSET_RUN_MISMATCH")
  assert.equal(result.body.run, RUN_B)
})

function fakeCrypto(digest = DIGEST) {
  const hashCalls = []
  return {
    hashCalls,
    atob(value) { return Buffer.from(value, "base64").toString("binary") },
    hashDigest(options) { hashCalls.push(options); return digest }
  }
}

function memoryHashCrypto(file) {
  const hashCalls = []
  return {
    hashCalls,
    atob(value) { return Buffer.from(value, "base64").toString("binary") },
    hashDigest(options) {
      hashCalls.push(options)
      return createHash("sha256").update(Buffer.from(file.storage.get(options.uri))).digest("hex")
    }
  }
}

function pendingToken(page) {
  assert.equal(typeof page.pendingPublication?.token, "string")
  return page.pendingPublication.token
}

function assertBoundedBandEnvelopes(page, sent) {
  for (const message of sent) {
    assert.ok(page.utf8Length(JSON.stringify(message)) <= 512, JSON.stringify(message))
  }
}

function memoryFile(initial = new Map()) {
  const storage = new Map(initial)
  const accesses = []
  const writes = []
  const deletes = []
  return {
    storage,
    accesses,
    writes,
    deletes,
    access({ uri, success, fail }) { accesses.push(uri); storage.has(uri) ? success() : fail() },
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
  const token = pendingToken(page)
  page.mapComplete(token)
  assert.deepEqual(sent.at(-1).body, {
    asset: ASSET,
    run: RUN,
    status: "ok",
    bytes: 8,
    sha256Prefix: "01234567"
  })
  assert.equal(sent.at(-1).topic, "map.asset.result")
  assert.match(sent.at(-1).id, /^b-[0-9]+-[0-9]+$/)
  const resultCount = sent.filter(message => message.topic === "map.asset.result").length
  page.mapComplete(token)
  page.mapError(token)
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
  assert.equal(page.activeMapOperationID, "end-1")
  page.mapComplete(pendingToken(page))
  assert.equal(sent.filter(message => message.topic === "map.asset.result").length, 1)
  assert.equal(page.activeMapOperationID, "")
})

test("holds asset A ownership through rendering and blocks the full asset B sequence", async () => {
  const { page, sent, file, crypto } = await pendingPublicationHarness()
  const pathA = page.mapPath
  const pendingA = structuredClone(page.pendingPublication)
  assert.equal(page.activeMapOperationID, "end-1")

  page.receiveMessage({ data: envelope("begin-b", "map.asset.begin", beginBody({ asset: ASSET_B, bytes: 4 })) })
  page.receiveMessage({
    data: envelope("chunk-b", "map.asset.chunk", { asset: ASSET_B, offset: 0, data: "AAECAw==" })
  })
  page.receiveMessage({ data: envelope("end-b", "map.asset.end", { asset: ASSET_B }) })

  const busyResults = sent.filter(message => message.topic === "map.asset.result" && message.body.code === "ASSET_BUSY")
  assert.equal(busyResults.length, 3)
  for (const result of busyResults) {
    assert.deepEqual(result.body, {
      asset: ASSET_B,
      run: RUN,
      status: "error",
      bytes: 0,
      sha256Prefix: "",
      code: "ASSET_BUSY"
    })
  }
  assert.equal(file.accesses.length, 1)
  assert.equal(file.writes.length, 1)
  assert.equal(crypto.hashCalls.length, 1)
  assert.equal(page.mapPath, pathA)
  assert.deepEqual(page.pendingPublication, pendingA)

  page.receiveMessage({ data: envelope("end-1", "map.asset.end", { asset: ASSET }) })
  assert.equal(sent.filter(message => message.type === "ack" && message.id === "end-1").length, 2)
  assert.equal(crypto.hashCalls.length, 1)
  page.mapComplete(pendingA.token)
  const okResults = sent.filter(message => message.topic === "map.asset.result" && message.body.status === "ok")
  assert.equal(okResults.length, 1)
  assert.equal(okResults[0].body.asset, ASSET)
  assert.equal(page.activeMapOperationID, "")

  page.receiveMessage({ data: envelope("begin-b-retry", "map.asset.begin", beginBody({ asset: ASSET_B, bytes: 4 })) })
  assert.equal(file.accesses.length, 2)
  assert.equal(page.activeTransfer.asset, ASSET_B)
  assert.equal(sent.filter(message => message.type === "ack" && message.id === "begin-b-retry").length, 1)
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
  assert.equal(sent.at(-2).body.code, "ASSET_BUSY")
  assert.equal(sent.filter(message => message.type === "ack" && message.id === "chunk-b").length, 1)
  writes[0].success()
  assert.equal(page.activeMapOperationID, "")

  page.receiveMessage({
    data: envelope("chunk-b-retry", "map.asset.chunk", { asset: ASSET, offset: 4, data: "+vv8/Q==" })
  })
  assert.equal(writes.length, 2)
  assert.equal(writes[1].position, 4)
  writes[1].success()
  assert.equal(sent.filter(message => message.type === "ack" && message.id === "chunk-b-retry").length, 1)
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
  assert.equal(sent.at(-2).body.code, "ASSET_BUSY")
  writes[0].success()
  assert.equal(page.activeMapOperationID, "")
})

test("reports ASSET_RENDER only when image rendering fails and consumes lifecycle once", async () => {
  const { page, sent, file } = await pendingPublicationHarness()
  assert.equal(sent.some(message => message.topic === "map.asset.result"), false)
  const token = pendingToken(page)
  page.mapError(token)
  const results = sent.filter(message => message.topic === "map.asset.result")
  assert.equal(page.mapReady, false)
  assert.equal(results.length, 1)
  assert.deepEqual(results[0].body, {
    asset: ASSET,
    run: RUN,
    status: "error",
    bytes: 4,
    sha256Prefix: "01234567",
    code: "ASSET_RENDER"
  })
  assert.equal(file.deletes.filter(uri => uri === URI).length, 1)
  assert.equal(page.activeMapOperationID, "")
  page.receiveMessage({ data: envelope("begin-b", "map.asset.begin", beginBody({ asset: ASSET_B, bytes: 4 })) })
  assert.equal(page.activeTransfer.asset, ASSET_B)
  page.mapError(token)
  page.mapComplete(token)
  assert.equal(sent.filter(message => message.topic === "map.asset.result").length, 1)
  assert.equal(file.deletes.filter(uri => uri === URI).length, 1)
})

test("lock and destroy discard pending render publication", async () => {
  const locked = await pendingPublicationHarness()
  const lockedToken = pendingToken(locked.page)
  locked.page.lock("IOS LINK CLOSED")
  locked.page.mapComplete(lockedToken)
  assert.equal(locked.sent.some(message => message.topic === "map.asset.result"), false)
  assert.equal(locked.page.activeMapOperationID, "")

  const destroyed = await pendingPublicationHarness()
  const destroyedToken = pendingToken(destroyed.page)
  destroyed.page.onDestroy()
  destroyed.page.mapComplete(destroyedToken)
  assert.equal(destroyed.sent.some(message => message.topic === "map.asset.result"), false)
  assert.equal(destroyed.page.activeMapOperationID, "")
})

test("rejects chunk offset, Base64 and overflow with stable results and ACK", async () => {
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
    assert.equal(sent.filter(message => message.type === "ack" && message.id === id).length, 1)
    assert.equal(sent.at(-2).body.code, code)
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
    assert.equal(sent.at(-2).body.code, scenario.code)
    assert.equal(sent.filter(message => message.type === "ack" && message.id === `end-${scenario.name}`).length, 1)
  }
})

test("handled write failure is deduplicated and corrected retry requires a new ID", async () => {
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
  assert.equal(sent.at(-2).body.code, "ASSET_WRITE_FAILED")
  assert.equal(sent.filter(message => message.type === "ack" && message.id === "retry-1").length, 1)
  page.receiveMessage({ data: chunk })
  assert.equal(file.writes.length, 1)
  assert.equal(sent.filter(message => message.type === "ack" && message.id === "retry-1").length, 2)
  page.receiveMessage({ data: envelope("retry-2", "map.asset.chunk", chunk.body) })
  assert.equal(file.writes.length, 2)
  assert.equal(sent.filter(message => message.type === "ack" && message.id === "retry-2").length, 1)
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
    assert.equal(sent.at(-2).body.code, "ASSET_BEGIN_INVALID")
    assert.equal(page.activeTransfer, null)
  }

  const { page, sent } = await readyHarness()
  page.receiveMessage({ data: envelope("begin-1", "map.asset.begin", beginBody()) })
  page.receiveMessage({ data: envelope("begin-2", "map.asset.begin", beginBody({ asset: "m1-fedcba9876543210" })) })
  assert.equal(sent.at(-2).body.code, "ASSET_BUSY")

  const pendingAccess = []
  const pendingFile = { access(options) { pendingAccess.push(options) } }
  const pending = await readyHarness(pendingFile)
  pending.page.receiveMessage({ data: envelope("pending-1", "map.asset.begin", beginBody()) })
  pending.page.receiveMessage({ data: envelope("pending-2", "map.asset.begin", beginBody({ asset: "m1-fedcba9876543210" })) })
  assert.equal(pendingAccess.length, 1)
  assert.equal(pending.sent.at(-2).body.code, "ASSET_BUSY")

  const deleteFile = memoryFile(new Map([[URI, new Uint8Array([9])]]))
  deleteFile.delete = ({ uri, fail }) => { deleteFile.deletes.push(uri); fail() }
  const failed = await readyHarness(deleteFile)
  failed.page.receiveMessage({ data: envelope("delete-1", "map.asset.begin", beginBody()) })
  assert.equal(failed.page.activeTransfer, null)
  assert.equal(failed.sent.at(-2).body.code, "ASSET_DELETE_FAILED")
  assert.equal(failed.sent.filter(message => message.type === "ack" && message.id === "delete-1").length, 1)
})

test("bounds successful deduplication IDs to 64", async () => {
  const { page } = await readyHarness()
  for (let index = 0; index < 66; index += 1) {
    page.receiveMessage({ data: envelope(`echo-${index}`, "system.echo", { text: "PING" }) })
  }
  assert.equal(page.recentIDs.length, 64)
  assert.equal(page.recentIDs[0], "echo-2")
})

test("lifecycle teardown makes pending access, delete and write callbacks inert and allows reconnect", async () => {
  for (const lifecycle of ["lock", "onDestroy"]) {
    for (const stage of ["access", "delete", "write"]) {
      const pending = { access: [], delete: [], write: [] }
      let controlled = true
      const file = {
        access(options) {
          if (controlled && stage === "access") pending.access.push(options)
          else if (controlled && stage === "delete") options.success()
          else options.fail()
        },
        delete(options) {
          if (controlled && stage === "delete") pending.delete.push(options)
          else options.success()
        },
        writeArrayBuffer(options) {
          if (controlled && stage === "write") pending.write.push(options)
          else options.success()
        }
      }
      const { page, sent } = await readyHarness(file)
      page.receiveMessage({ data: envelope(`${lifecycle}-${stage}-begin`, "map.asset.begin", beginBody({ bytes: 4 })) })
      if (stage === "write") {
        page.receiveMessage({
          data: envelope(`${lifecycle}-${stage}-chunk`, "map.asset.chunk", {
            asset: ASSET, offset: 0, data: "AAECAw=="
          })
        })
      }
      const callback = pending[stage][0]
      assert.ok(callback, `${lifecycle} ${stage} callback must be pending`)
      const sentBefore = sent.length
      const epochBefore = page.lifecycleEpoch
      if (lifecycle === "lock") page.lock("IOS LINK CLOSED")
      else page.onDestroy()
      assert.equal(page.lifecycleEpoch, epochBefore + 1)
      callback.success()
      if (callback.fail) callback.fail()
      assert.equal(sent.length, sentBefore)
      assert.equal(page.activeMapOperationID, "")
      assert.equal(page.activeTransfer, null)
      assert.equal(page.pendingPublication, null)
      assert.equal(page.mapReady, false)

      controlled = false
      const liveHarness = lifecycle === "onDestroy" ? await readyHarness(file) : null
      const livePage = liveHarness ? liveHarness.page : page
      const liveSent = liveHarness ? liveHarness.sent : sent
      if (lifecycle === "lock") livePage.unlock()
      const freshID = `${lifecycle}-${stage}-fresh`
      livePage.receiveMessage({ data: envelope(freshID, "map.asset.begin", beginBody({ bytes: 4 })) })
      assert.equal(livePage.activeTransfer.asset, ASSET)
      assert.equal(liveSent.filter(message => message.type === "ack" && message.id === freshID).length, 1)
    }
  }
})

test("immutable render token ignores stale A events while B remains pending", async () => {
  const harness = await pendingPublicationHarness()
  const { page, sent } = harness
  const tokenA = pendingToken(page)
  page.lock("IOS LINK CLOSED")
  page.unlock()
  page.receiveMessage({ data: envelope("begin-b", "map.asset.begin", beginBody({ asset: ASSET_B, bytes: 4 })) })
  page.receiveMessage({
    data: envelope("chunk-b", "map.asset.chunk", { asset: ASSET_B, offset: 0, data: "AAECAw==" })
  })
  page.receiveMessage({ data: envelope("end-b", "map.asset.end", { asset: ASSET_B }) })
  const tokenB = pendingToken(page)
  assert.notEqual(tokenB, tokenA)
  const pendingB = structuredClone(page.pendingPublication)
  const resultCount = sent.filter(message => message.topic === "map.asset.result").length

  page.mapComplete(tokenA)
  page.mapError(tokenA)
  assert.deepEqual(page.pendingPublication, pendingB)
  assert.equal(page.activeMapOperationID, "end-b")
  assert.equal(page.mapPath, `internal://files/${ASSET_B}.png`)
  assert.equal(sent.filter(message => message.topic === "map.asset.result").length, resultCount)

  page.mapComplete(tokenB)
  const results = sent.filter(message => message.topic === "map.asset.result")
  assert.equal(results.at(-1).body.status, "ok")
  assert.equal(results.at(-1).body.asset, ASSET_B)
  assert.equal(page.activeMapOperationID, "")
})

test("render error token releases ownership and stale callbacks cannot consume the next publication", async () => {
  const { page, sent } = await pendingPublicationHarness()
  const tokenA = pendingToken(page)
  page.mapError(tokenA)
  assert.equal(page.activeMapOperationID, "")
  page.receiveMessage({ data: envelope("begin-b", "map.asset.begin", beginBody({ asset: ASSET_B, bytes: 4 })) })
  page.receiveMessage({ data: envelope("chunk-b", "map.asset.chunk", { asset: ASSET_B, offset: 0, data: "AAECAw==" }) })
  page.receiveMessage({ data: envelope("end-b", "map.asset.end", { asset: ASSET_B }) })
  const tokenB = pendingToken(page)
  page.mapComplete(tokenA)
  page.mapError(tokenA)
  assert.equal(page.pendingPublication.token, tokenB)
  page.mapError(tokenB)
  const errors = sent.filter(message => message.topic === "map.asset.result" && message.body.code === "ASSET_RENDER")
  assert.equal(errors.length, 2)
  assert.equal(errors.at(-1).body.asset, ASSET_B)
  assert.equal(page.activeMapOperationID, "")
})

test("confirmed map survives lifecycle reset while an unconfirmed map is hidden and deleted", async () => {
  const confirmed = await pendingPublicationHarness()
  const token = pendingToken(confirmed.page)
  confirmed.page.mapComplete(token)
  const deleteCount = confirmed.file.deletes.length
  confirmed.page.lock("IOS LINK CLOSED")
  assert.equal(confirmed.file.deletes.length, deleteCount)
  assert.equal(confirmed.page.mapReady, true)
  assert.equal(confirmed.page.mapPath, URI)

  const unconfirmed = await pendingPublicationHarness()
  unconfirmed.page.lock("IOS LINK CLOSED")
  assert.equal(unconfirmed.page.mapReady, false)
  assert.deepEqual(unconfirmed.page.renderItems, [])
  assert.equal(unconfirmed.file.deletes.filter(uri => uri === URI).length, 1)
})

test("handled failures ACK once, deduplicate result side effects, and bound adversarial result envelopes", async () => {
  const { page, sent } = await readyHarness()
  const invalidAssets = ["x".repeat(220), "地図".repeat(40), "m1-0123456789abcdeG"]
  for (const [index, asset] of invalidAssets.entries()) {
    const id = `invalid-asset-${index}`
    const request = envelope(id, "map.asset.begin", beginBody({ asset }))
    assert.ok(page.utf8Length(JSON.stringify(request)) <= 512)
    page.receiveMessage({ data: request })
    const resultCount = sent.filter(message => message.topic === "map.asset.result").length
    page.receiveMessage({ data: request })
    assert.equal(sent.filter(message => message.type === "ack" && message.id === id).length, 2)
    assert.equal(sent.filter(message => message.topic === "map.asset.result").length, resultCount)
    assert.equal(sent.findLast(message => message.topic === "map.asset.result").body.asset, "")
  }
  assertBoundedBandEnvelopes(page, sent)
})

test("hashes realistic memory-file bytes synchronously before render publication", async () => {
  const file = memoryFile()
  const crypto = memoryHashCrypto(file)
  const bytes = new Uint8Array([0, 1, 2, 3])
  const digest = createHash("sha256").update(bytes).digest("hex")
  const { page, sent } = await readyHarness(file, crypto)
  page.receiveMessage({ data: envelope("real-begin", "map.asset.begin", beginBody({ bytes: 4, sha256: digest })) })
  page.receiveMessage({ data: envelope("real-chunk", "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" }) })
  page.receiveMessage({ data: envelope("real-end", "map.asset.end", { asset: ASSET }) })
  assert.deepEqual(crypto.hashCalls, [{ uri: URI, algo: "SHA256" }])
  assert.equal(sent.some(message => message.topic === "map.asset.result"), false)
  page.mapComplete(pendingToken(page))
  assert.equal(sent.at(-1).body.sha256Prefix, digest.slice(0, 8))
})

test("same-asset replacement keeps deletion ownership across lifecycle reset", async () => {
  const file = memoryFile()
  const harness = await pendingPublicationHarness(file)
  const { page, sent } = harness
  page.mapComplete(pendingToken(page))
  assert.equal(page.mapReady, true)

  const heldDeletes = []
  file.delete = options => { heldDeletes.push(options) }
  const accessCount = file.accesses.length
  page.receiveMessage({ data: envelope("replace-begin", "map.asset.begin", beginBody({ bytes: 4 })) })
  assert.equal(heldDeletes.length, 1)
  assert.deepEqual(page.pendingDeleteURIs, [URI])
  assert.equal(page.confirmedMap, null)
  assert.equal(page.mapReady, false)
  assert.equal(page.mapPath, "")
  assert.deepEqual(page.renderItems, [])

  page.lock("IOS LINK CLOSED")
  assert.deepEqual(page.pendingDeleteURIs, [URI])
  assert.equal(heldDeletes.length, 1, "reset must not schedule a duplicate delete")
  assert.equal(page.mapReady, false)
  page.unlock()
  page.receiveMessage({ data: envelope("replace-blocked", "map.asset.begin", beginBody({ bytes: 4 })) })
  assert.equal(file.accesses.length, accessCount + 1, "blocked retry must not call access")
  assert.equal(sent.at(-2).body.code, "ASSET_BUSY")
  assert.equal(sent.at(-1).id, "replace-blocked")

  file.storage.delete(URI)
  heldDeletes[0].success()
  assert.deepEqual(page.pendingDeleteURIs, [])
  page.receiveMessage({ data: envelope("replace-allowed", "map.asset.begin", beginBody({ bytes: 4 })) })
  assert.equal(file.accesses.length, accessCount + 2)
  assert.equal(page.activeTransfer.asset, ASSET)
  assert.equal(sent.at(-1).id, "replace-allowed")
})

test("delayed best-effort cleanup blocks same URI retry until callback completion", async () => {
  for (const completion of ["success", "fail"]) {
    const file = memoryFile()
    const heldDeletes = []
    file.delete = options => { heldDeletes.push(options) }
    const crypto = fakeCrypto("f".repeat(64))
    const { page, sent } = await readyHarness(file, crypto)
    page.receiveMessage({ data: envelope(`${completion}-begin`, "map.asset.begin", beginBody({ bytes: 4 })) })
    page.receiveMessage({ data: envelope(`${completion}-chunk`, "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" }) })
    page.receiveMessage({ data: envelope(`${completion}-end`, "map.asset.end", { asset: ASSET }) })
    assert.equal(heldDeletes.length, 1)
    assert.deepEqual(page.pendingDeleteURIs, [URI])
    const accessCount = file.accesses.length

    page.receiveMessage({ data: envelope(`${completion}-blocked`, "map.asset.begin", beginBody({ bytes: 4 })) })
    assert.equal(file.accesses.length, accessCount)
    assert.equal(sent.at(-2).body.code, "ASSET_BUSY")
    heldDeletes[0][completion]()
    assert.deepEqual(page.pendingDeleteURIs, [])

    page.receiveMessage({ data: envelope(`${completion}-allowed`, "map.asset.begin", beginBody({ bytes: 4 })) })
    assert.equal(file.accesses.length, accessCount + 1)
  }
})

test("delete registry clears on synchronous throw and never schedules duplicate URI cleanup", async () => {
  const file = memoryFile()
  file.delete = () => { throw new Error("delete") }
  const crypto = fakeCrypto("f".repeat(64))
  const { page } = await readyHarness(file, crypto)
  page.receiveMessage({ data: envelope("throw-begin", "map.asset.begin", beginBody({ bytes: 4 })) })
  page.receiveMessage({ data: envelope("throw-chunk", "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" }) })
  page.receiveMessage({ data: envelope("throw-end", "map.asset.end", { asset: ASSET }) })
  assert.deepEqual(page.pendingDeleteURIs, [])
  page.deleteBestEffort(URI)
  page.deleteBestEffort(URI)
  assert.deepEqual(page.pendingDeleteURIs, [])
})

test("repeated readiness while connected preserves dedup side effects until a real new session", async () => {
  const sent = []
  const file = memoryFile()
  const connection = {
    send(options) { sent.push(options.data) },
    getReadyState({ success }) { success({ status: 1 }) }
  }
  const page = await loadPage(connection, file, fakeCrypto())
  page.unlock()
  const echo = envelope("stable-echo", "system.echo", { text: "PING" })
  const begin = envelope("stable-begin", "map.asset.begin", beginBody({ bytes: 4 }))
  const chunk = envelope("stable-chunk", "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" })
  page.receiveMessage({ data: echo })
  page.receiveMessage({ data: begin })
  page.receiveMessage({ data: chunk })
  const accessCount = file.accesses.length
  const writeCount = file.writes.length
  const resultCount = sent.filter(message => message.topic === "map.asset.result").length

  page.checkConnection()
  page.receiveMessage({ data: echo })
  page.receiveMessage({ data: begin })
  page.receiveMessage({ data: chunk })
  assert.equal(file.accesses.length, accessCount)
  assert.equal(file.writes.length, writeCount)
  assert.equal(sent.filter(message => message.topic === "map.asset.result").length, resultCount)
  for (const id of [echo.id, begin.id, chunk.id]) {
    assert.equal(sent.filter(message => message.type === "ack" && message.id === id).length, 2)
  }
  assert.equal(page.logRows.length, 0, "repeated check may clear diagnostics but must not rerender duplicate echo")

  page.lock("IOS LINK CLOSED")
  page.unlock()
  page.receiveMessage({ data: echo })
  assert.equal(page.logRows.length, 1, "new interconnect session may clear dedup history")
})

test("delayed readiness callbacks after lock or destroy are lifecycle-inert", async () => {
  for (const lifecycle of ["lock", "onDestroy"]) {
    for (const outcome of ["success", "fail"]) {
      const readyCallbacks = []
      const sent = []
      const connection = {
        send(options) { sent.push(options.data) },
        getReadyState(options) { readyCallbacks.push(options) }
      }
      const page = await loadPage(connection, memoryFile(), fakeCrypto())
      page.unlock()
      page.checkConnection()
      assert.equal(readyCallbacks.length, 1)
      const epoch = page.lifecycleEpoch
      if (lifecycle === "lock") page.lock("IOS LINK CLOSED")
      else page.onDestroy()
      const status = page.statusText
      assert.equal(page.lifecycleEpoch, epoch + 1)
      if (outcome === "success") readyCallbacks[0].success({ status: 1 })
      else readyCallbacks[0].fail({}, 99)
      assert.equal(page.connected, false)
      assert.equal(page.acceptingMessages, false)
      assert.equal(page.statusText, status)
      assert.equal(sent.length, 0)
    }
  }
})

test("queued asset and echo messages after lock or destroy have no side effects", async () => {
  for (const lifecycle of ["lock", "onDestroy"]) {
    const sent = []
    const file = memoryFile()
    const connection = { send(options) { sent.push(options.data) } }
    const page = await loadPage(connection, file, fakeCrypto())
    page.unlock()
    if (lifecycle === "lock") page.lock("IOS LINK CLOSED")
    else page.onDestroy()
    const snapshot = {
      accesses: file.accesses.length,
      writes: file.writes.length,
      deletes: file.deletes.length,
      sent: sent.length,
      logRows: page.logRows.length,
      statusText: page.statusText,
      epoch: page.lifecycleEpoch
    }
    page.receiveMessage({ data: envelope(`${lifecycle}-begin`, "map.asset.begin", beginBody({ bytes: 4 })) })
    page.receiveMessage({ data: envelope(`${lifecycle}-chunk`, "map.asset.chunk", { asset: ASSET, offset: 0, data: "AAECAw==" }) })
    page.receiveMessage({ data: envelope(`${lifecycle}-echo`, "system.echo", { text: "QUEUED" }) })
    assert.deepEqual({
      accesses: file.accesses.length,
      writes: file.writes.length,
      deletes: file.deletes.length,
      sent: sent.length,
      logRows: page.logRows.length,
      statusText: page.statusText,
      epoch: page.lifecycleEpoch
    }, snapshot)
    assert.equal(page.activeTransfer, null)
    assert.equal(page.activeMapOperationID, "")
  }
})

test("stale interconnect handlers are inert and a new live page can unlock", async () => {
  const oldSent = []
  const oldConnection = {
    send(options) { oldSent.push(options.data) },
    getReadyState({ success }) { success({ status: 1 }) }
  }
  const oldPage = await loadPage(oldConnection, memoryFile(), fakeCrypto())
  const staleHandlers = {
    open: oldConnection.onopen,
    close: oldConnection.onclose,
    error: oldConnection.onerror,
    message: oldConnection.onmessage
  }
  oldPage.onDestroy()
  const oldStatus = oldPage.statusText
  const oldEpoch = oldPage.lifecycleEpoch
  staleHandlers.open()
  staleHandlers.close()
  staleHandlers.error()
  staleHandlers.message({ data: envelope("stale-echo", "system.echo", { text: "STALE" }) })
  assert.equal(oldPage.statusText, oldStatus)
  assert.equal(oldPage.lifecycleEpoch, oldEpoch)
  assert.equal(oldSent.length, 0)

  const sent = []
  const connection = {
    send(options) { sent.push(options.data) },
    getReadyState({ success }) { success({ status: 1 }) }
  }
  const page = await loadPage(connection, memoryFile(), fakeCrypto())
  page.receiveMessage({ data: envelope("before-unlock", "system.echo", { text: "EARLY" }) })
  assert.equal(sent.length, 0)
  assert.equal(page.acceptingMessages, false)
  page.checkConnection()
  assert.equal(page.connected, true)
  assert.equal(page.acceptingMessages, true)
  page.receiveMessage({ data: envelope("live-echo", "system.echo", { text: "LIVE" }) })
  assert.deepEqual(sent.at(-1), { v: 1, id: "live-echo", src: "band", type: "ack" })
})

test("pre-lock interconnect handlers cannot mutate a reopened lifecycle", async () => {
  const connection = { send() {} }
  const page = await loadPage(connection, memoryFile(), fakeCrypto())
  const stale = {
    open: connection.onopen,
    close: connection.onclose,
    error: connection.onerror,
    message: connection.onmessage
  }
  page.unlock()
  page.lock("IOS LINK CLOSED")
  const lockedStatus = page.statusText
  stale.open()
  stale.error()
  stale.message({ data: envelope("locked-stale", "system.echo", { text: "STALE" }) })
  assert.equal(page.statusText, lockedStatus)
  assert.equal(page.logRows.length, 0)

  page.unlock()
  const reopenedEpoch = page.lifecycleEpoch
  stale.close()
  stale.message({ data: envelope("reopened-stale", "system.echo", { text: "STALE" }) })
  assert.equal(page.connected, true)
  assert.equal(page.lifecycleEpoch, reopenedEpoch)
  assert.equal(page.logRows.length, 0)

  connection.onclose()
  assert.equal(page.connected, false)
  assert.equal(page.lifecycleEpoch, reopenedEpoch + 1)
})

test("send failure callbacks lock only the lifecycle that issued them", async () => {
  const sends = []
  const connection = { send(options) { sends.push(options) } }
  const page = await loadPage(connection, memoryFile(), fakeCrypto())
  page.unlock()
  page.receiveMessage({ data: envelope("old-send", "system.echo", { text: "OLD" }) })
  assert.equal(sends.length, 1)
  page.lock("IOS LINK CLOSED")
  const lockedStatus = page.statusText
  const lockedEpoch = page.lifecycleEpoch
  sends[0].fail()
  assert.equal(page.statusText, lockedStatus)
  assert.equal(page.lifecycleEpoch, lockedEpoch)

  page.unlock()
  page.receiveMessage({ data: envelope("current-send", "system.echo", { text: "CURRENT" }) })
  sends.at(-1).fail()
  assert.equal(page.statusText, "SEND FAILED")
  assert.equal(page.connected, false)
  assert.equal(page.acceptingMessages, false)
  assert.equal(page.lifecycleEpoch, lockedEpoch + 1)
})

test("current close and error invalidate pending pre-admission readiness", async () => {
  for (const event of ["close", "error"]) {
    const readyCallbacks = []
    const sent = []
    const file = memoryFile()
    const connection = {
      send(options) { sent.push(options.data) },
      getReadyState(options) { readyCallbacks.push(options) }
    }
    const page = await loadPage(connection, file, fakeCrypto())
    assert.equal(page.connected, false)
    assert.equal(page.acceptingMessages, false)
    page.checkConnection()
    assert.equal(readyCallbacks.length, 1)
    const initialEpoch = page.lifecycleEpoch
    const handler = event === "close" ? connection.onclose : connection.onerror
    handler()
    assert.equal(page.lifecycleEpoch, initialEpoch + 1)
    assert.equal(page.connected, false)
    assert.equal(page.acceptingMessages, false)
    assert.equal(page.statusText, event === "close" ? "IOS LINK CLOSED" : "IOS LINK ERROR")

    const lockedEpoch = page.lifecycleEpoch
    handler()
    assert.equal(page.lifecycleEpoch, lockedEpoch, "repeated stale event must not reset twice")
    readyCallbacks[0].success({ status: 1 })
    assert.equal(page.connected, false)
    assert.equal(page.acceptingMessages, false)
    page.receiveMessage({ data: envelope(`${event}-queued`, "system.echo", { text: "QUEUED" }) })
    assert.equal(sent.length, 0)
    assert.equal(page.logRows.length, 0)
    assert.equal(file.accesses.length, 0)
  }
})
