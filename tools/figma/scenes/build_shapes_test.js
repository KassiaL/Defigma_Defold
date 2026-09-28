const page = figma.root.children.find(p => p.name === "draft")
await page.loadAsync()
for (const child of [...page.children]) if (child.name === "shapes_test") child.remove()

const frame = figma.createFrame()
page.appendChild(frame)
frame.name = "shapes_test"
frame.resize(1080, 1000)
frame.x = -40000; frame.y = -15000
frame.fills = []
frame.clipsContent = true

const solid = (hex, a = 1) => { const n = parseInt(hex.slice(1), 16); return { type: "SOLID", color: { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255 }, opacity: a } }
const rgba = (hex, a) => { const n = parseInt(hex.slice(1), 16); return { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255, a } }
const meta = (text) => { const r = figma.createRectangle(); r.name = text; r.resize(8, 8); r.fills = [solid("#ff0000")]; r.visible = false; frame.appendChild(r); return r }

const bg = figma.createRectangle(); frame.appendChild(bg); bg.name = "bg"; bg.resize(1080, 1000); bg.fills = [solid("#0a0a0c")]

const rect = (name, x, y, w, h, fills, extra = {}) => { const r = figma.createRectangle(); frame.appendChild(r); r.name = name; r.x = x; r.y = y; r.resize(w, h); r.fills = fills; Object.assign(r, extra); return r }
const ellipse = (name, x, y, w, h, fills, extra = {}) => { const r = figma.createEllipse(); frame.appendChild(r); r.name = name; r.x = x; r.y = y; r.resize(w, h); r.fills = fills; Object.assign(r, extra); return r }
const shadow = (x, y, radius, color, spread = 0) => ({ type: "DROP_SHADOW", visible: true, radius, color, offset: { x, y }, spread, blendMode: "NORMAL", showShadowBehindNode: false })

rect("opaque_shadow", 40, 40, 200, 120, [solid("#3a3a48")], { cornerRadius: 24, effects: [shadow(0, 14, 28, rgba("#000000", 0.9))] })
rect("alpha_shadow", 290, 40, 200, 120, [solid("#3a3a48", 0.3)], { cornerRadius: 24, effects: [shadow(0, 14, 28, rgba("#000000", 0.9))] })
rect("light_on_dark_shadow", 540, 40, 200, 120, [solid("#1a1a20")], { cornerRadius: 0, effects: [shadow(10, 10, 20, rgba("#d4af37", 1), 6)] })
rect("multi_stop", 790, 40, 250, 120, [{ type: "GRADIENT_LINEAR", gradientTransform: [[0.8, 0.3, 0], [-0.3, 0.8, 0.2]], gradientStops: [
  { position: 0, color: rgba("#2e7bff", 1) }, { position: 0.3, color: rgba("#ffffff", 1) }, { position: 0.6, color: rgba("#ff3e3e", 0.5) }, { position: 1, color: rgba("#d4af37", 1) }] }],
  { topLeftRadius: 50, topRightRadius: 8, bottomRightRadius: 0, bottomLeftRadius: 30 })

const src = async (id) => await figma.getNodeByIdAsync(id)
const cloneTo = async (id, x, y) => { const n = (await src(id)).clone(); frame.appendChild(n); n.x = x; n.y = y; return n }

const stage = (await src("4570:282274"))
const tile = await cloneTo("4570:282274", 20, 200)
const detached = tile.detachInstance()
detached.name = "stage_bg"

await cloneTo("4570:282375", 40, 900)
const fill = await cloneTo("4570:282376", 40, 900)
fill.name = "bar_fill"
ellipse("avatar_ring", 940, 860, 120, 120, [solid("#07070a")], { strokes: [solid("#e8c65a")], strokeWeight: 4, strokeAlign: "INSIDE", effects: [shadow(0, 4, 14, rgba("#000000", 0.6))] })

const chevron = (await src("I4570:282200;4570:282127")).clone(); frame.appendChild(chevron); chevron.name = "chevron"; chevron.x = 560; chevron.y = 820
const core = (await src("I4570:282200;4570:282129")).clone(); frame.appendChild(core); core.name = "chevron_core"; core.x = 680; core.y = 880
const glow = (await src("I4570:282200;4570:282116")).clone(); frame.appendChild(glow); glow.name = "glow"; glow.resize(520, 420); glow.x = 700; glow.y = 380

ellipse("ellipse_linear", 420, 880, 160, 90, [{ type: "GRADIENT_LINEAR", gradientTransform: [[1, 0, 0], [0, 1, 0]], gradientStops: [{ position: 0, color: rgba("#b8912a", 1) }, { position: 1, color: rgba("#f6dc8a", 1) }] }],
  { strokes: [solid("#fff2c4")], strokeWeight: 6, strokeAlign: "OUTSIDE" })
rect("center_stroke", 250, 880, 140, 80, [solid("#120e05")], { cornerRadius: 16, strokes: [solid("#e8c65a", 0.8)], strokeWeight: 8, strokeAlign: "CENTER" })

meta('{"path_to_screen":"/tests/shapes_test"}')
meta('{"shape_nodes":true}')
return JSON.stringify({ page: page.id, frame: frame.id, kids: frame.children.map(c => c.name) })
