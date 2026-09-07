// Optional offline artwork regeneration. Normal builds use the checked-in PNGs.
const { createCanvas, loadImage } = require('@napi-rs/canvas')
const { readFile, writeFile } = require('node:fs/promises')
const { resolve } = require('node:path')

async function main() {
  const icons = { straight: 'straight', left: 'turn_left', right: 'turn_right',
    uTurn: 'u_turn_left', arrive: 'place' }
  for (const [maneuver, icon] of Object.entries(icons)) {
    const svg = await readFile(resolve(__dirname, `../vendor/material-icons/${icon}.svg`), 'utf8')
    const image = await loadImage(Buffer.from(svg.replace('<svg ', '<svg fill="#00e5ff" ')))
    const canvas = createCanvas(44, 56)
    canvas.getContext('2d').drawImage(image, 0, 6, 44, 44)
    await writeFile(resolve(__dirname, `../src/common/maneuver-${maneuver}.png`), canvas.toBuffer('image/png'))
  }
  const svg = await readFile(resolve(__dirname, '../vendor/mapbox-directions/roundabout.svg'), 'utf8')
  const roundabout = await loadImage(Buffer.from(svg.replaceAll('#000000', '#00e5ff')))
  for (let exit = 0; exit <= 12; exit++) {
    const canvas = createCanvas(44, 56), context = canvas.getContext('2d')
    context.drawImage(roundabout, -10, -4, 64, 64)
    if (exit) {
      context.fillStyle = '#ffffff'
      context.font = 'bold 15px sans-serif'
      context.textAlign = 'center'
      context.textBaseline = 'middle'
      context.fillText(String(exit), 22, 28)
    }
    await writeFile(resolve(__dirname, `../src/common/maneuver-roundabout${exit ? '-' + exit : ''}.png`), canvas.toBuffer('image/png'))
  }
}
main().catch(error => { console.error(error); process.exitCode = 1 })
