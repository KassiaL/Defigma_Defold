const page = figma.root.children.find(p => p.name === "draft")
await page.loadAsync()
const NAMES = ["bench_atlas", "bench_vector", "bench_material", "bench_raster"]
for (const child of [...page.children]) if (NAMES.includes(child.name) || child.name === "/tests/bench_screen/bench_raster.atlas") child.remove()

await figma.loadFontAsync({ family: "DIN Pro", style: "Condensed Black Italic" })
await figma.loadFontAsync({ family: "DIN Pro", style: "Condensed Bold Italic" })

const hex = (h, a = 1) => { const n = parseInt(h.slice(1), 16); return { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255, a } }
const solid = (h, a = 1) => { const c = hex(h); return { type: "SOLID", color: { r: c.r, g: c.g, b: c.b }, opacity: a } }
const linear = (stops, t = [[0, 1, 0], [-1, 0, 1]]) => ({ type: "GRADIENT_LINEAR", gradientTransform: t, gradientStops: stops.map(([p, h, a]) => ({ position: p, color: hex(h, a) })) })
const radial = (stops) => ({ type: "GRADIENT_RADIAL", gradientTransform: [[1, 0, 0], [0, 1, 0]], gradientStops: stops.map(([p, h, a]) => ({ position: p, color: hex(h, a) })) })
const shadow = (x, y, r, h, a) => ({ type: "DROP_SHADOW", visible: true, radius: r, color: hex(h, a), offset: { x, y }, spread: 0, blendMode: "NORMAL", showShadowBehindNode: false })
const blur = (r) => ({ type: "LAYER_BLUR", visible: true, radius: r })

const add = (parent, node, name, x, y, w, h, props = {}) => { parent.appendChild(node); node.name = name; node.x = x; node.y = y; node.resize(w, h); Object.assign(node, props); return node }
const rect = (parent, name, x, y, w, h, props) => add(parent, figma.createRectangle(), name, x, y, w, h, props)
const ellipse = (parent, name, x, y, w, h, props) => add(parent, figma.createEllipse(), name, x, y, w, h, props)
const frame = (parent, name, x, y, w, h, props) => add(parent, figma.createFrame(), name, x, y, w, h, Object.assign({ fills: [], clipsContent: false }, props))
const polygon = (parent, name, points, fills) => {
  const v = figma.createVector(); parent.appendChild(v); v.name = name
  v.vectorPaths = [{ windingRule: "NONZERO", data: "M " + points.map(p => p.join(" ")).join(" L ") + " Z" }]
  v.fills = fills; v.strokes = []; return v
}
const text = (parent, name, x, y, w, h, value, size, style, color, align, effects = []) => {
  const t = figma.createText(); parent.appendChild(t); t.name = name
  t.fontName = { family: "DIN Pro", style }; t.characters = value; t.fontSize = size
  t.textAlignHorizontal = align; t.textAutoResize = "NONE"; t.resize(w, h); t.x = x; t.y = y
  t.fills = [solid(color)]; t.effects = effects; return t
}

const section = figma.createSection()
page.appendChild(section)
section.name = "/tests/bench_screen/bench_raster.atlas"
section.x = -36000; section.y = -15000
section.resizeWithoutConstraints(4200, 2500)

const component = (name, x, w, h) => { const c = figma.createComponent(); section.appendChild(c); c.name = name; c.x = x; c.y = 100; c.resize(w, h); c.fills = []; c.clipsContent = true; return c }

const bg = component("bench_bg", 100, 1080, 2300)
rect(bg, "base", 0, 0, 1080, 2300, { fills: [linear([[0, "#141026", 1], [0.55, "#0b0a17", 1], [1, "#06060c", 1]])] })
ellipse(bg, "glow_top", -60, -200, 1200, 900, { fills: [radial([[0, "#37f3d2", 0.28], [1, "#37f3d2", 0]])], effects: [blur(120)] })
ellipse(bg, "glow_bottom", 400, 1700, 1000, 800, { fills: [radial([[0, "#8c3cff", 0.3], [1, "#8c3cff", 0]])], effects: [blur(110)] })
polygon(bg, "facet_a", [[0, 300], [620, 0], [380, 900]], [linear([[0, "#ffffff", 0.07], [1, "#ffffff", 0]])])
polygon(bg, "facet_b", [[1080, 700], [540, 1400], [1080, 1900]], [linear([[0, "#ffffff", 0.05], [1, "#ffffff", 0]])])
polygon(bg, "facet_c", [[0, 1500], [700, 2300], [0, 2300]], [linear([[0, "#000000", 0.25], [1, "#000000", 0]])])
rect(bg, "vignette", 0, 0, 1080, 2300, { fills: [radial([[0.5, "#000000", 0], [1, "#000000", 0.5]])] })

const header = component("bench_header", 1300, 1080, 260)
rect(header, "panel", 24, 24, 1032, 212, { cornerRadius: 36, fills: [linear([[0, "#2a2350", 1], [1, "#17142e", 1]])],
  strokes: [linear([[0, "#6f5cff", 0.25], [1, "#37f3d2", 0.9]], [[1, 0, 0], [0, 1, 0]])], strokeWeight: 3, strokeAlign: "INSIDE", effects: [shadow(0, 12, 24, "#000000", 0.5)] })
