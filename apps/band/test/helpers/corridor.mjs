import { readFile } from "node:fs/promises"

// Exercise the shipped inline helper, not a separately compiled/reference implementation.
const page = await readFile(new URL("../../src/pages/index/index.ux", import.meta.url), "utf8")
const source = page.match(/\/\/ BEGIN CORRIDOR MAP\n([\s\S]*?)\/\/ END CORRIDOR MAP/)[1]
export default new Function(`${source}\nreturn corridorMap`)()
