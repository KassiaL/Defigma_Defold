// Builds panels_raster and panels_vector on page draft: the my_profile background (3260:43499) with
// the five panel_bg / panel_bg_small instances visible on its first screen, at their positions and
// sizes, and exports both. panels_vector gets {"shape_nodes":true} inside the two panel masters
// for its export only; the markers are always removed before the job returns.
const page = figma.root.children.find(p => p.name === "draft")
await page.loadAsync()
await figma.setCurrentPageAsync(page)
const SCREEN = "3260:43499"
const PANELS = ["profile_info", "account_block", "market_panel", "draft_panel", "sim_scorers"]
const MARKER = '{"shape_nodes":true}'
const screen = await figma.getNodeByIdAsync(SCREEN)
const origin = screen.absoluteTransform
const sources = []
let background = null
const masters = new Map()
for (const node of screen.findAll(n => n.type === "INSTANCE")) {
  const master = await node.getMainComponentAsync()
  if (!master) continue
  if (master.name === "profile_bg") background = { master, node }
  if ((master.name === "panel_bg" || master.name === "panel_bg_small") && PANELS.includes(node.parent.name)) {
    sources.push({ master, node })
    masters.set(master.id, master)
  }
}
for (const old of page.children.filter(c => c.name === "panels_raster" || c.name === "panels_vector")) old.remove()
const meta = (frame, name) => { const r = figma.createRectangle(); frame.appendChild(r); r.name = name; r.resize(8, 8); r.visible = false }
const build = (name, x) => {
  const frame = figma.createFrame()
  page.appendChild(frame)
  frame.name = name
  frame.resize(1080, 2300)
  frame.x = x; frame.y = -12000
  frame.fills = []
  frame.clipsContent = true
  const bg = background.master.createInstance()
  frame.appendChild(bg)
  bg.name = "bg_i"
  bg.x = 0; bg.y = 0
  sources.forEach((s, i) => {
    const instance = s.master.createInstance()
    frame.appendChild(instance)
    instance.name = "panel_" + (i + 1)
    instance.resize(s.node.width, s.node.height)
    instance.x = Math.round(s.node.absoluteTransform[0][2] - origin[0][2])
    instance.y = Math.round(s.node.absoluteTransform[1][2] - origin[1][2])
  })
  meta(frame, '{"path_to_screen":"/tests/panels_screen"}')
  return frame
}
const raster = build("panels_raster", -24000)
const vector = build("panels_vector", -22800)
const files = []
files.push(...await exportNode(raster.id))
const markers = []
try {
  for (const master of masters.values()) {
    const marker = figma.createRectangle()
    master.appendChild(marker)
    marker.name = MARKER
    marker.resize(8, 8)
    marker.visible = false
    markers.push(marker)
  }
  files.push(...await exportNode(vector.id))
} finally {
  for (const marker of markers) if (!marker.removed) marker.remove()
}
const left = [...masters.values()].filter(m => m.children.some(c => c.name === MARKER)).map(m => m.name)
return { files, markers_left: left, panels: sources.map(s => [s.node.parent.name, s.master.name, Math.round(s.node.width), Math.round(s.node.height)]) }
