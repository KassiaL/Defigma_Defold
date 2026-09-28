// Builds the results screen test frames on the page "draft" from the component
// "Property 1=emerald" (4575:231281): results_raster, results_current, results_bg_raster,
// results_vector, plus the atlas section with the native shapes of results_raster.
// Template instances are detached so every variant is one .gui. Idempotent.
const SOURCE = "4575:231281"
const SECTION = "/tests/results_screen/results_extra.atlas"
const FRAMES = ["results_raster", "results_current", "results_bg_raster", "results_vector"]
const page = figma.root.children.find(p => p.name === "draft")
await page.loadAsync()
for (const child of [...page.children]) if (FRAMES.includes(child.name) || child.name === SECTION) child.remove()

const metadataOf = (node) => { try { return node.name.startsWith("{") ? JSON.parse(node.name) : null } catch (e) { return null } }
const isTemplateMaster = (component) => component.children.some(c => metadataOf(c)?.is_template === true)
const insideSection = (node) => { for (let p = node.parent; p; p = p.parent) if (p.type === "SECTION") return true; return false }

async function detachTemplates(root) {
  for (;;) {
    let detached = false
    for (const instance of root.findAll(n => n.type === "INSTANCE")) {
      const main = await instance.getMainComponentAsync()
      if (!main || !isTemplateMaster(main)) continue
      const frame = instance.detachInstance()
      for (const child of [...frame.children]) {
        const meta = metadataOf(child)
        if (meta && ("is_template" in meta || "path_to_screen" in meta)) child.remove()
      }
      detached = true
      break
    }
    if (!detached) return
  }
}

async function makeCopy(name, x) {
  const component = await figma.getNodeByIdAsync(SOURCE)
  const instance = component.createInstance()
  page.appendChild(instance)
  instance.x = x; instance.y = -12000
  const frame = instance.detachInstance()
  frame.name = name
  await detachTemplates(frame)
  for (const node of frame.findAll(n => n.locked)) node.locked = false
  for (const node of frame.findAll(n => n.name === '{"need_export":["searching"]}')) node.remove()
  for (const child of [...frame.children]) {
    const meta = metadataOf(child)
    if (meta && "path_to_screen" in meta) child.name = '{"path_to_screen":"/tests/results_screen"}'
  }
  const meta = (value) => { const r = figma.createRectangle(); frame.appendChild(r); r.name = value; r.resize(8, 8); r.visible = false }
  meta('{"allow_identical_names":["*"]}')
  if (name !== "results_raster") meta('{"shape_nodes":true}')
  return frame
}

async function nativeShapes(root) {
  const found = []
  const walk = async (node) => {
    if (metadataOf(node)) return
    if (node.type === "INSTANCE") {
      const main = await node.getMainComponentAsync()
      if (main && insideSection(main)) return
    }
    if (["RECTANGLE", "ELLIPSE", "VECTOR", "STAR", "POLYGON", "BOOLEAN_OPERATION"].includes(node.type)) {
      const hasImage = Array.isArray(node.fills) && node.fills.some(f => f.type === "IMAGE")
      if (!hasImage) found.push(node)
      return
    }
    if ("children" in node) for (const child of node.children) await walk(child)
  }
  await walk(root)
  return found
}

function signature(node) {
  const pick = (n) => JSON.stringify([n.type, Math.round(n.width * 100), Math.round(n.height * 100), n.fills, n.strokes, n.strokeWeight, n.strokeAlign, n.effects,
    n.type === "RECTANGLE" ? [n.topLeftRadius, n.topRightRadius, n.bottomRightRadius, n.bottomLeftRadius] : 0, "vectorPaths" in n ? n.vectorPaths : 0, n.rotation, n.opacity])
  return pick(node)
}

const frames = {}
let x = -27000
for (const name of FRAMES) { frames[name] = await makeCopy(name, x); x += 1200 }

const section = figma.createSection()
page.appendChild(section)
section.name = SECTION
section.x = -27000; section.y = -9000
section.resizeWithoutConstraints(3000, 1200)
const components = new Map()
let cx = 50, cy = 50, rowHeight = 0
const raster = frames["results_raster"]
for (const node of await nativeShapes(raster)) {
  const key = signature(node)
  const bounds = node.absoluteRenderBounds || node.absoluteBoundingBox
  const box = node.absoluteBoundingBox
  const padLeft = Math.ceil(box.x - bounds.x), padTop = Math.ceil(box.y - bounds.y)
  const padRight = Math.ceil(bounds.x + bounds.width - box.x - box.width), padBottom = Math.ceil(bounds.y + bounds.height - box.y - box.height)
  let entry = components.get(key)
  if (!entry) {
    const component = figma.createComponent()
    section.appendChild(component)
    component.name = "extra_" + components.size
    component.fills = []
    component.clipsContent = true
    component.resize(Math.max(1, box.width + padLeft + padRight), Math.max(1, box.height + padTop + padBottom))
    if (cx + component.width > 2900) { cx = 50; cy += rowHeight + 40; rowHeight = 0 }
    component.x = cx; component.y = cy
    cx += component.width + 40; rowHeight = Math.max(rowHeight, component.height)
    const clone = node.clone()
    component.appendChild(clone)
    clone.x = padLeft; clone.y = padTop
    entry = { component, padLeft, padTop }
    components.set(key, entry)
  }
  const parent = node.parent
  const index = parent.children.indexOf(node)
  const instance = entry.component.createInstance()
  parent.insertChild(index, instance)
  instance.name = node.name
  instance.x = node.x - entry.padLeft
  instance.y = node.y - entry.padTop
  instance.visible = node.visible
  node.remove()
}
section.resizeWithoutConstraints(3000, cy + rowHeight + 100)
const result = { section: section.id, extra_components: components.size }
for (const name of FRAMES) result[name] = frames[name].id
return JSON.stringify(result)
