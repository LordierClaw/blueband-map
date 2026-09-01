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
  return page
}

function envelope(id, topic, body) {
  return { v: 1, id, src: "ios", type: "message", topic, body }
}

function prepare(overrides = {}) {
  return {
    runId: RUN, sceneId: SCENE, renderer: "raster", format: "image/png",
    formatVersion: 1, width: 212, height: 520, bytes: BYTES.length,
    sha256: DIGEST, primitives: 0, ...overrides
  }
}

function preview(overrides = {}) {
  return {
    maneuver: "right", distanceM: 88, street: "Chu Huy Man",
    x: 106, y: 374, heading: 2,
    destinationMode: "visible", destinationX: 106, destinationY: 120,
    ...overrides
  }
}

function begin(overrides = {}) {
  return {
    asset: ASSET, run: RUN, scene: SCENE, renderer: "raster", format: "image/png",
    mime: "image/png", formatVersion: 1, width: 212, height: 520,
    bytes: BYTES.length, sha256: DIGEST, primitives: 0, ...overrides
  }
}

function navigation(overrides = {}) {
  return {
    scene: SCENE, seq: 1, x: 106, y: 320, heading: 0,
    maneuver: "straight", distanceM: 100, street: "Road", status: "navigating",
    destinationMode: "hidden", destinationX: 0, destinationY: 0,
    ...overrides
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
  const connection = {
    getReadyState({ success }) { success({ status: 1 }) },
    send({ data, success }) { sent.push(data); if (success) success() }
  }
  return { page: await loadPage(connection, file), sent, file, connection }
}

test("waiting page probes immediately with one in flight and owns one retry timer", async () => {
  const timers = new Map()
  let nextTimer = 1
  const originalSetTimeout = globalThis.setTimeout
  const originalClearTimeout = globalThis.clearTimeout
  globalThis.setTimeout = (callback, delay) => {
    const id = nextTimer++
    timers.set(id, { callback, delay })
    return id
  }
  globalThis.clearTimeout = id => timers.delete(id)
  try {
    const probes = []
    const connection = {
      getReadyState(callbacks) { probes.push(callbacks) },
      send() {}
    }
    const page = await loadPage(connection)
    assert.equal(probes.length, 1)
    page.probeConnection()
    assert.equal(probes.length, 1)

    probes[0].fail({}, 7)
    assert.equal(timers.size, 1)
    assert.equal([...timers.values()][0].delay, 2000)
    const retry = [...timers.values()][0]
    timers.clear()
    retry.callback()
    assert.equal(probes.length, 2)
    probes[1].success({ status: 1 })
    assert.equal(page.connected, true)
    assert.equal(timers.size, 0)

    connection.onclose()
    assert.equal(page.connected, false)
    assert.equal(timers.size, 1)
    page.onDestroy()
    assert.equal(timers.size, 0)
    assert.equal(connection.onmessage, null)
  } finally {
    globalThis.setTimeout = originalSetTimeout
    globalThis.clearTimeout = originalClearTimeout
  }
})

function publish(page, scene = SCENE, suffix = "") {
  page.receiveMessage({ data: envelope(`prepare${suffix}`, "render.prepare", prepare({ sceneId: scene })) })
  page.receiveMessage({ data: envelope(`begin${suffix}`, "map.asset.begin", begin({ scene })) })
  page.receiveMessage({ data: envelope(`chunk${suffix}`, "map.asset.chunk", {
    asset: ASSET, run: RUN, scene, offset: 0, data: Buffer.from(BYTES).toString("base64")
  }) })
  page.receiveMessage({ data: envelope(`end${suffix}`, "map.asset.end", { asset: ASSET, run: RUN, scene }) })
  page.mapComplete(page.pendingPublication.token)
}

test("publishes only a prepared 212x520 raster snapshot and one aggregate result", async () => {
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
  page.receiveMessage({ data: envelope("large", "render.prepare", prepare({ bytes: 8193 })) })
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
    heading: seq, distanceM: 180 - seq, street: "Next Road", status,
    destinationMode: "hidden", destinationX: 0, destinationY: 0
  }) }))

  assert.equal(page.navStatus, "ARRIVED")
  assert.equal(page.navArrowPath, "/common/maneuver-arrive.png")
  assert.equal(page.navMarkerPath, "/common/marker-0.png")
  assert.equal(page.navMarkerStyle, "left:83px;top:347px;")
  assert.equal(page.navStatusVisible, true)
  page.receiveMessage({ data: envelope("nav-5", "nav.update", {
    ...navigation({ seq: 5, x: 104, y: 296, heading: 3, distanceM: 120, street: "Next Road" })
  }) })
  assert.equal(page.navStatusVisible, false)
  page.receiveMessage({ data: envelope("stale", "nav.update", {
    ...navigation({ seq: 3, x: 1, y: 1, maneuver: "left", distanceM: 1, street: "Stale" })
  }) })
  page.receiveMessage({ data: envelope("wrong", "nav.update", {
    ...navigation({ scene: "wrong-scene", seq: 99, x: 1, y: 1, maneuver: "left", distanceM: 1, street: "Wrong" })
  }) })
  assert.equal(page.navSequence, 5)
  assert.equal(page.navStreet, "Next Road")
  assert.equal(sent.filter(message => message.type === "ack" && /^nav-|stale|wrong/.test(message.id)).length, 8)
})

