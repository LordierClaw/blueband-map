import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { readFile } from "node:fs/promises"
import test from "node:test"
import corridorMap from "./helpers/corridor.mjs"

const RUN = "run-0123456789abcdef"
const SCENE = "scene-0123456789"
const BYTES = Uint8Array.from([0, 1, 2, 3])
const DIGEST = createHash("sha256").update(BYTES).digest("hex")
const ASSET = `nav-${DIGEST.slice(0, 16)}`
// Generated 128x128 grayscale gradient, independent of the app renderer/encoder.
const CELL_PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAAAAADmVT4XAAACI0lEQVR4nMXNA5IYAAAAsa1t27Zt27Zt82rbtm3btm3bnj5j84FAoMBBggYLHiJkqNBhwoYLHyFipMhRokaLHiNmrNhx4saLnyBhosRJkiZLniJlqtRp0qZLnyFjpsxZsmbLniNnrtx58ubLX6BgocJFihYrXqJkqdJlypYrX6FipcpVqlarXqNmrdp16tar36Bho8ZNmjZr3qJlq9Zt2rZr36Fjp85dunbr3qNnr959+vbrH2D/A5D/gcj/IOR/MPI/BPkfivwPQ/6HI/8jkP+RyP8o5H808j8G+R+L/I9D/scj/xOQ/4nI/yTkfzLyPwX5n4r8T0P+pyP/M5D/mcj/LOR/NvI/B/mfi/zPQ/7nI/8LkP+FyP8i5H8x8r8E+V+K/C9D/pcj/yuQ/5XI/yrkfzXyvwb5X4v8r0P+1yP/G5D/jcj/JuR/M/K/BfnfivxvQ/63I/87kP+dyP8u5H838r8H+d+L/O9D/vcj/weQ/4PI/yHk/zDyfwT5P4r8H0P+jyP/J5D/k8j/KeT/NPJ/Bvk/i/yfQ/7PI/8XkP+LyP8l5P8y8n8F+b+K/F9D/q8j/zeQ/5vI/y3k/zbyfwf5v4v830P+7yP/D5D/h8j/I+T/MfL/BPl/ivw/Q/6fI/8vkP+XyP8r5P818v8G+X+L/L9D/t8j/x+Q/4/I/yfk/zPy/wX5/4r8f0P+vyP/P5D/n8j/L+T/N/L/B/n/i/z/+w96ocHS/e4O/QAAAABJRU5ErkJggg==", "base64")

