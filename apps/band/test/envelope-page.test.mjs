import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function loadPage(connection) {
  const ux = await readFile(new URL("../src/pages/index/index.ux", import.meta.url), "utf8")
  const script = ux.match(/<script>([\s\S]*?)<\/script>/)[1]
    .replace(/import interconnect from ["']@system\.interconnect["']/, "")
    .replace("export default", "return")
  const component = new Function("interconnect", script)({ instance() { return connection } })
  const page = structuredClone(component.private)
  for (const [name, value] of Object.entries(component)) if (name !== "private") page[name] = value
  page.onReady()
  return page
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
