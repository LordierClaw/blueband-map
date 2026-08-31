import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { readFile } from "node:fs/promises"
import test from "node:test"

const RUN = "run-0123456789abcdef"
const SCENE = "scene-0123456789"
const BYTES = Uint8Array.from([0, 1, 2, 3])
const DIGEST = createHash("sha256").update(BYTES).digest("hex")
const ASSET = `nav-${DIGEST.slice(0, 16)}`

async function loadPage(connection, file = memoryFile()) {
  const ux = await readFile(new URL("../src/pages/index/index.ux", import.meta.url), "utf8")
  const script = ux.match(/<script>([\s\S]*?)<\/script>/)[1]
    .replace(/import interconnect from ["']@system\.interconnect["']/, "")
    .replace(/import file from ["']@system\.file["']/, "")
    .replace("export default", "return")
  const component = new Function("interconnect", "file", script)(
    { instance() { return connection } }, file
  )
  const page = structuredClone(component.private)
  for (const [name, value] of Object.entries(component)) if (name !== "private") page[name] = value
  page.onReady()
  page.unlock()
  return page
}

function envelope(id, topic, body) {
  return { v: 1, id, src: "ios", type: "message", topic, body }
}

function prepare(overrides = {}) {
  return {
    runId: RUN, sceneId: SCENE, renderer: "raster", format: "image/png",
    formatVersion: 1, width: 212, height: 360, bytes: BYTES.length,
    sha256: DIGEST, primitives: 0, ...overrides
  }
}

function begin(overrides = {}) {
  return {
    asset: ASSET, run: RUN, scene: SCENE, renderer: "raster", format: "image/png",
    mime: "image/png", formatVersion: 1, width: 212, height: 360,
    bytes: BYTES.length, sha256: DIGEST, primitives: 0, ...overrides
  }
}

function memoryFile() {
  const storage = new Map()
  const writes = []
  const deletes = []
  return {
    storage, writes, deletes,
    access({ uri, success, fail }) { storage.has(uri) ? success() : fail() },
    delete({ uri, success }) { deletes.push(uri); storage.delete(uri); success() },
    writeArrayBuffer({ uri, buffer, position, success }) {
      writes.push({ uri, position, bytes: buffer.length })
      const existing = storage.get(uri) || new Uint8Array(0)
      const output = new Uint8Array(Math.max(existing.length, position + buffer.length))
      output.set(existing)
      output.set(buffer, position)
      storage.set(uri, output)
      success()
    }
  }
}

async function harness() {
  const sent = []
  const file = memoryFile()
  const connection = { send({ data, success }) { sent.push(data); if (success) success() } }
  return { page: await loadPage(connection, file), sent, file, connection }
}

function publish(page) {
  page.receiveMessage({ data: envelope("prepare", "render.prepare", prepare()) })
  page.receiveMessage({ data: envelope("begin", "map.asset.begin", begin()) })
  page.receiveMessage({ data: envelope("chunk", "map.asset.chunk", {
    asset: ASSET, run: RUN, scene: SCENE, offset: 0, data: Buffer.from(BYTES).toString("base64")
  }) })
  page.receiveMessage({ data: envelope("end", "map.asset.end", { asset: ASSET, run: RUN, scene: SCENE }) })
  page.mapComplete(page.pendingPublication.token)
}

test("publishes only a prepared 212x360 raster route-card and one aggregate result", async () => {
  const { page, sent, file } = await harness()
  publish(page)

  assert.equal(file.writes.length, 1)
  assert.deepEqual(file.storage.get(`internal://files/${ASSET}.png`), BYTES)
  assert.equal(page.confirmedMap.scene, SCENE)
  assert.equal(page.mapRenderer, "raster")
  assert.equal(sent.find(message => message.topic === "render.ready").body.bytes, 4)
  assert.deepEqual(sent.find(message => message.topic === "render.result").body, {
    runId: RUN, sceneId: SCENE, renderer: "raster", formatVersion: 1,
    status: "ok", bytes: 4, primitives: 0,
    prepareMs: sent.find(message => message.topic === "render.result").body.prepareMs,
    validateMs: sent.find(message => message.topic === "render.result").body.validateMs,
    renderMs: sent.find(message => message.topic === "render.result").body.renderMs,
    sha256Prefix: DIGEST.slice(0, 8)
  })
})

test("rejects vector, oversized and unprepared assets before file allocation", async () => {
  const { page, sent, file } = await harness()
  page.receiveMessage({ data: envelope("vector", "render.prepare", prepare({ renderer: "vector" })) })
  page.receiveMessage({ data: envelope("large", "render.prepare", prepare({ bytes: 1025 })) })
  page.receiveMessage({ data: envelope("unprepared", "map.asset.begin", begin()) })

  assert.equal(file.writes.length, 0)
  assert.deepEqual(sent.filter(message => message.topic === "render.reject").map(message => message.body.code), [
    "unsupportedRenderer", "payloadTooLarge"
  ])
  assert.equal(page.activeTransfer, null)
})

test("rejects a chunk from an old scene instead of appending it", async () => {
  const { page, sent, file } = await harness()
  page.receiveMessage({ data: envelope("prepare", "render.prepare", prepare()) })
  page.receiveMessage({ data: envelope("begin", "map.asset.begin", begin()) })
  page.receiveMessage({ data: envelope("chunk", "map.asset.chunk", {
    asset: ASSET, run: RUN, scene: "scene-old", offset: 0, data: Buffer.from(BYTES).toString("base64")
  }) })

  assert.equal(page.activeTransfer, null)
  assert.equal(file.writes.length, 0)
  const result = sent.find(message => message.topic === "render.result")
  assert.equal(result.body.errorCode, "ASSET_SCENE_MISMATCH")
})

test("nav.update covers live statuses and ignores stale scene or sequence", async () => {
  const { page, sent } = await harness()
  publish(page)
  const statuses = ["navigating", "gpsLow", "limitedMap", "rerouting", "arrived"]
  statuses.forEach((status, seq) => page.receiveMessage({ data: envelope(`nav-${seq}`, "nav.update", {
    scene: SCENE, seq, x: 100 + seq, y: 300 - seq,
    maneuver: status === "arrived" ? "arrive" : "right",
    distanceM: 180 - seq, street: "Next Road", status
  }) }))

  assert.equal(page.navStatus, "ARRIVED")
  assert.equal(page.navArrow, "●")
  assert.equal(page.navMarkerStyle, "left:100px;top:292px;")
  page.receiveMessage({ data: envelope("stale", "nav.update", {
    scene: SCENE, seq: 3, x: 1, y: 1, maneuver: "left", distanceM: 1, street: "Stale", status: "navigating"
  }) })
  page.receiveMessage({ data: envelope("wrong", "nav.update", {
    scene: "wrong-scene", seq: 99, x: 1, y: 1, maneuver: "left", distanceM: 1, street: "Wrong", status: "navigating"
  }) })
  assert.equal(page.navSequence, 4)
  assert.equal(page.navStreet, "Next Road")
  assert.equal(sent.filter(message => message.type === "ack" && /^nav-|stale|wrong/.test(message.id)).length, 7)
})

test("disconnect clears transfer ownership and nav sequence without accepting queued messages", async () => {
  const { page, sent, connection } = await harness()
  publish(page)
  const before = sent.length
  connection.onclose()
  page.receiveMessage({ data: envelope("queued", "nav.update", {
    scene: SCENE, seq: 1, x: 106, y: 320, maneuver: "straight", distanceM: 1, street: "Queued", status: "navigating"
  }) })
  assert.equal(page.activeTransfer, null)
  assert.equal(page.activeMapOperationID, "")
  assert.equal(page.navSequence, -1)
  assert.equal(sent.length, before)
})
