// Builds the glass_test frame on page draft: a glass tile in the style of the Draft Battle waiting
// panel (glass fill, drop shadow, gradient rim, edge glints, an inner panel and a glowing arc
// spinner) plus the transparent layers tests/glass_test/glass_fx.lua animates, and exports it into
// tests/glass_test.
const page = figma.root.children.find(p => p.name === "draft")
await page.loadAsync()
await figma.setCurrentPageAsync(page)
for (const old of page.children.filter(c => c.name === "glass_test")) old.remove()
const frame = figma.createFrame()
page.appendChild(frame)
frame.name = "glass_test"
frame.resize(1080, 1000)
frame.x = -20400
frame.y = -11000
frame.fills = []
frame.clipsContent = false
const rgba = (r, g, b, a) => ({ r, g, b, a })
const stop = (position, color) => ({ position, color })
const add = (node, name, x, y, w, h) => { frame.appendChild(node); node.name = name; node.x = x; node.y = y; node.resize(w, h); return node }
const TEAL = { r: 0.216, g: 0.953, b: 0.824 }
const ICE = { r: 0.7745, g: 0.9843, b: 1 }

const background = add(figma.createRectangle(), "background", 0, 0, 1080, 1000)
background.fills = [{ type: "GRADIENT_RADIAL", gradientTransform: [[1, 0, 0], [0, 1.4, -0.35]], gradientStops: [
  stop(0, rgba(0.07, 0.24, 0.27, 1)), stop(1, rgba(0.02, 0.06, 0.09, 1))] }]

const glass = add(figma.createRectangle(), "tile_glass", 40, 70, 1000, 860)
glass.cornerRadius = 40
glass.fills = [{ type: "GRADIENT_LINEAR", gradientTransform: [[0, 1, 0], [-1, 0, 1]], gradientStops: [
  stop(0, rgba(0.1, 0.2, 0.25, 0.92)), stop(1, rgba(0.12, 0.34, 0.38, 0.92))] }]
glass.effects = [{ type: "DROP_SHADOW", color: rgba(0, 0, 0, 0.4), offset: { x: 0, y: 14 }, radius: 28, spread: 0, visible: true, blendMode: "NORMAL", showShadowBehindNode: false }]

const panel = add(figma.createRectangle(), "stats_panel", 70, 480, 940, 250)
panel.cornerRadius = 30
panel.fills = [{ type: "SOLID", color: { r: 0.12, g: 0.26, b: 0.3 }, opacity: 0.55 }]
panel.strokes = [{ type: "GRADIENT_LINEAR", gradientTransform: [[1, 0, 0], [0, 1, 0]], gradientStops: [
  stop(0, rgba(ICE.r, ICE.g, ICE.b, 0.5)), stop(0.5, rgba(ICE.r, ICE.g, ICE.b, 0.15)), stop(1, rgba(ICE.r, ICE.g, ICE.b, 0.5))] }]
panel.strokeWeight = 2
panel.strokeAlign = "INSIDE"

const sheen = add(figma.createRectangle(), "glass_sheen", 40, 70, 1000, 860)
sheen.cornerRadius = 40
sheen.fills = [{ type: "SOLID", color: { r: 1, g: 1, b: 1 }, opacity: 0 }]

const rim = add(figma.createRectangle(), "tile_rim", 40, 70, 1000, 860)
rim.cornerRadius = 40
rim.fills = []
rim.strokes = [{ type: "GRADIENT_LINEAR", gradientTransform: [[0, 1, 0], [-1, 0, 1]], gradientStops: [
  stop(0, rgba(ICE.r, ICE.g, ICE.b, 0.12)), stop(0.55, rgba(ICE.r, ICE.g, ICE.b, 0.2)), stop(1, rgba(ICE.r, ICE.g, ICE.b, 1))] }]
rim.strokeWeight = 3
rim.strokeAlign = "INSIDE"

const spinner = add(figma.createEllipse(), "spinner", 470, 130, 140, 140)
spinner.fills = [{ type: "SOLID", color: TEAL }]
spinner.arcData = { startingAngle: -Math.PI / 2, endingAngle: -Math.PI / 2 + 0.45 * 2 * Math.PI, innerRadius: 0.86 }
spinner.cornerRadius = 5
spinner.effects = [{ type: "DROP_SHADOW", color: rgba(TEAL.r, TEAL.g, TEAL.b, 0.8), offset: { x: 0, y: 0 }, radius: 14, spread: 0, visible: true, blendMode: "NORMAL", showShadowBehindNode: false }]

for (let i = 1; i <= 3; i++) {
  const glint = add(figma.createEllipse(), "glint_" + i, 90 + i * 60, 67, 220, 7)
  glint.fills = [{ type: "GRADIENT_RADIAL", gradientTransform: [[1, 0, 0], [0, 1, 0]], gradientStops: [
    stop(0, rgba(ICE.r, ICE.g, ICE.b, 1)), stop(1, rgba(ICE.r, ICE.g, ICE.b, 0))] }]
  glint.effects = [{ type: "LAYER_BLUR", radius: 2, visible: true }]
}
const meta = name => { const r = figma.createRectangle(); frame.appendChild(r); r.name = name; r.resize(8, 8); r.visible = false }
meta('{"path_to_screen":"/tests/glass_test"}')
const files = await exportNode(frame.id)
return { files, frame: frame.id }
