// Builds the arcs_test frame on page draft (Figma arcs with every parameter combination the shape
// node supports) and exports it as shape nodes into tests/arcs_test.
const page = figma.root.children.find(p => p.name === "draft")
await page.loadAsync()
await figma.setCurrentPageAsync(page)
for (const old of page.children.filter(c => c.name === "arcs_test")) old.remove()
const frame = figma.createFrame()
page.appendChild(frame)
frame.name = "arcs_test"
frame.resize(1000, 760)
frame.x = -21600
frame.y = -12000
frame.fills = [{ type: "SOLID", color: { r: 0, g: 0, b: 0 } }]
const DEG = Math.PI / 180
const solid = (r, g, b) => [{ type: "SOLID", color: { r, g, b } }]
const linear = [{ type: "GRADIENT_LINEAR", gradientTransform: [[1, 0, 0], [0, 1, 0]], gradientStops: [
  { position: 0, color: { r: 0.2, g: 0.95, b: 0.8, a: 1 } }, { position: 1, color: { r: 0.3, g: 0.3, b: 1, a: 1 } }] }]
const radial = [{ type: "GRADIENT_RADIAL", gradientTransform: [[1, 0, 0], [0, 1, 0]], gradientStops: [
  { position: 0, color: { r: 1, g: 0.9, b: 0.3, a: 1 } }, { position: 1, color: { r: 0.9, g: 0.2, b: 0.4, a: 1 } }] }]
const arcs = [
  ["ring_round", 40, 40, 170, 170, -90, 72, 0.865, 85, solid(0.216, 0.953, 0.824)],
  ["ring_square", 250, 40, 170, 170, -90, 72, 0.865, 0, solid(0.216, 0.953, 0.824)],
  ["pie", 460, 40, 170, 170, 10, 30, 0, 0, solid(1, 0.6, 0.2)],
  ["pie_round", 670, 40, 170, 170, 10, 30, 0, 12, solid(1, 0.6, 0.2)],
  ["donut", 40, 260, 170, 170, 0, 100, 0.5, 0, linear],
  ["thick_partial", 250, 260, 170, 170, 45, 60, 0.5, 8, solid(0.6, 0.5, 1)],
  ["tiny_sweep", 460, 260, 170, 170, -90, 3, 0.8, 85, solid(0.216, 0.953, 0.824)],
  ["wide_sweep", 670, 260, 170, 170, 120, 95, 0.7, 85, linear],
  ["ellipse_arc", 40, 480, 300, 170, 30, 60, 0.6, 10, radial],
  ["big_ring", 380, 480, 250, 250, 200, 45, 0.9, 85, solid(0.95, 0.95, 0.95)],
  ["half_translucent", 700, 480, 250, 250, 180, 50, 0.3, 30, [{ type: "SOLID", color: { r: 0.2, g: 0.8, b: 1 }, opacity: 0.5 }]],
]
for (const [name, x, y, w, h, start, sweep, ratio, corner, fills] of arcs) {
  const e = figma.createEllipse()
  frame.appendChild(e)
  e.name = name
  e.x = x; e.y = y
  e.resize(w, h)
  e.fills = fills
  e.arcData = { startingAngle: start * DEG, endingAngle: (start + sweep * 3.6) * DEG, innerRadius: ratio }
  e.cornerRadius = corner
}
const meta = name => { const r = figma.createRectangle(); frame.appendChild(r); r.name = name; r.resize(8, 8); r.visible = false }
meta('{"path_to_screen":"/tests/arcs_test"}')
meta('{"shape_nodes":true}')
const files = await exportNode(frame.id)
return { files, frame: frame.id }
