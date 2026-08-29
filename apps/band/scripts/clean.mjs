import { rm } from "node:fs/promises"
import { dirname, join, relative, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const root = resolve(fileURLToPath(new URL("../", import.meta.url)))
const parent = dirname(root)
const targets = [
  join(root, "build"),
  join(root, "dist"),
  join(parent, ".temp_blueband-map-rpk")
]

for (const target of targets) {
  const owner = target.startsWith(root) ? root : parent
  const pathFromOwner = relative(owner, target)
  if (!pathFromOwner || pathFromOwner.startsWith("..")) {
    throw new Error(`refusing to clean unexpected path: ${target}`)
  }
  await rm(target, { recursive: true, force: true })
}