async function loadPage(connection, file = memoryFile(), clock = Date) {
  const ux = await readFile(new URL("../src/pages/index/index.ux", import.meta.url), "utf8")
  const script = ux.match(/<script>([\s\S]*?)<\/script>/)[1]
    .replace(/import interconnect from ["']@system\.interconnect["']/, "")
    .replace(/import file from ["']@system\.file["']/, "")
    .replace("export default", "return")
  const component = new Function("interconnect", "file", "Date", script)(
    { instance() { return connection } }, file, clock
  )
  const page = structuredClone(component.private)
  for (const [name, value] of Object.entries(component)) if (name !== "private") page[name] = value
  page.$nextTick = callback => callback()
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
    list({ uri, success }) { success({ fileList: [...storage.keys()].filter(key => key.startsWith(uri)).map(uri => ({ uri })) }) },
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

test("native callback diagnostics count first owned completion without throttling sends", async () => {
  const pending = [], sent = []
  let now = 1000
  const connection = {
    getReadyState({ success }) { success({ status: 1 }) },
    send(options) { sent.push(options.data); pending.push(options) }
  }
  const page = await loadPage(connection, memoryFile(), { now: () => now })
  try {
    page.sendACK("one"); page.sendACK("two")
    assert.equal(pending.length, 2, "passive measurement cannot serialize native sends")
    now += 20
    pending[0].success?.(); pending[0].success?.(); pending[0].fail({}, 204)
    now += 10
    pending[1].fail({}, 204); pending[1].success?.()
    assert.equal(page.connected, true)
    page.receiveMessage({ data: envelope("probe", "diagnostics.get", { request: "native-1", transport: true }) })
    const report = sent.find(m => m.topic === "diagnostics.report")
    assert.deepEqual(report.body.transport, { v: 1, clockValid: true, attempted: 2, succeeded: 1,
      failed: 1, pending: 0, peakPending: 2, timeouts204: 1, abandoned: 0, saturated: false, lastCallbackMs: 30, maxCallbackMs: 30 })
    assert.ok(Buffer.byteLength(JSON.stringify(report)) <= 512)
    assert.equal(report.body.perf, undefined, "transport has its own bounded reply")
  } finally { page.onDestroy() }
})

test("callback classes and finite pending sample distinguish delivered sends from missing callbacks", async () => {
  const sends = []
  let now = 1000
  const connection = { getReadyState({ success }) { success({ status: 1 }) }, send(options) { sends.push(options) } }
  const page = await loadPage(connection, memoryFile(), { now: () => now })
  try {
    page.sendACK("a"); page.sendPing()
    now += 20
    sends[0].success(); sends[0].success()
    for (let i = 0; i < 30; i++) page.sendACK(`sample-${i}`)
    now += 500
    page.receiveMessage({ data: envelope("probe", "diagnostics.get", { request: "class-1", transport: true, callbacks: true }) })
    const detail = sends.find(s => s.data.body?.callbacks)?.data
    assert.ok(detail, "explicit detail request must produce class evidence")
    assert.deepEqual(detail.body.callbacks.ack, [31, 1, 0, 30, 0])
    assert.deepEqual(detail.body.callbacks.message, [1, 0, 0, 1, 0])
    assert.deepEqual(detail.body.callbacks.sample, [16, 520, 15])
    assert.equal(detail.body.callbacks.duplicate, 1)
    assert.ok(Buffer.byteLength(JSON.stringify(detail)) <= 512)
    page.resetMapLifecycle()
    sends[1].success()
    page.receiveMessage({ data: envelope("probe-2", "diagnostics.get", { request: "class-2", transport: true, callbacks: true }) })
    const after = sends.filter(s => s.data.body?.callbacks).at(-1).data.body.callbacks
    assert.equal(after.ack[3], 0)
    assert.equal(after.ack[4], 31)
    assert.equal(after.late, 1)
    assert.equal(after.sample[0], 0)
  } finally { page.onDestroy() }
})

test("transport reply matches an independent literal maximum-width vector", async () => {
  const literal = (await readFile(new URL("./fixtures/transport-diagnostics.json", import.meta.url), "utf8")).trim()
  assert.equal(Buffer.byteLength(literal), 451)
  const expected = JSON.parse(literal), sent = []
  const connection = { getReadyState({ success }) { success({ status: 1 }) }, send({ data }) { sent.push(data) } }
  const page = await loadPage(connection, memoryFile(), { now: () => 9999999999999 })
  try {
    page.nextID = 999999; page.rpkBuild = 2147483647; page.rpkVersion = "0.6.19"
    page.transportPerf = { ...expected.body.transport }
    delete page.transportPerf.v; delete page.transportPerf.clockValid
    page.receiveMessage({ data: envelope("probe", "diagnostics.get", { request: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", transport: true }) })
    assert.equal(JSON.stringify(sent[0]), literal)
  } finally { page.onDestroy() }
})

test("callback detail matches an independent bounded maximum-width vector", async () => {
  const literal = (await readFile(new URL("./fixtures/callback-diagnostics.json", import.meta.url), "utf8")).trim()
  assert.ok(Buffer.byteLength(literal) <= 512)
  const expected = JSON.parse(literal), sent = []
  const connection = { getReadyState({ success }) { success({ status: 1 }) }, send({ data }) { sent.push(data) } }
  const page = await loadPage(connection, memoryFile(), { now: () => 9999999999999 })
  try {
    const metrics = expected.body.callbacks
    page.nextID = 999999
    Object.assign(page.callbackPerf, { ack: metrics.ack.slice(), message: metrics.message.slice(),
      dropped: 2147483647, duplicate: 2147483647, late: 2147483647, saturated: true,
      samples: Array.from({ length: 16 }, () => ({ started: 9999999399999 })) })
    page.receiveMessage({ data: envelope("probe", "diagnostics.get", { request: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", transport: true, callbacks: true }) })
    assert.equal(JSON.stringify(sent[0]), literal)
  } finally { page.onDestroy() }
})

test("uncompleted sends and stale lifecycle callbacks stay distinguishable", async () => {
  const pending = [], sent = []
  let now = 1000
  const connection = { getReadyState({ success }) { success({ status: 1 }) },
    send(options) { sent.push(options.data); pending.push(options) } }
  const page = await loadPage(connection, memoryFile(), { now: () => now })
  try {
    page.sendACK("old")
    page.resetMapLifecycle()
    pending[0].success?.(); pending[0].fail({}, 1006)
    assert.equal(page.connected, true)
    page.sendACK("new")
    now = 900
    pending[1].success?.()
    page.sendACK("no-callback")
    page.receiveMessage({ data: envelope("probe", "diagnostics.get", { request: "native-2", transport: true }) })
    const metrics = sent.find(m => m.topic === "diagnostics.report").body.transport
    assert.equal(metrics.abandoned, 1)
    assert.equal(metrics.pending, 1)
    assert.equal(metrics.succeeded, 1)
    assert.equal(metrics.clockValid, false)
    assert.equal(metrics.lastCallbackMs, null)
    assert.equal(metrics.maxCallbackMs, null)
  } finally { page.onDestroy() }
})

test("corridor streaming requires a confirmed scene and resets on full-map replacement", async () => {
  const { page, sent } = await harness()
  try {
    page.receiveMessage({ data: envelope("stream-before-map", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    assert.equal(sent.some(message => message.topic === "map.stream.ready"), false)
    publish(page)
    page.receiveMessage({ data: envelope("stream-open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    const ready = sent.find(message => message.topic === "map.stream.ready")
    assert.ok(ready, "application capability reply is required; unknown-topic ACK is insufficient")
    assert.deepEqual(ready.body, { scene: SCENE, epoch: "e1", version: 1, cellSize: 128, maximumFiles: 30, maximumResident: 24,
      cellChunkBytes: 540 })
    assert.equal(page.streamVisible, false, "opening cannot hide the confirmed full map")
    page.receiveMessage({ data: envelope("stream-view", "map.stream.view", { epoch: "e1", seq: 1, x: 0, y: 0 }) })
    const need = sent.find(message => message.topic === "map.stream.state")
    assert.deepEqual(need.body.missing, corridorMap.cells(0, 0))
    assert.equal(page.streamImages.length, 0, "missing images never decode or display")
    publish(page, "next-scene", "-next")
    assert.equal(page.streamState, null, "old camera coordinates must not survive scene replacement")
    assert.equal(page.streamVisible, false)
  } finally { page.onDestroy() }
})

function streamCell(page, key, suffix = key, data = CELL_PNG, epoch = "e1", chunk = 216) {
  const digest = createHash("sha256").update(data).digest("hex")
  const begin = { epoch, cell: key, bytes: data.length, sha256: digest }
  if (chunk !== 216) begin.chunk = chunk
  page.receiveMessage({ data: envelope(`cb-${suffix}`, "map.cell.begin", begin) })
  const offsets = Array.from({ length: Math.ceil(data.length / chunk) }, (_, i) => i * chunk)
  if (offsets.length > 1) [offsets[0], offsets[1]] = [offsets[1], offsets[0]]
  for (const offset of offsets) page.receiveMessage({ data: envelope(`cc-${suffix}-${offset}`, "map.cell.chunk", {
    epoch, cell: key, offset, data: data.subarray(offset, offset + chunk).toString("base64")
  }) })
  page.receiveMessage({ data: envelope(`ce-${suffix}`, "map.cell.end", { epoch, cell: key }) })
}

test("cells accept the advertised 540-byte chunk only when begin declares it", async () => {
  const { page, sent } = await harness()
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    const [first, second, third] = corridorMap.cells(0, 0)
    assert.ok(CELL_PNG.length > 540, "fixture must span more than one large chunk")
    streamCell(page, first, "large", CELL_PNG, "e1", 540)
    const stored = sent.filter(m => m.topic === "map.cell.result" && m.body.cell === first).at(-1)
    assert.equal(stored.body.status, "stored", "two out-of-order 540-byte chunks complete the cell")
    streamCell(page, second, "legacy")
    assert.equal(sent.filter(m => m.topic === "map.cell.result" && m.body.cell === second).at(-1).body.status, "stored",
      "a begin without chunk keeps the 216-byte contract for older iPhone builds")
    const digest = createHash("sha256").update(CELL_PNG).digest("hex")
    page.receiveMessage({ data: envelope("cb-odd", "map.cell.begin", { epoch: "e1", cell: third, bytes: CELL_PNG.length,
      sha256: digest, chunk: 300 }) })
    const rejected = sent.filter(m => m.topic === "map.cell.result" && m.body.cell === third).at(-1)
    assert.equal(rejected.body.status, "error")
    assert.equal(rejected.body.code, "invalidPayload")
    page.receiveMessage({ data: envelope("cb-mixed", "map.cell.begin", { epoch: "e1", cell: third, bytes: CELL_PNG.length,
      sha256: digest, chunk: 540 }) })
    page.receiveMessage({ data: envelope("cc-mixed", "map.cell.chunk", { epoch: "e1", cell: third, offset: 0,
      data: CELL_PNG.subarray(0, 216).toString("base64") }) })
    assert.equal(sent.filter(m => m.topic === "map.cell.result" && m.body.cell === third).at(-1).body.code, "invalidChunk",
      "a chunk shorter than the declared size is rejected")
  } finally { page.onDestroy() }
})

test("repeated native completions cannot refresh their own image list or flood decoded replies", async () => {
  const { page, sent } = await harness()
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    page.receiveMessage({ data: envelope("view", "map.stream.view", { epoch: "e1", seq: 1, x: 0, y: 0 }) })
    for (const key of corridorMap.cells(0, 0)) streamCell(page, key)
    const mounted = page.streamImages, first = mounted[0]
    page.streamImageComplete(first.key, first.uri, first.token)
    assert.equal(page.streamImages, mounted, "partial decode has no visual change to remount")
    for (const item of mounted) page.streamImageComplete(item.key, item.uri, item.token)
    assert.equal(page.streamState.position.seq, 1, "all first completions still promote coverage")
    const displayed = page.streamImages, before = sent.length
    for (let repeat = 0; repeat < 100; repeat++) {
      for (const item of displayed) page.streamImageComplete(item.key, item.uri, item.token)
    }
    assert.equal(page.streamImages, displayed, "a callback cannot trigger another reactive image refresh")
    assert.equal(sent.length, before, "duplicate native callbacks have no transport side effects")
    assert.equal(sent.filter(message => message.topic === "map.cell.decoded").length, 10)
  } finally { page.onDestroy() }
})

test("cached remount reports a new decode while ignoring callbacks from the old mount", async () => {
  const { page, sent, file } = await harness()
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    page.receiveMessage({ data: envelope("view", "map.stream.view", { epoch: "e1", seq: 1, x: 0, y: 0 }) })
    for (const key of corridorMap.cells(0, 0)) streamCell(page, key)
    for (const item of page.streamImages.slice()) page.streamImageComplete(item.key, item.uri, item.token)
    const oldMount = page.streamImages.find(item => item.key === "0:4")
    page.receiveMessage({ data: envelope("move", "map.stream.view", { epoch: "e1", seq: 2, x: 0, y: 128 }) })
    for (const key of corridorMap.cells(0, 128).filter(key => !page.streamState.has(key))) streamCell(page, key)
    for (const item of page.streamImages.slice()) page.streamImageComplete(item.key, item.uri, item.token)
    assert.equal(page.streamState.position.seq, 2)
    assert.equal(page.streamImages.some(item => item.uri === oldMount.uri), false)
    const writes = file.writes.length
    page.receiveMessage({ data: envelope("return", "map.stream.view", { epoch: "e1", seq: 3, x: 0, y: 0 }) })
    const remounted = page.streamImages.find(item => item.uri === oldMount.uri)
    assert.ok(remounted)
    assert.notEqual(remounted.token, oldMount.token, "each native mount must own its callbacks")
    const before = sent.length, images = page.streamImages
    page.streamImageComplete(oldMount.key, oldMount.uri, oldMount.token)
    page.streamImageError(oldMount.key, oldMount.uri, oldMount.token)
    assert.equal(sent.length, before)
    assert.equal(page.streamImages, images)
    assert.equal(page.streamState.position.seq, 2)
    assert.equal(file.storage.has(oldMount.uri), true)
    for (const item of page.streamImages.slice()) page.streamImageComplete(item.key, item.uri, item.token)
    assert.equal(page.streamState.position.seq, 3)
    assert.equal(file.writes.length, writes, "returning to cached cells needs decode, not another transfer")
    assert.equal(sent.filter(message => message.topic === "map.cell.decoded" && message.body.cell === "0:4").length, 2)
  } finally { page.onDestroy() }
})

test("epoch replacement and destruction reject late native image callbacks", async () => {
  const { page, sent, file } = await harness()
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    page.receiveMessage({ data: envelope("view", "map.stream.view", { epoch: "e1", seq: 1, x: 0, y: 0 }) })
    streamCell(page, "0:0")
    const old = page.streamImages[0]
    page.receiveMessage({ data: envelope("open2", "map.stream.open", { scene: SCENE, epoch: "e2", version: 1 }) })
    page.receiveMessage({ data: envelope("view2", "map.stream.view", { epoch: "e2", seq: 1, x: 0, y: 0 }) })
    streamCell(page, "0:0", "epoch2", CELL_PNG, "e2")
    const current = page.streamImages[0], before = sent.length
    page.streamImageComplete(old.key, old.uri, old.token)
    page.streamImageError(old.key, old.uri, old.token)
    assert.equal(sent.length, before)
    page.streamImageComplete(current.key, current.uri, current.token)
    assert.equal(sent.filter(message => message.topic === "map.cell.decoded").length, 1)
    assert.equal(sent.at(-1).body.epoch, "e2")
    page.onDestroy()
    const destroyedImages = page.streamImages, destroyedSends = sent.length, deletes = file.deletes.length
    page.streamImageComplete(current.key, current.uri, current.token)
    page.streamImageError(current.key, current.uri, current.token)
    assert.equal(page.streamImages, destroyedImages)
    assert.equal(sent.length, destroyedSends)
    assert.equal(file.deletes.length, deletes)
  } finally { page.onDestroy() }
})

test("windowed cell transfers populate a moving viewport without replacing the full map", async () => {
  const { page, sent, file } = await harness()
  try {
    publish(page)
    const originalScene = page.confirmedMap.scene
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    // Files may arrive before the position message; admission/cache bounds must
    // protect the old frame without making payload progress wait on view ACKs.
    for (const key of corridorMap.cells(0, 0)) streamCell(page, key)
    assert.equal(sent.filter(m => m.topic === "map.cell.result" && m.body.status === "accepted").length, 10)
    assert.equal(sent.filter(m => m.topic === "map.cell.result" && m.body.status === "stored").length, 10)
    for (const result of sent.filter(m => m.topic === "map.cell.result" && m.body.status === "stored")) {
      assert.equal(result.body.request, `ce-${result.body.cell}`, "stored replies bind to the exact end command")
    }
    assert.equal(page.streamVisible, false, "write completion alone must not hide the full map")
    page.receiveMessage({ data: envelope("view1-retry", "map.stream.view", { epoch: "e1", seq: 1, x: 0, y: 0 }) })
    assert.equal(page.streamImages.length, 10)
    const state = sent.filter(m => m.topic === "map.stream.state").at(-1)
    assert.equal(state.body.perf.nodes, 10)
    assert.equal(state.body.perf.files, 10)
    assert.equal(state.body.perf.nativeMemory, null)
    assert.equal(page.perfFrame, "f456789", "staging must not advance the visible sequence label")
    assert.equal(page.perfVisual, false, "the filming overlay stays off in production")
    for (const item of page.streamImages.slice()) page.streamImageComplete(item.key, item.uri, item.token)
    assert.equal(page.streamVisible, true)
    assert.equal(page.perfFrame, "v1")
    const writes = file.writes.length
    const priorDestination = page.navDestinationStyle
    const view2 = { epoch: "e1", seq: 2, x: 0, y: 4,
      destinationMode: "visible", destinationX: 106, destinationY: 290 }
    page.receiveMessage({ data: envelope("view2", "map.stream.view", view2) })
    assert.equal(page.navDestinationStyle, priorDestination, "destination must wait for matching coverage")
    for (const key of corridorMap.cells(0, 4).filter(key => !page.streamState.has(key))) streamCell(page, key)
    page.receiveMessage({ data: envelope("view2-retry", "map.stream.view", view2) })
    for (const item of page.streamImages.slice()) page.streamImageComplete(item.key, item.uri, item.token)
    assert.equal(page.streamState.position.y, 4)
    assert.equal(page.navDestinationStyle, "left:92px;top:273px;")
    assert.equal(file.writes.length - writes, 2, "only the entering row is transferred")
    page.receiveMessage({ data: envelope("view3", "map.stream.view", { epoch: "e1", seq: 3, x: 0, y: 8 }) })
    assert.equal(page.streamState.position.y, 8)
    assert.equal(file.writes.length - writes, 2, "cached movement needs no image writes")
    assert.equal(page.confirmedMap.scene, originalScene)
    assert.ok(page.streamImages.length <= 24)
    const visible = page.streamImages.map(item => item.uri)
    page.receiveMessage({ data: envelope("retain", "map.stream.close", { epoch: "e1", retain: true }) })
    assert.equal(page.streamVisible, true, "recovery holds the latest mosaic instead of flashing the initial snapshot")
    page.receiveMessage({ data: envelope("late-view", "map.stream.view", { epoch: "e1", seq: 4, x: 0, y: 12 }) })
    assert.equal(page.streamState.position.y, 8, "a retained epoch is display-only")
    assert.deepEqual(page.streamImages.map(item => item.uri), visible)
    publish(page, "recovered-scene", "-recovery")
    assert.equal(page.streamState, null)
    for (const uri of visible) assert.equal(file.storage.has(uri), false, "new confirmed frame retires the held mosaic")
  } finally { page.onDestroy() }
})

test("changed cell content retires old pixels only after native decode", async () => {
  const { page, sent, file } = await harness()
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    page.receiveMessage({ data: envelope("view", "map.stream.view", { epoch: "e1", seq: 1, x: 0, y: 0 }) })
    for (const key of corridorMap.cells(0, 0)) streamCell(page, key)
    for (const item of page.streamImages.slice()) page.streamImageComplete(item.key, item.uri, item.token)
    const old = page.streamImages.find(item => item.key === "0:0").uri
    // A different valid image byte stream (ancillary bytes after IEND do not change native dimensions).
    streamCell(page, "0:0", "replacement", Buffer.concat([CELL_PNG, Buffer.from([0])]))
    assert.equal(sent.filter(m => m.topic === "map.cell.result").at(-1).body.status, "stored")
    assert.equal(file.storage.has(old), true)
    const replacement = page.streamImages.find(item => item.key === "0:0" && item.uri !== old)
    assert.ok(replacement)
    page.receiveMessage({ data: envelope("diag-staged", "diagnostics.get", { request: "staged" }) })
    assert.equal(sent.filter(m => m.topic === "diagnostics.report").at(-1).body.perf.files, 11,
      "old and staging versions of the same cell both count")
    page.streamImageComplete(replacement.key, replacement.uri, replacement.token)
    assert.equal(file.storage.has(old), false)
    assert.equal(page.streamVisible, true)
    assert.equal(page.streamImages.length, 10)
  } finally { page.onDestroy() }
})

test("a replacement decodes while the moving viewport still awaits entering cells", async () => {
  const { page, sent, file } = await harness()
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    page.receiveMessage({ data: envelope("view", "map.stream.view", { epoch: "e1", seq: 1, x: 0, y: 0 }) })
    for (const key of corridorMap.cells(0, 0)) streamCell(page, key)
    for (const item of page.streamImages.slice()) page.streamImageComplete(item.key, item.uri, item.token)
    const old = page.streamImages.find(item => item.key === "0:0").uri
    // GPS advances while iOS is replacing a visible cell. The sender cannot send
    // the entering row until this replacement has received its native decode reply.
    page.receiveMessage({ data: envelope("move", "map.stream.view", { epoch: "e1", seq: 2, x: 0, y: 4 }) })
    const missing = corridorMap.cells(0, 4).filter(key => !page.streamState.has(key))
    assert.equal(missing.length, 2)
    const replacementBytes = Buffer.concat([CELL_PNG, Buffer.from([0])])
    streamCell(page, "0:0", "moving-replacement", replacementBytes)
    const replacement = page.streamImages.find(item => item.key === "0:0" && item.uri !== old)
    assert.ok(replacement, "available cells must mount before all entering files arrive, or sender and decoder deadlock")
    page.streamImageComplete(replacement.key, replacement.uri, replacement.token)
    assert.ok(sent.some(message => message.topic === "map.cell.decoded" &&
      message.body.sha256 === createHash("sha256").update(replacementBytes).digest("hex")))
    assert.equal(page.streamState.position.seq, 1, "partial decoding must not expose an uncovered viewport")
    assert.equal(file.storage.has(old), true)
    for (const key of missing) {
      streamCell(page, key)
      for (const item of page.streamImages.slice()) page.streamImageComplete(item.key, item.uri, item.token)
      assert.ok(page.streamImages.length <= 24)
    }
    assert.equal(page.streamState.position.seq, 2)
    assert.equal(file.storage.has(old), false)
    const writes = file.writes.length
    for (let seq = 3; seq <= 30; seq++) {
      page.receiveMessage({ data: envelope(`move-${seq}`, "map.stream.view", { epoch: "e1", seq, x: 0, y: seq }) })
      assert.equal(page.streamState.position.seq, seq, "cached GPS updates cannot wait on image transfer or another callback")
    }
    assert.equal(file.writes.length, writes)
    assert.equal(page.confirmedMap.scene, SCENE)
  } finally { page.onDestroy() }
})

test("cell admission rejects oversized or malformed PNGs before native image allocation", async () => {
  const { page, sent, file } = await harness()
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    const before = file.writes.length
    page.receiveMessage({ data: envelope("oversize", "map.cell.begin", { epoch: "e1", cell: "0:0", bytes: 8193, sha256: DIGEST }) })
    assert.ok(sent.some(m => m.topic === "map.cell.result" && m.body.status === "error"))
    const invalid = Buffer.from(CELL_PNG)
    invalid.writeUInt32BE(4096, 16)
    streamCell(page, "0:0", "bad-dimensions", invalid)
    assert.equal(file.writes.length, before)
    assert.equal(page.streamImages.length, 0)
    assert.equal(page.streamState.count, 0)
    assert.equal(page.mapReady, true)
  } finally { page.onDestroy() }
})

test("late cell writes are retired and duplicate callbacks cannot release a newer write", async () => {
  const { page, file } = await harness()
  const pending = []
  try {
    publish(page)
    const write = file.writeArrayBuffer.bind(file)
    file.writeArrayBuffer = options => pending.push(options)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    streamCell(page, "0:0")
    assert.equal(page.streamWritePending, true)
    page.receiveMessage({ data: envelope("close", "map.stream.close", { epoch: "e1" }) })
    const old = pending.shift()
    write(old)
    assert.equal(file.storage.has(old.uri), false, "a write completing after close must not leak its file")
    page.receiveMessage({ data: envelope("open-again", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    streamCell(page, "0:1")
    assert.equal(page.streamWritePending, true)
    old.success()
    assert.equal(page.streamWritePending, true, "duplicate old completion cannot clear current write ownership")
    write(pending.shift())
    assert.equal(page.streamState.has("0:1"), true)
  } finally { page.onDestroy() }
})

test("failed cell retirement blocks further file admission until cleanup succeeds", async () => {
  const { page, file } = await harness()
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    streamCell(page, "0:0")
    const remove = file.delete.bind(file)
    file.delete = options => options.uri.includes("/cell-") ? options.fail() : remove(options)
    page.receiveMessage({ data: envelope("close", "map.stream.close", { epoch: "e1" }) })
    assert.equal(page.streamGarbage.length, 1)
    page.receiveMessage({ data: envelope("blocked-open", "map.stream.open", { scene: SCENE, epoch: "e2", version: 1 }) })
    assert.equal(page.streamState, null)
    file.delete = remove
    page.receiveMessage({ data: envelope("clean-open", "map.stream.open", { scene: SCENE, epoch: "e2", version: 1 }) })
    assert.equal(page.streamGarbage.length, 0)
    assert.equal(page.streamState.epoch, "e2")
  } finally { page.onDestroy() }
})

test("restart scrubs only owned cell files before admitting a new stream", async () => {
  const file = memoryFile(), sent = []
  file.storage.set("internal://files/cell-old-0-1.png", CELL_PNG)
  file.storage.set("internal://files/nav-kept.png", CELL_PNG)
  let listing
  file.list = options => { listing = options }
  const page = await loadPage({ getReadyState({ success }) { success({ status: 1 }) },
    send({ data, success }) { sent.push(data); if (success) success() } }, file)
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open-before-clean", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    assert.equal(sent.some(m => m.topic === "map.stream.ready"), false)
    assert.ok(listing)
    listing.success({ fileList: [{ uri: "cell-old-0-1.png" }, { uri: "internal://files/nav-kept.png" },
      { uri: "internal://files/cell-../foreign.png" }] })
    assert.equal(file.storage.has("internal://files/cell-old-0-1.png"), false)
    assert.equal(file.storage.has("internal://files/nav-kept.png"), true)
    assert.equal(file.deletes.some(uri => uri.includes("..")), false)
    page.receiveMessage({ data: envelope("open-clean", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    assert.equal(page.streamState.epoch, "e1")
  } finally { page.onDestroy() }
})

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

function stageMap(page, scene = SCENE, suffix = "") {
  page.receiveMessage({ data: envelope(`prepare${suffix}`, "render.prepare", prepare({ sceneId: scene })) })
  page.receiveMessage({ data: envelope(`begin${suffix}`, "map.asset.begin", begin({ scene })) })
  page.receiveMessage({ data: envelope(`chunk${suffix}`, "map.asset.chunk", {
    asset: ASSET, run: RUN, scene, offset: 0, data: Buffer.from(BYTES).toString("base64")
  }) })
  page.receiveMessage({ data: envelope(`end${suffix}`, "map.asset.end", { asset: ASSET, run: RUN, scene }) })
}

function publish(page, scene = SCENE, suffix = "") {
  stageMap(page, scene, suffix)
  page.mapComplete(page.pendingPublication.token)
}

// Small template-backed mount model: tid retains a node; a changed src or an
// unmounted node needs another native image load. This does not model firmware
// allocation/cache policy. DOM changes are applied only at flush(), before ticks.
async function mountedFullImages(page, file) {
  const ux = await readFile(new URL("../src/pages/index/index.ux", import.meta.url), "utf8")
  const definitions = [...ux.split("</template>")[0].matchAll(/<image\b[^>]*\/>/g)]
    .map(match => Object.fromEntries([...match[0].matchAll(/([\w@-]+)="([^"]*)"/g)]
      .map(([, name, value]) => [name, value])))
    .filter(attributes => attributes.class.split(" ").includes("map"))
  const evaluate = (expression, item) => new Function("$page", "$item",
    `with ($page) { return (${expression.replace(/^\{\{\s*|\s*\}\}$/g, "")}) }`)(page, item)
  const ticks = [], loads = [], prematureDeletes = []
  let mounted = new Map()
  page.$nextTick = callback => ticks.push(callback)
  const originalDelete = file.delete
  file.delete = function (options) {
    if ([...mounted.values()].some(node => node.uri === options.uri)) prematureDeletes.push(options.uri)
    originalDelete.call(file, options)
  }
  function flush(runTicks = true) {
    const next = new Map()
    if (page.connected && (page.mapReady || page.pendingPublication)) {
      definitions.forEach((definition, index) => {
        const items = definition.for ? evaluate(definition.for) : [null]
        for (const item of items) {
          if (definition.if && !evaluate(definition.if, item)) continue
          const key = `${index}:${definition.for ? item[definition.tid] : "single"}`
          const uri = evaluate(definition.src, item)
          let node = mounted.get(key)
          if (!node || node.uri !== uri) {
            const callback = name => {
              const event = definition[`@${name}`]
              if (!event) return () => {}
              const [, method, argumentsExpression] = event.match(/^(\w+)\((.*)\)$/)
              const args = evaluate(`[${argumentsExpression}]`, item)
              return () => page[method](...args)
            }
            node = { uri, decoded: false, complete: callback("complete"), error: callback("error") }
            loads.push(node)
          }
          node.style = definition.style ? evaluate(definition.style, item) : ""
          next.set(key, node)
        }
      })
    }
    mounted = next
    if (runTicks) {
      const ready = ticks.splice(0)
      for (const callback of ready) callback()
    }
    assert.deepEqual(prematureDeletes, [], "a file must outlive every mounted image using it")
    return [...mounted.values()]
  }
  return { flush, loads, complete(node) { node.decoded = true; node.complete() } }
}

test("twenty full-frame publications retain the decoded node and retire files after unmount", async () => {
  const { page, sent, file } = await harness()
  const images = await mountedFullImages(page, file)
  let confirmed
  for (let index = 0; index < 20; index++) {
    stageMap(page, `scene-${index.toString().padStart(10, "0")}`, `-retained-${index}`)
    const staged = images.flush().find(node => node !== confirmed)
    assert.ok(staged)
    assert.equal(staged.style, "opacity:0;", "pending pixels must not obscure the last complete map")
    if (confirmed) assert.equal(confirmed.style, "opacity:1;")
    assert.equal(images.loads.length, index + 1, "one image load per transferred frame")
    assert.ok(images.flush().length <= 2, "at most confirmed and pending images are mounted")
    const previous = confirmed
    images.complete(staged)
    staged.complete()
    staged.error()
    if (previous) { previous.complete(); previous.error() }
    assert.deepEqual(images.flush(), [staged], "publication must keep its already decoded image node")
    assert.ok(staged.decoded)
    assert.equal(staged.style, "opacity:1;")
    staged.complete()
    staged.error()
    if (previous) { previous.complete(); previous.error() }
    assert.deepEqual(images.flush(), [staged])
    assert.equal(sent.filter(message => message.topic === "render.result").length, index + 1)
    assert.equal(file.storage.size, 1)
    confirmed = staged
    page.streamVisible = true
    assert.deepEqual(images.flush(), [confirmed], "corridor coverage must not remount the fallback image")
    assert.equal(confirmed.style, "opacity:0;")
    page.streamVisible = false
    assert.deepEqual(images.flush(), [confirmed])
    assert.equal(confirmed.style, "opacity:1;")
  }
  assert.equal(images.loads.length, 20)
  assert.equal(file.deletes.length, 19)
  page.onDestroy()
  images.flush()
  confirmed.complete()
  confirmed.error()
  assert.equal(sent.filter(message => message.topic === "render.result").length, 20)
})

test("failed and reset full-frame mounts preserve the last decoded map and ignore stale callbacks", async () => {
  const { page, sent, file } = await harness()
  const images = await mountedFullImages(page, file)
  stageMap(page)
  const confirmed = images.flush()[0]
  images.complete(confirmed)
  images.flush()
  stageMap(page, "scene-1111111111", "-error")
  const failed = images.flush().find(node => node !== confirmed)
  failed.error()
  assert.deepEqual(images.flush(), [confirmed])
  failed.complete()
  failed.error()
  assert.equal(sent.filter(message => message.topic === "render.result").length, 2)
  assert.equal(sent.filter(message => message.topic === "render.result")[1].body.status, "error")
  stageMap(page, "scene-2222222222", "-reset")
  const stale = images.flush().find(node => node !== confirmed)
  page.resetMapLifecycle()
  assert.deepEqual(images.flush(), [confirmed])
  stageMap(page, "scene-3333333333", "-next")
  const pending = images.flush().find(node => node !== confirmed)
  stale.complete()
  stale.error()
  assert.equal(page.pendingPublication.scene, "scene-3333333333")
  page.onDestroy()
  assert.deepEqual(images.flush(), [])
  pending.complete()
  pending.error()
  assert.equal(sent.filter(message => message.topic === "render.result").length, 2)
  assert.ok(file.storage.has(confirmed.uri))
  assert.equal(file.storage.size, 2) // Destroyed pages defer abandoned cleanup to startup.
})

test("startup removes owned full frames when destruction drops a queued DOM retirement", async () => {
  const { page, file, connection } = await harness()
  const images = await mountedFullImages(page, file)
  stageMap(page)
  images.complete(images.flush()[0])
  images.flush()
  stageMap(page, "scene-1111111111", "-destroyed")
  const pending = images.flush().find(node => !node.decoded)
  images.complete(pending)
  page.onDestroy()
  assert.equal(page.activeMapOperationID, "")
  images.flush(false) // A destroyed page is allowed to drop its next DOM callback.
  file.storage.set("internal://files/unrelated.png", BYTES)
  file.storage.set("internal://files/nav-not-an-owned-digest.png", BYTES)
  await loadPage(connection, file)
  assert.deepEqual([...file.storage.keys()].sort(), [
    "internal://files/nav-not-an-owned-digest.png", "internal://files/unrelated.png"
  ])
})

test("startup full-frame scrub recognizes only owned names and preserves a concurrently mounted map", async () => {
  const file = memoryFile()
  const abandoned = "internal://files/nav-0000000000000000-scene-1111111111.jpg"
  const unrelated = "internal://files/nav-not-an-owned-digest.png"
  file.storage.set(abandoned, BYTES)
  file.storage.set(unrelated, BYTES)
  let finishList
  file.list = ({ success }) => { finishList = success }
  const page = await loadPage({
    getReadyState({ success }) { success({ status: 1 }) }, send() {}
  }, file)
  stageMap(page)
  const liveURI = page.pendingPublication.uri
  finishList({ fileList: [...file.storage.keys()].map(uri => ({ uri })) })
  assert.ok(!file.storage.has(abandoned), "a new page must recover files whose DOM retirement was dropped")
  assert.ok(file.storage.has(unrelated))
  assert.ok(file.storage.has(liveURI), "late directory listing must not delete the current publication")
  page.mapComplete(page.pendingPublication.token)
})

test("a destroyed page's delayed DOM retirement cannot delete its successor's confirmed file", async () => {
  const { page, file, connection } = await harness()
  const images = await mountedFullImages(page, file)
  stageMap(page)
  images.complete(images.flush()[0])
  images.flush()
  stageMap(page, "scene-1111111111", "-old-page")
  images.complete(images.flush().find(node => !node.decoded))
  page.onDestroy()
  images.flush(false)
  const successor = await loadPage(connection, file)
  publish(successor, "scene-2222222222", "-new-page")
  const currentURI = successor.confirmedMap.uri
  assert.ok(file.storage.has(currentURI))
  images.flush() // The former page's queued callback arrives after URI reuse.
  assert.ok(file.storage.has(currentURI), "a destroyed page must not delete its successor's confirmed file")
  assert.equal(successor.mapImages.length, 1)
})

test("unavailable DOM retirement hook keeps the file and releases completed publication ownership", async () => {
  const { page, file } = await harness()
  publish(page)
  const previousURI = page.confirmedMap.uri
  delete page.$nextTick
  publish(page, "scene-1111111111", "-missing-tick")
  assert.equal(page.confirmedMap.scene, "scene-1111111111")
  assert.equal(page.pendingPublication, null)
  assert.equal(page.activeMapOperationID, "")
  assert.equal(page.retiredMapURI, previousURI)
  assert.ok(file.storage.has(previousURI), "never delete before an unavailable DOM update hook")
  assert.deepEqual(page.pendingDeleteURIs, [])
})

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
    sha256Prefix: DIGEST.slice(0, 8),
    perf: sent.find(message => message.topic === "render.result").body.perf
  })
})

test("full-frame telemetry separates native write, image callback, JS apply and retirement", async () => {
  let now = 1000, finishWrite, finishDelete
  const sent = [], file = memoryFile()
  const page = await loadPage({
    getReadyState({ success }) { success({ status: 1 }) }, send({ data }) { sent.push(data) }
  }, file, { now: () => now })
  try {
    publish(page)
    const write = file.writeArrayBuffer.bind(file), remove = file.delete.bind(file)
    file.writeArrayBuffer = options => { finishWrite = () => write(options) }
    file.delete = options => { finishDelete = () => remove(options) }
    const apply = page.applyPreviewOverlay.bind(page)
    page.applyPreviewOverlay = value => { apply(value); now += 5 }
    page.receiveMessage({ data: envelope("prepare2", "render.prepare", prepare({ sceneId: "scene2" })) })
    page.receiveMessage({ data: envelope("begin2", "map.asset.begin", begin({ scene: "scene2" })) })
    page.receiveMessage({ data: envelope("chunk2", "map.asset.chunk", {
      asset: ASSET, run: RUN, scene: "scene2", offset: 0, data: Buffer.from(BYTES).toString("base64")
    }) })
    now = 1100
    page.receiveMessage({ data: envelope("end2", "map.asset.end", { asset: ASSET, run: RUN, scene: "scene2" }) })
    now = 1117
    finishWrite()
    now = 1140
    page.mapComplete(page.pendingPublication.token)
    assert.equal(sent.filter(m => m.topic === "render.result").length, 1, "result still awaits retirement")
    now = 1190
    finishDelete()
    assert.deepEqual(sent.filter(m => m.topic === "render.result").at(-1).body.perf,
      { v: 1, clockValid: true, writeMs: 17, decodeMs: 23, applyMs: 5, cleanupMs: 45 })
    assert.ok(sent.every(m => Buffer.byteLength(JSON.stringify(m)) <= 512))
  } finally { page.onDestroy() }
})

test("cell telemetry counts staged files and measures each mounted image only once", async () => {
  let now = 1000, finishWrite
  const sent = [], file = memoryFile()
  const page = await loadPage({
    getReadyState({ success }) { success({ status: 1 }) }, send({ data }) { sent.push(data) }
  }, file, { now: () => now })
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    page.receiveMessage({ data: envelope("view", "map.stream.view", { epoch: "e1", seq: 1, x: 0, y: 0 }) })
    const write = file.writeArrayBuffer.bind(file)
    file.writeArrayBuffer = options => { finishWrite = () => write(options) }
    streamCell(page, "0:0")
    page.receiveMessage({ data: envelope("diag1", "diagnostics.get", { request: "perf-1", visual: true }) })
    const during = sent.filter(m => m.topic === "diagnostics.report").at(-1).body
    assert.equal(during.perfVersion, 1)
    assert.deepEqual(during.perf, { v: 1, clockValid: true, files: 1, nodes: 0, pendingDeletes: 0, inFlight: 1, nativeMemory: null })
    now += 17
    finishWrite()
    const stored = sent.filter(m => m.topic === "map.cell.result" && m.body.status === "stored").at(-1)
    assert.deepEqual(stored.body.perf, { v: 1, clockValid: true, writeMs: 17 })
    const item = page.streamImages[0]
    now += 23
    page.streamImageComplete(item.key, item.uri, item.token)
    assert.deepEqual(sent.filter(m => m.topic === "map.cell.decoded").at(-1).body.perf,
      { v: 1, clockValid: true, decodeMs: 23 })
    now += 99
    page.streamImageComplete(item.key, item.uri, item.token)
    assert.equal(sent.filter(m => m.topic === "map.cell.decoded").length, 1,
      "duplicate callback must not send another decoded envelope")
    const manifest = JSON.parse(await readFile(new URL("../src/manifest.json", import.meta.url)))
    assert.equal(during.rpk, manifest.versionCode)
    assert.equal(during.versionName, manifest.versionName)
    assert.equal(page.perfVisual, true)
    page.connection.onclose()
    assert.equal(page.perfVisual, false, "filming is opt-in per connection lifecycle")
    page.probeConnection()
    page.receiveMessage({ data: envelope("diag2", "diagnostics.get", { request: "perf-2", visual: false }) })
    assert.equal(page.perfVisual, false)
    assert.ok(sent.every(m => Buffer.byteLength(JSON.stringify(m)) <= 512))
  } finally { page.onDestroy() }
})

test("a regressing Band clock yields unavailable durations rather than false zero latency", async () => {
  let now = 1000, finishWrite
  const sent = [], file = memoryFile()
  const page = await loadPage({
    getReadyState({ success }) { success({ status: 1 }) }, send({ data }) { sent.push(data) }
  }, file, { now: () => now })
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    const write = file.writeArrayBuffer.bind(file)
    file.writeArrayBuffer = options => { finishWrite = () => write(options) }
    streamCell(page, "0:0")
    now = 900
    finishWrite()
    assert.deepEqual(sent.filter(m => m.topic === "map.cell.result" && m.body.status === "stored").at(-1).body.perf,
      { v: 1, clockValid: false, writeMs: null })
    page.receiveMessage({ data: envelope("diag", "diagnostics.get", { request: "clock" }) })
    assert.equal(sent.filter(m => m.topic === "diagnostics.report").at(-1).body.perf.clockValid, false)
    page.receiveMessage({ data: envelope("diag-render", "diagnostics.get", { request: "clock-render", render: true }) })
    assert.deepEqual(sent.filter(m => m.topic === "diagnostics.report").at(-1).body.perf,
      { v: 1, clockValid: false, writeMs: null, decodeMs: null, applyMs: null, cleanupMs: null },
      "stored aggregates must carry current clock invalidity too")
  } finally { page.onDestroy() }
})

test("telemetry keeps independent application vectors and maximal missing-cell replies within 512 bytes", async () => {
  const adr = await readFile(new URL("../../../docs/adr/0020-performance-trace.md", import.meta.url), "utf8")
  const vectors = [...adr.matchAll(/```json\n([^`]+)```/g)].flatMap(match => match[1].trim().split("\n").map(JSON.parse))
  assert.ok(vectors.length >= 5)
  const { page, sent } = await harness()
  try {
    for (const vector of vectors) {
      assert.ok(Buffer.byteLength(JSON.stringify(vector)) <= 512, vector.topic)
      if (vector.src === "band") {
        page.sendEnvelope(structuredClone(vector))
        assert.deepEqual(sent.at(-1), vector, "the literal vector must be sent without truncation")
      }
    }
    publish(page)
    const epoch = "e".repeat(24)
    page.receiveMessage({ data: envelope("open-max", "map.stream.open", { scene: SCENE, epoch, version: 1 }) })
    page.receiveMessage({ data: envelope("view-max", "map.stream.view", { epoch, seq: 2147483647, x: -32705, y: -32761 }) })
    const reply = sent.filter(m => m.topic === "map.stream.state").at(-1)
    assert.equal(reply.body.missing.length, 18)
    assert.equal(reply.body.perf.v, 1)
    assert.equal(reply.body.perf.applyMs >= 0, true)
    assert.ok(Buffer.byteLength(JSON.stringify(reply)) <= 512)
  } finally { page.onDestroy() }
})

test("decode failure telemetry retains pending cleanup without accepting stale callbacks", async () => {
  const { page, sent, file } = await harness()
  try {
    publish(page)
    page.receiveMessage({ data: envelope("open", "map.stream.open", { scene: SCENE, epoch: "e1", version: 1 }) })
    page.receiveMessage({ data: envelope("view", "map.stream.view", { epoch: "e1", seq: 1, x: 0, y: 0 }) })
    streamCell(page, "0:0")
    const item = page.streamImages[0]
    file.delete = () => {}
    page.streamImageError(item.key, item.uri, item.token)
    const failure = sent.filter(m => m.topic === "map.stream.state").at(-1)
    assert.equal(failure.body.code, "decodeFailed")
    assert.deepEqual(failure.body.perf, { v: 1, clockValid: true, files: 1, nodes: 0,
      pendingDeletes: 1, inFlight: 0, nativeMemory: null, applyMs: failure.body.perf?.applyMs })
    assert.equal(typeof failure.body.perf.applyMs, "number")
    const count = sent.length
    page.streamImageComplete(item.key, item.uri, item.token)
    page.streamImageError(item.key, item.uri, item.token)
    assert.equal(sent.length, count)
  } finally { page.onDestroy() }
})

test("re-acknowledges an exact duplicate chunk without writing it twice", async () => {
  const { page, sent, file } = await harness()
  page.receiveMessage({ data: envelope("prepare", "render.prepare", prepare()) })
  page.receiveMessage({ data: envelope("begin", "map.asset.begin", begin()) })
  const chunk = envelope("chunk-retry", "map.asset.chunk", {
    asset: ASSET, run: RUN, scene: SCENE, offset: 0,
    data: Buffer.from(BYTES).toString("base64")
  })

  page.receiveMessage({ data: chunk })
  page.receiveMessage({ data: chunk })
  page.receiveMessage({ data: envelope("end", "map.asset.end", { asset: ASSET, run: RUN, scene: SCENE }) })

  assert.equal(file.writes.length, 1)
  assert.deepEqual(file.storage.get(`internal://files/${ASSET}.png`), BYTES)
  assert.equal(sent.filter(message => message.type === "ack" && message.id === "chunk-retry").length, 2)
})

test("a native ACK timeout does not erase a transfer before the phone retries", async () => {
  const { page, connection, sent } = await harness()
  const sends = []
  connection.send = options => { sends.push(options); sent.push(options.data) }
  try {
    page.receiveMessage({ data: envelope("prepare", "render.prepare", prepare()) })
    page.receiveMessage({ data: envelope("begin", "map.asset.begin", begin()) })
    const chunk = envelope("chunk-retry", "map.asset.chunk", {
      asset: ASSET, run: RUN, scene: SCENE, offset: 0,
      data: Buffer.from(BYTES).toString("base64")
    })
    page.receiveMessage({ data: chunk })
    const transfer = page.activeTransfer
    sends.find(send => send.data.id === chunk.id).fail("timeout", 204)

    assert.equal(page.connected, true, "a send timeout is not a disconnect event")
    assert.equal(page.activeTransfer, transfer, "retain accepted bytes for exact-command retry")
    page.receiveMessage({ data: JSON.stringify(chunk) })
    assert.equal(transfer.receivedBytes, BYTES.length)
    assert.equal(sent.filter(message => message.id === chunk.id && message.type === "ack").length, 2)
  } finally {
    page.onDestroy()
  }
})

test("full-size maps survive asynchronous file and send callbacks across repeated refreshes", async () => {
  const callbacks = []
  const sent = []
  const file = memoryFile()
  for (const name of ["access", "delete", "writeArrayBuffer"]) {
    const operation = file[name].bind(file)
    file[name] = options => callbacks.push(() => operation(options))
  }
  const connection = {
    getReadyState({ success }) { success({ status: 1 }) },
    failedIDs: new Set(),
    send({ data, success, fail }) {
      if (data.type === "ack" && /-480$/.test(data.id) && !this.failedIDs.has(data.id)) {
        this.failedIDs.add(data.id)
        callbacks.push(() => fail({ code: 204 }))
        return
      }
      sent.push(JSON.parse(JSON.stringify(data)))
      if (success) callbacks.push(success)
    }
  }
  const page = await loadPage(connection, file)
  const flush = () => { while (callbacks.length) callbacks.shift()() }
  const receive = message => {
    const wire = JSON.stringify(message)
    assert.ok(Buffer.byteLength(wire) <= 940, "exercise admitted envelopes")
    page.receiveMessage({ data: wire })
    flush()
    if (!sent.some(item => item.type === "ack" && item.id === message.id)) {
      page.receiveMessage({ data: wire }) // the phone retries the identical command once
      flush()
    }
    assert.ok(sent.some(item => item.type === "ack" && item.id === message.id), `missing ACK ${message.id}`)
  }
  try {
    for (let run = 0; run < 100; run += 1) {
      const bytes = Uint8Array.from({ length: 8192 }, (_, index) => (index * 37 + run) & 255)
      const sha256 = createHash("sha256").update(bytes).digest("hex")
      const asset = `nav-${sha256.slice(0, 16)}`
      const scene = `scene-${run}`
      receive(envelope(`prepare-${run}`, "render.prepare", prepare({ sceneId: scene, bytes: bytes.length, sha256, preview: preview() })))
      receive(envelope(`begin-${run}`, "map.asset.begin", begin({ asset, scene, bytes: bytes.length, sha256 })))
      const offsets = Array.from({ length: Math.ceil(bytes.length / 480) }, (_, index) => index * 480)
      // Alternate stop-and-wait with reordered two/four-chunk windows, including a
      // native 204 on the later chunk and its identical command retry.
      const window = [1, 2, 4][run % 3]
      for (let index = 0; index < offsets.length; index += window)
        offsets.splice(index, window, ...offsets.slice(index, index + window).reverse())
      for (const offset of offsets) {
        const chunk = envelope(`chunk-${run}-${offset}`, "map.asset.chunk", {
          asset, scene, run: RUN, offset, data: Buffer.from(bytes.subarray(offset, offset + 480)).toString("base64")
        })
        receive(chunk)
        if (offset === 480) receive(chunk) // exact retry must not append twice
      }
      receive(envelope(`end-${run}`, "map.asset.end", { asset, scene, run: RUN }))
      assert.deepEqual(file.storage.get(page.pendingMapPath), bytes)
      assert.notEqual(page.confirmedMap?.scene, scene, "do not promote before image decode")
      page.mapComplete(page.pendingPublication.token)
      flush()
      assert.equal(page.confirmedMap.scene, scene)
      assert.equal(page.navMarkerVisible, true)
      assert.ok(sent.some(item => item.topic === "render.result" && item.body.sceneId === scene && item.body.status === "ok"))
      assert.ok(file.storage.size <= 2, "keep file storage bounded")
    }
    assert.equal(connection.failedIDs.size, 100, "inject one native send failure per map")
  } finally {
    page.onDestroy()
    flush()
  }
})

test("native disconnect still clears the transfer and stale failures cannot reset a new session", async () => {
  const { page, connection } = await harness()
  const sends = []
  connection.send = options => sends.push(options)
  try {
    page.receiveMessage({ data: envelope("prepare", "render.prepare", prepare()) })
    page.receiveMessage({ data: envelope("begin", "map.asset.begin", begin()) })
    const oldFailure = sends[0].fail
    oldFailure("disconnected", 1006)
    assert.equal(page.connected, false)
    assert.equal(page.activeTransfer, null)
    page.probeConnection()
    assert.equal(page.connected, true)
    page.receiveMessage({ data: envelope("prepare-2", "render.prepare", prepare()) })
    const prepared = page.preparedRender
    oldFailure("late error", 1006)
    assert.equal(page.connected, true)
    assert.equal(page.preparedRender, prepared)
  } finally {
    page.onDestroy()
  }
})

test("failure diagnostics retain the last chunk boundary without returning payloads", async () => {
  const { page, connection, sent } = await harness()
  const sends = []
  connection.send = options => { sends.push(options); sent.push(options.data) }
  try {
    page.receiveMessage({ data: envelope("prepare", "render.prepare", prepare()) })
    page.receiveMessage({ data: envelope("begin", "map.asset.begin", begin()) })
    page.receiveMessage({ data: envelope("chunk", "map.asset.chunk", {
      asset: ASSET, run: RUN, scene: SCENE, offset: 0, data: Buffer.from(BYTES).toString("base64")
    }) })
    page.receiveMessage({ data: envelope("diagnostic", "diagnostics.get", { request: "probe-1" }) })
    const report = sent.find(message => message.topic === "diagnostics.report")
    assert.ok(report, "automatically queryable peer diagnostics are required")
    assert.deepEqual(report.body, {
      request: "probe-1", rpk: page.rpkBuild, versionName: page.rpkVersion, perfVersion: 1,
      phase: "chunk", offset: 0, received: 4, sendCode: 0,
      perf: { v: 1, clockValid: true, files: 0, nodes: 0, pendingDeletes: 0, inFlight: 1, nativeMemory: null }
    })
    assert.ok(Buffer.byteLength(JSON.stringify(report)) < 512)
    sends.find(send => send.data.id === "chunk").fail({ code: 204 })
    page.receiveMessage({ data: envelope("prepare", "render.prepare", prepare()) })
    page.receiveMessage({ data: envelope("diagnostic-retry", "diagnostics.get", { request: "probe-2" }) })
    const retryReport = sent.filter(message => message.topic === "diagnostics.report").at(-1)
    assert.equal(retryReport.body.sendCode, 204, "duplicate prepare must not erase native failure evidence")
    assert.equal(retryReport.body.received, 4)
    const count = sent.length
    page.receiveMessage({ data: envelope("bad-probe", "diagnostics.get", { request: "x".repeat(33) }) })
    assert.equal(sent.length, count, "invalid diagnostic request must not produce traffic")
  } finally {
    page.onDestroy()
  }
})

test("stores and publishes a prepared JPEG with a jpg extension", async () => {
  const { page, file } = await harness()
  page.receiveMessage({ data: envelope("prepare-jpeg", "render.prepare", prepare({ format: "image/jpeg" })) })
  page.receiveMessage({ data: envelope("begin-jpeg", "map.asset.begin", begin({ format: "image/jpeg", mime: "image/jpeg" })) })
  page.receiveMessage({ data: envelope("chunk-jpeg", "map.asset.chunk", {
    asset: ASSET, run: RUN, scene: SCENE, offset: 0, data: Buffer.from(BYTES).toString("base64")
  }) })
  page.receiveMessage({ data: envelope("end-jpeg", "map.asset.end", { asset: ASSET, run: RUN, scene: SCENE }) })

  assert.equal(page.pendingMapPath, `internal://files/${ASSET}.jpg`)
  assert.deepEqual(file.storage.get(page.pendingMapPath), BYTES)
  page.mapComplete(page.pendingPublication.token)
  assert.equal(page.mapPath, `internal://files/${ASSET}.jpg`)
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
  assert.equal(page.navMarkerPath, "/common/marker-cursor-v4.png")
  assert.equal(page.navMarkerStyle, "left:91px;top:355px;")
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
    assert.equal(page.navMarkerPath, "/common/marker-cursor-v4.png")
    assert.equal(page.navMarkerStyle, "left:91px;top:355px;")
  })
})

test("destination overlay switches atomically and stays inside the curved safe mask", async () => {
  const { page } = await harness()
  assert.equal(page.destinationDirection(106, 374, 106, 22), 0)
  assert.equal(page.destinationDirection(106, 374, 190, 290), 1)
  assert.equal(page.destinationDirection(106, 374, 199, 260), 1)
  assert.equal(page.destinationDirection(106, 374, 22, 374), 6)
  assert.deepEqual(page.destinationOverlay("edge", 12, 260), {
    path: "/common/destination-edge-7.png", style: "left:0px;top:248px;width:24px;height:24px;"
  })
  publish(page)
  page.receiveMessage({ data: envelope("visible", "nav.update", navigation({
    destinationMode: "visible", destinationX: 106, destinationY: 120
  })) })
  assert.equal(page.navDestinationVisible, true)
  assert.equal(page.navDestinationPath, "/common/destination-pin.png")
  assert.equal(page.navDestinationStyle, "left:92px;top:103px;")

  page.receiveMessage({ data: envelope("edge", "nav.update", navigation({
    seq: 2, destinationMode: "edge", destinationX: 200, destinationY: 260
  })) })
  assert.equal(page.navDestinationPath, "/common/destination-edge-1.png")
  assert.equal(page.navDestinationStyle, "left:188px;top:248px;width:24px;height:24px;")

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

test("render.prepare accepts an edge destination whose full chevron stays inside the visual mask", async () => {
  const { page, sent } = await harness()
  page.receiveMessage({ data: envelope("prepare-edge", "render.prepare", prepare({
    preview: preview({ destinationMode: "edge", destinationX: 186, destinationY: 260 })
  })) })

  assert.equal(sent.find(message => message.topic === "render.reject"), undefined)
  assert.equal(sent.find(message => message.topic === "render.ready").body.sceneId, SCENE)
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
  assert.equal(page.navMarkerPath, "/common/marker-cursor-v4.png")
  assert.equal(page.navMarkerStyle, "left:91px;top:355px;")
  assert.equal(page.navDestinationVisible, true)
  assert.equal(page.navDestinationPath, "/common/destination-pin.png")
  assert.equal(page.navDestinationStyle, "left:92px;top:103px;")
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

test("roundabout geometry overrides exit number in preview and live guidance", async () => {
  const { page } = await harness()
  page.receiveMessage({ data: envelope("direction-preview", "render.prepare", prepare({
    preview: preview({ maneuver: "roundabout", roundaboutExit: 2, roundaboutDirection: "straight" })
  })) })
  assert.equal(page.navArrowPath, "/common/maneuver-roundabout-straight.png")
  page.receiveMessage({ data: envelope("direction-cancel", "render.cancel", { runId: RUN, sceneId: SCENE }) })
  publish(page)
  let seq = 0
  for (const direction of ["straight", "left", "right", "uTurn"]) {
    page.receiveMessage({ data: envelope(`direction-${direction}`, "nav.update", navigation({
      seq: ++seq, maneuver: "roundabout", roundaboutExit: 2, roundaboutDirection: direction
    })) })
    assert.equal(page.navArrowPath, direction === "uTurn" ? "/common/maneuver-uTurn.png" : `/common/maneuver-roundabout-${direction}.png`)
  }
  for (const direction of ["arrive", "../../bad", 2, null]) {
    page.receiveMessage({ data: envelope(`invalid-direction-${seq++}`, "nav.update", navigation({
      seq: 100, maneuver: "roundabout", roundaboutDirection: direction
    })) })
    assert.equal(page.navSequence, 4, "invalid direction cannot replace the current scene guidance")
  }
})

test("roundabout preview and live guidance show the provider exit without inventing a right turn", async () => {
  const { page } = await harness()
  page.receiveMessage({ data: envelope("exit-preview", "render.prepare", prepare({
    preview: preview({ maneuver: "roundabout", roundaboutExit: 2 })
  })) })
  assert.equal(page.navArrowPath, "/common/maneuver-roundabout-2.png")
  page.receiveMessage({ data: envelope("exit-cancel", "render.cancel", { runId: RUN, sceneId: SCENE }) })
  publish(page)
  for (const exit of [1, 2, 3, 12]) {
    page.receiveMessage({ data: envelope(`exit-${exit}`, "nav.update", navigation({
      seq: exit, maneuver: "roundabout", roundaboutExit: exit
    })) })
    assert.equal(page.navArrowPath, `/common/maneuver-roundabout-${exit}.png`)
  }
  page.receiveMessage({ data: envelope("exit-bad", "nav.update", navigation({
    seq: 13, maneuver: "roundabout", roundaboutExit: 99
  })) })
  assert.equal(page.navSequence, 12, "invalid exit cannot overwrite valid guidance")
})

test("explicit reset after suspension releases incomplete publication and ignores its late decode", async () => {
  const { page, sent, file } = await harness()
  publish(page)
  const confirmed = page.mapPath
  const write = file.writeArrayBuffer
  let finishWrite
  file.writeArrayBuffer = options => { finishWrite = () => write(options) }
  page.receiveMessage({ data: envelope("resume-prepare", "render.prepare", prepare({ sceneId: "resume-scene" })) })
  page.receiveMessage({ data: envelope("resume-begin", "map.asset.begin", begin({ scene: "resume-scene" })) })
  page.receiveMessage({ data: envelope("resume-chunk", "map.asset.chunk", { asset: ASSET, run: RUN, scene: "resume-scene", offset: 0, data: Buffer.from(BYTES).toString("base64") }) })
  page.receiveMessage({ data: envelope("resume-end", "map.asset.end", { asset: ASSET, run: RUN, scene: "resume-scene" }) })
  page.receiveMessage({ data: envelope("write-reset", "render.reset", { runId: RUN, sceneId: "resume-scene" }) })
  assert.equal(sent.some(message => message.topic === "render.reset.ready" && message.body.request === "write-reset"), false,
    "wait for native file I/O before resetting, otherwise a late write can recreate an orphaned asset")
  finishWrite()
  const staleToken = page.pendingMapToken
  assert.ok(staleToken)
  page.receiveMessage({ data: envelope("wrong-reset", "render.reset", { runId: "wrong", sceneId: "resume-scene" }) })
  assert.equal(page.pendingMapToken, staleToken, "a reset cannot cancel another live run")
  assert.equal(sent.some(message => message.topic === "render.reset.ready" && message.body.request === "wrong-reset"), false)
  page.receiveMessage({ data: envelope("resume-reset", "render.reset", { runId: RUN, sceneId: "resume-scene" }) })
  assert.equal(page.pendingPublication, null)
  assert.equal(page.activeTransfer, null)
  assert.equal(page.preparedRender, null)
  assert.equal(page.mapPath, confirmed)
  page.mapComplete(staleToken)
  assert.equal(page.mapPath, confirmed)
  assert.ok(sent.some(message => message.topic === "render.reset.ready" && message.body.request === "resume-reset"))
  page.receiveMessage({ data: envelope("resume-reset", "render.reset", { runId: RUN, sceneId: "resume-scene" }) })
  assert.equal(sent.filter(message => message.topic === "render.reset.ready" && message.body.request === "resume-reset").length, 2,
    "an exact-command retry must replay both the ready response and ACK")
  page.receiveMessage({ data: envelope("resume-fresh", "render.prepare", prepare({ sceneId: "fresh-scene" })) })
  assert.equal(page.preparedRender.sceneId, "fresh-scene")
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
  assert.equal(page.navStreet, "Old Road")
  page.receiveMessage({ data: envelope("nav-latest", "nav.update", {
    scene: SCENE, seq: 2, x: 108, y: 318, heading: 3,
    maneuver: "straight", distanceM: 120, street: "Latest Road", status: "navigating",
    destinationMode: "hidden", destinationX: 0, destinationY: 0
  }) })
  assert.equal(page.navArrowPath, "/common/maneuver-straight.png")
  assert.equal(page.navDistance, "120 m")
  assert.equal(page.navStreet, "Latest Road")
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
  assert.equal(page.navMarkerPath, "/common/marker-cursor-v4.png")

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
  assert.equal(page.navMarkerPath, "/common/marker-cursor-v4.png")
  assert.equal(page.navDestinationPath, "/common/destination-edge-1.png")
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