test("preview and live guidance share compact metre and kilometre labels", async () => {
  const { page } = await harness()
  const cases = [[0, "0 m"], [999, "999 m"], [1000, "1 km"], [1354, "1.4 km"], [2000, "2 km"], [12345, "12.3 km"]]
  for (const [distanceM, label] of cases) {
    page.receiveMessage({ data: envelope(`prepare-${distanceM}`, "render.prepare", prepare({
      sceneId: `${SCENE}-${distanceM}`, preview: preview({ distanceM })
    })) })
    assert.equal(page.navDistance, label)
    page.receiveMessage({ data: envelope(`cancel-${distanceM}`, "render.cancel", {
      runId: RUN, sceneId: `${SCENE}-${distanceM}`
    }) })
  }

  publish(page)
  cases.forEach(([distanceM, label], seq) => {
    page.receiveMessage({ data: envelope(`nav-distance-${seq}`, "nav.update", navigation({ seq, distanceM })) })
    assert.equal(page.navDistance, label)
    assert.equal(page.navMarkerPath, "/common/marker-0.png")
    assert.equal(page.navMarkerStyle, "left:83px;top:347px;")
  })
})

test("destination overlay switches atomically and stays inside the curved safe mask", async () => {
  const { page } = await harness()
  publish(page)
  page.receiveMessage({ data: envelope("visible", "nav.update", navigation({
    destinationMode: "visible", destinationX: 106, destinationY: 120
  })) })
  assert.equal(page.navDestinationVisible, true)
  assert.equal(page.navDestinationPath, "/common/destination-pin.png")
  assert.equal(page.navDestinationStyle, "left:96px;top:108px;")

  page.receiveMessage({ data: envelope("edge", "nav.update", navigation({
    seq: 2, destinationMode: "edge", destinationX: 190, destinationY: 260
  })) })
  assert.equal(page.navDestinationPath, "/common/destination-edge.png")
  assert.equal(page.navDestinationStyle, "left:180px;top:250px;")

  page.receiveMessage({ data: envelope("visible-too-close", "nav.update", navigation({
    seq: 3, destinationMode: "visible", destinationX: 190, destinationY: 260
  })) })
  assert.equal(page.navSequence, 2)

  page.receiveMessage({ data: envelope("partial", "nav.update", navigation({
    seq: 4, destinationMode: "visible", destinationX: 106, destinationY: undefined
  })) })
  assert.equal(page.navSequence, 2)

  page.receiveMessage({ data: envelope("hidden", "nav.update", navigation({ seq: 3 })) })
  assert.equal(page.navDestinationVisible, false)

  page.receiveMessage({ data: envelope("visible-again", "nav.update", navigation({
    seq: 4, destinationMode: "visible", destinationX: 106, destinationY: 120
  })) })
  publish(page, "scene-refresh-01", "-refresh")
  assert.equal(page.navDestinationVisible, false)
  assert.equal(page.navMarkerVisible, false)
  page.receiveMessage({ data: envelope("new-marker", "nav.update", navigation({ scene: "scene-refresh-01" })) })
  assert.equal(page.navMarkerVisible, true)
})

test("render.prepare shows compact guidance before the map arrives", async () => {
  const { page } = await harness()
  page.receiveMessage({ data: envelope("prepare", "render.prepare", prepare({
    preview: preview()
  })) })

  assert.equal(page.navArrowPath, "/common/maneuver-right.png")
  assert.equal(page.navDistance, "88 m")
  assert.equal(page.navStreet, "Chu Huy Man")
  assert.equal(page.navStatus, "LOADING MAP")
  assert.equal(page.navStatusVisible, true)
  assert.equal(page.navMarkerVisible, false)
  assert.equal(page.navDestinationVisible, false)
})