ellipse(header, "panel_glint", 120, 22, 400, 6, { fills: [radial([[0, "#ffffff", 0.9], [1, "#ffffff", 0]])], effects: [blur(2)] })

const card = component("bench_card", 2500, 340, 420)
const body = frame(card, "body", 30, 30, 280, 360, { cornerRadius: 28, clipsContent: true, effects: [shadow(0, 14, 28, "#000000", 0.55)] })
rect(body, "fill", 0, 0, 280, 360, { fills: [linear([[0, "#2c2552", 1], [0.6, "#1d1939", 1], [1, "#141129", 1]])] })
ellipse(body, "glow", 10, -60, 260, 220, { fills: [radial([[0, "#37f3d2", 0.35], [1, "#37f3d2", 0]])] })
polygon(body, "shine", [[40, 0], [150, 0], [0, 200], [0, 60]], [linear([[0, "#ffffff", 0.14], [1, "#ffffff", 0]])])
ellipse(body, "icon", 80, 80, 120, 120, { fills: [radial([[0, "#ffffff", 0.95], [0.6, "#b7a8ff", 0.7], [1, "#6f5cff", 0.3]])], strokes: [solid("#ffffff", 0.35)], strokeWeight: 2, strokeAlign: "OUTSIDE" })
ellipse(body, "badge", 200, 16, 64, 64, { fills: [solid("#1b1733")], strokes: [solid("#37f3d2")], strokeWeight: 3, strokeAlign: "INSIDE" })
rect(body, "plate", 30, 284, 220, 56, { cornerRadius: 28, fills: [linear([[0, "#37f3d2", 1], [1, "#20b39a", 1]], [[1, 0, 0], [0, 1, 0]])], effects: [shadow(0, 6, 12, "#37f3d2", 0.4)] })
rect(card, "rim", 30, 30, 280, 360, { cornerRadius: 28, fills: [], strokes: [linear([[0, "#8b7dff", 0.15], [1, "#37f3d2", 0.8]])], strokeWeight: 3, strokeAlign: "INSIDE" })

const button = component("bench_button", 3000, 860, 220)
rect(button, "base", 30, 30, 800, 160, { cornerRadius: 80, fills: [linear([[0, "#fff2c4", 1], [0.45, "#f6dc8a", 1], [1, "#b8912a", 1]])],
  strokes: [solid("#fff2c4")], strokeWeight: 3, strokeAlign: "INSIDE", effects: [shadow(0, 16, 30, "#000000", 0.5)] })
ellipse(button, "gloss", 80, 36, 700, 60, { fills: [radial([[0, "#ffffff", 0.45], [1, "#ffffff", 0]])] })

const variants = [["bench_vector", -33500, false], ["bench_material", -32300, false], ["bench_raster", -31100, true]]
const result = {}
for (const [name, x, raster] of variants) {
  const screen = figma.createFrame(); page.appendChild(screen); screen.name = name; screen.x = x; screen.y = -15000; screen.resize(1080, 2300); screen.fills = [solid("#06060c")]; screen.clipsContent = true
  const place = (source, holder, px, py, prefix) => {
    const inst = source.createInstance(); holder.appendChild(inst); inst.x = px; inst.y = py
    if (raster) { inst.name = prefix; return inst }
    const f = inst.detachInstance(); f.name = prefix
    const used = new Set()
    for (const child of f.findAll(() => true)) { let n = prefix + "_" + child.name; for (let i = 2; used.has(n); i++) n = prefix + "_" + child.name + i; used.add(n); child.name = n }
    return f
  }
  place(bg, screen, 0, 0, "bg")
  const top = frame(screen, "top", 0, 120, 1080, 260)
  place(header, top, 0, 0, "header")
  text(top, "title", 80, 70, 600, 80, "PACK STORE", 64, "Condensed Black Italic", "#f3e9d2", "LEFT", [shadow(0, 4, 8, "#000000", 0.6)])
  text(top, "coins", 640, 88, 360, 60, "125 000", 48, "Condensed Black Italic", "#37f3d2", "RIGHT")
  for (let i = 0; i < 9; i++) {
    const cx = 20 + (i % 3) * 346, cy = 420 + Math.floor(i / 3) * 440
    const slot = frame(screen, "slot" + i, cx, cy, 340, 420)
    place(card, slot, 0, 0, "card" + i)
    text(slot, "name" + i, 50, 250, 240, 40, "PACK " + (i + 1), 30, "Condensed Bold Italic", "#f3e9d2", "CENTER")
    text(slot, "price" + i, 60, 318, 220, 50, (1000 + i * 250) + "", 36, "Condensed Black Italic", "#0b0a17", "CENTER")
  }
  const bottom = frame(screen, "bottom", 110, 1760, 860, 220)
  place(button, bottom, 0, 0, "button")
  text(bottom, "buy", 30, 70, 800, 90, "BUY ALL", 72, "Condensed Black Italic", "#120e05", "CENTER")
  const meta = (value) => { const r = figma.createRectangle(); screen.appendChild(r); r.name = value; r.resize(8, 8); r.visible = false }
  meta('{"path_to_screen":"/tests/bench_screen"}')
  meta('{"max_nodes":1024}')
  if (name === "bench_vector") meta('{"shape_nodes":true}')
  result[name] = screen.id
}
result.section = section.id
return JSON.stringify(result)
