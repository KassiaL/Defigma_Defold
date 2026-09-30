// Builds the arcs_fx_test frame on page draft (Figma arcs with drop shadows, strokes of every
// alignment and layer blur) and exports it as shape nodes into tests/arcs_fx_test.
const page = figma.root.children.find(p => p.name === "draft")
await page.loadAsync()
await figma.setCurrentPageAsync(page)
for (const old of page.children.filter(c => c.name === "arcs_fx_test")) old.remove()
const frame = figma.createFrame()
page.appendChild(frame)
frame.name = "arcs_fx_test"
frame.resize(1000, 760)
frame.x = -21600
frame.y = -11000
frame.fills = []
const background = figma.createRectangle()
frame.appendChild(background)
background.name = "background"
background.resize(1000, 760)
background.fills = [{ type: "SOLID", color: { r: 0.09, g: 0.13, b: 0.17 } }]
const DEG = Math.PI / 180
const solid = (r, g, b, opacity = 1) => [{ type: "SOLID", color: { r, g, b }, opacity }]
const linear = [{ type: "GRADIENT_LINEAR", gradientTransform: [[1, 0, 0], [0, 1, 0]], gradientStops: [
  { position: 0, color: { r: 0.2, g: 0.95, b: 0.8, a: 1 } }, { position: 1, color: { r: 0.3, g: 0.3, b: 1, a: 1 } }] }]
const shadow = (x, y, radius, spread, r, g, b, a) => ({ type: "DROP_SHADOW", color: { r, g, b, a }, offset: { x, y }, radius, spread, visible: true, blendMode: "NORMAL", showShadowBehindNode: false })
const blur = radius => ({ type: "LAYER_BLUR", radius, visible: true })
const TEAL = [0.216, 0.953, 0.824]
const arcs = [
  { name: "glow", x: 40, y: 40, w: 170, h: 170, start: -90, sweep: 45, ratio: 0.86, corner: 5, fills: solid(...TEAL), effects: [shadow(0, 0, 14, 0, ...TEAL, 0.8)] },
  { name: "shadow_offset", x: 270, y: 40, w: 170, h: 170, start: 45, sweep: 60, ratio: 0.5, corner: 8, fills: solid(0.6, 0.5, 1), effects: [shadow(6, 10, 12, 0, 0, 0, 0, 0.6)] },
  { name: "shadow_spread", x: 500, y: 40, w: 170, h: 170, start: -90, sweep: 72, ratio: 0.8, corner: 0, fills: solid(1, 0.6, 0.2), effects: [shadow(0, 0, 8, 6, 1, 1, 1, 0.5)] },
  { name: "pie_shadow", x: 730, y: 40, w: 170, h: 170, start: 10, sweep: 30, ratio: 0, corner: 12, fills: solid(1, 0.6, 0.2), effects: [shadow(0, 6, 10, 0, 0, 0, 0, 0.7)] },
  { name: "stroke_inside", x: 40, y: 280, w: 170, h: 170, start: -90, sweep: 70, ratio: 0.6, corner: 20, fills: solid(0.2, 0.5, 0.9), strokes: solid(1, 1, 1), weight: 6, align: "INSIDE" },
  { name: "stroke_center", x: 270, y: 280, w: 170, h: 170, start: 120, sweep: 80, ratio: 0.7, corner: 0, fills: solid(0.15, 0.2, 0.3), strokes: linear, weight: 4, align: "CENTER" },
  { name: "stroke_outside", x: 500, y: 280, w: 170, h: 170, start: 0, sweep: 55, ratio: 0.5, corner: 10, fills: solid(0.9, 0.2, 0.4), strokes: solid(1, 0.8, 0.2), weight: 5, align: "OUTSIDE" },
  { name: "blur_arc", x: 730, y: 280, w: 170, h: 170, start: -150, sweep: 60, ratio: 0.8, corner: 85, fills: solid(0.78, 0.98, 1), effects: [blur(8)] },
  { name: "ellipse_fx", x: 40, y: 520, w: 300, h: 170, start: 30, sweep: 60, ratio: 0.6, corner: 10, fills: linear, strokes: solid(1, 1, 1), weight: 3, align: "CENTER", effects: [shadow(0, 8, 10, 0, 0, 0, 0, 0.5)] },
  { name: "translucent", x: 400, y: 510, w: 200, h: 200, start: 180, sweep: 50, ratio: 0.3, corner: 30, fills: solid(0.2, 0.8, 1, 0.5), effects: [shadow(0, 0, 12, 0, 0.2, 0.8, 1, 0.6)] },
  { name: "full_ring", x: 700, y: 510, w: 200, h: 200, start: 0, sweep: 100, ratio: 0.7, corner: 0, fills: solid(0.95, 0.95, 0.95), strokes: solid(0.2, 0.9, 0.6), weight: 3, align: "OUTSIDE", effects: [shadow(0, 0, 16, 0, 0, 0, 0, 0.8)] },
]
for (const a of arcs) {
  const e = figma.createEllipse()
  frame.appendChild(e)
  e.name = a.name
  e.x = a.x; e.y = a.y
  e.resize(a.w, a.h)
  e.fills = a.fills
  e.arcData = { startingAngle: a.start * DEG, endingAngle: (a.start + a.sweep * 3.6) * DEG, innerRadius: a.ratio }
  e.cornerRadius = a.corner
  if (a.strokes) { e.strokes = a.strokes; e.strokeWeight = a.weight; e.strokeAlign = a.align }
  if (a.effects) e.effects = a.effects
}
const meta = name => { const r = figma.createRectangle(); frame.appendChild(r); r.name = name; r.resize(8, 8); r.visible = false }
meta('{"path_to_screen":"/tests/arcs_fx_test"}')
const files = await exportNode(frame.id)
return { files, frame: frame.id }