test("first raster promotes its staged marker and destination atomically", async () => {
  const { page } = await harness()
  page.receiveMessage({ data: envelope("prepare", "render.prepare", prepare({ preview: preview() })) })
  page.receiveMessage({ data: envelope("begin", "map.asset.begin", begin()) })
  page.receiveMessage({ data: envelope("chunk", "map.asset.chunk", {
    asset: ASSET, run: RUN, scene: SCENE, offset: 0, data: Buffer.from(BYTES).toString("base64")
  }) })
  page.receiveMessage({ data: envelope("end", "map.asset.end", { asset: ASSET, run: RUN, scene: SCENE }) })

  assert.equal(page.navMarkerVisible, false)
  assert.equal(page.navDestinationVisible, false)
  page.mapComplete(page.pendingPublication.token)
  assert.equal(page.navMarkerVisible, true)
  assert.equal(page.navMarkerPath, "/common/marker-0.png")
  assert.equal(page.navMarkerStyle, "left:83px;top:347px;")
  assert.equal(page.navDestinationVisible, true)
  assert.equal(page.navDestinationPath, "/common/destination-pin.png")
  assert.equal(page.navDestinationStyle, "left:96px;top:108px;")
})

test("startup navigation status is visible before the first map", async () => {
  const { page } = await harness()
  page.receiveMessage({ data: envelope("locating", "nav.status", { status: "locating" }) })
  assert.equal(page.startupStatus, "LOCATING")
  page.receiveMessage({ data: envelope("gps-low", "nav.status", { status: "gpsLow" }) })
  assert.equal(page.startupStatus, "GPS LOW")
})

test("render.cancel releases a matching prepared generation", async () => {
  const { page } = await harness()
  page.receiveMessage({ data: envelope("prepare", "render.prepare", prepare()) })
  assert.ok(page.preparedRender)
  page.receiveMessage({ data: envelope("cancel", "render.cancel", { runId: RUN, sceneId: SCENE }) })
  assert.equal(page.preparedRender, null)
})

test("cancelled refresh restores the confirmed scene guidance", async () => {
  const { page } = await harness()
  publish(page)
  page.receiveMessage({ data: envelope("nav-old", "nav.update", {
    scene: SCENE, seq: 1, x: 106, y: 320, heading: 2,
    maneuver: "left", distanceM: 140, street: "Old Road", status: "navigating",
    destinationMode: "hidden", destinationX: 0, destinationY: 0
  }) })
  page.receiveMessage({ data: envelope("prepare-new", "render.prepare", prepare({
    sceneId: "scene-refresh-01",
    preview: preview({ street: "New Road" })
  })) })
  page.receiveMessage({ data: envelope("nav-latest", "nav.update", {
    scene: SCENE, seq: 2, x: 108, y: 318, heading: 3,
    maneuver: "straight", distanceM: 120, street: "Latest Road", status: "navigating",
    destinationMode: "hidden", destinationX: 0, destinationY: 0
  }) })
  assert.equal(page.navStreet, "New Road")
  page.receiveMessage({ data: envelope("cancel-new", "render.cancel", {
    runId: RUN, sceneId: "scene-refresh-01"
  }) })

  assert.equal(page.navArrowPath, "/common/maneuver-straight.png")
  assert.equal(page.navDistance, "120 m")
  assert.equal(page.navStreet, "Latest Road")
})

test("three out-of-order windowed chunks are buffered until their predecessor", async () => {
  const { page, sent, file } = await harness()
  page.receiveMessage({ data: envelope("prepare", "render.prepare", prepare()) })
  page.receiveMessage({ data: envelope("begin", "map.asset.begin", begin()) })
  for (const offset of [3, 2, 1, 0]) page.receiveMessage({ data: envelope(`chunk-${offset}`, "map.asset.chunk", {
    asset: ASSET, run: RUN, scene: SCENE, offset,
    data: Buffer.from(BYTES.slice(offset, offset + 1)).toString("base64")
  }) })
  page.receiveMessage({ data: envelope("end", "map.asset.end", { asset: ASSET, run: RUN, scene: SCENE }) })

  assert.deepEqual(file.storage.get(`internal://files/${ASSET}.png`), BYTES)
  assert.equal(sent.some(message => message.body && message.body.errorCode === "ASSET_OFFSET_INVALID"), false)
})

test("disconnect clears transfer ownership and nav sequence without accepting queued messages", async () => {
  const { page, sent, connection } = await harness()
  publish(page)
  const before = sent.length
  connection.onclose()
  page.receiveMessage({ data: envelope("queued", "nav.update", {
    scene: SCENE, seq: 1, x: 106, y: 320, heading: 0, maneuver: "straight", distanceM: 1,
    street: "Queued", status: "navigating", destinationMode: "hidden", destinationX: 0, destinationY: 0
  }) })
  assert.equal(page.activeTransfer, null)
  assert.equal(page.activeMapOperationID, "")
  assert.equal(page.navSequence, -1)
  assert.equal(sent.length, before)
})

test("accepts windowed unique chunk IDs in offset order and publishes a refresh atomically", async () => {
  const { page, sent, file } = await harness()
  publish(page)
  page.receiveMessage({ data: envelope("nav-old", "nav.update", navigation({ heading: 1 })) })
  const oldURI = page.confirmedMap.uri
  const nextBytes = Uint8Array.from([4, 5, 6, 7])
  const nextDigest = createHash("sha256").update(nextBytes).digest("hex")
  const nextAsset = `nav-${nextDigest.slice(0, 16)}`
  const nextScene = "scene-refresh-01"

  page.receiveMessage({ data: envelope("prepare-2", "render.prepare", prepare({
    sceneId: nextScene, sha256: nextDigest,
    preview: preview({ heading: 6, destinationMode: "edge", destinationX: 180, destinationY: 260 })
  })) })
  page.receiveMessage({ data: envelope("begin-2", "map.asset.begin", begin({
    asset: nextAsset, scene: nextScene, sha256: nextDigest
  })) })
  assert.equal(page.mapPath, oldURI)
  assert.equal(page.confirmedMap.uri, oldURI)
  assert.equal(page.navMarkerPath, "/common/marker-0.png")

  page.receiveMessage({ data: envelope("chunk-1", "map.asset.chunk", {
    asset: nextAsset, run: RUN, scene: nextScene, offset: 0,
    data: Buffer.from(nextBytes.slice(0, 2)).toString("base64")
  }) })
  page.receiveMessage({ data: envelope("chunk-2", "map.asset.chunk", {
    asset: nextAsset, run: RUN, scene: nextScene, offset: 2,
    data: Buffer.from(nextBytes.slice(2)).toString("base64")
  }) })
  page.receiveMessage({ data: envelope("end-2", "map.asset.end", {
    asset: nextAsset, run: RUN, scene: nextScene
  }) })

  assert.equal(page.confirmedMap.uri, oldURI)
  assert.equal(page.mapPath, oldURI)
  assert.equal(page.pendingMapPath, `internal://files/${nextAsset}.png`)
  assert.deepEqual(file.storage.get(page.pendingMapPath), nextBytes)
  assert.equal(sent.filter(message => message.type === "ack" && /^chunk-/.test(message.id)).length, 2)

  page.mapComplete(page.pendingPublication.token)
  assert.equal(page.confirmedMap.scene, nextScene)
  assert.equal(page.mapPath, `internal://files/${nextAsset}.png`)
  assert.equal(page.navMarkerPath, "/common/marker-0.png")
  assert.equal(page.navDestinationPath, "/common/destination-edge.png")
})

test("wrong windowed offset aborts the refresh and keeps the confirmed map", async () => {
  const { page, sent } = await harness()
  publish(page)
  const confirmed = page.confirmedMap
  page.receiveMessage({ data: envelope("prepare-2", "render.prepare", prepare()) })
  page.receiveMessage({ data: envelope("begin-2", "map.asset.begin", begin()) })
  page.receiveMessage({ data: envelope("chunk-wrong", "map.asset.chunk", {
    asset: ASSET, run: RUN, scene: SCENE, offset: 3,
    data: Buffer.from(BYTES.slice(0, 2)).toString("base64")
  }) })
  page.receiveMessage({ data: envelope("end-wrong", "map.asset.end", {
    asset: ASSET, run: RUN, scene: SCENE
  }) })

  assert.equal(sent.find(message => message.topic === "render.result" && message.body.status === "error").body.errorCode, "ASSET_OVERFLOW")
  assert.equal(page.confirmedMap.uri, confirmed.uri)
  assert.equal(page.mapPath, confirmed.uri)
})
