const page = figma.root.children.find(p => p.name === "draft")
await page.loadAsync()
for (const child of [...page.children]) if (child.name === "divisions_gold_shapes") child.remove()
const comp = await figma.getNodeByIdAsync("4580:225487")
const inst = comp.createInstance()
page.appendChild(inst)
inst.x = -38800
inst.y = -15000
const frame = inst.detachInstance()
frame.name = "divisions_gold_shapes"
const tiles = ["bg_i", "stage_bg", "rewards_panel_bg", "play_btn_bg", "reward_cell_card_i", "reward_cell_packs_i", "coins_plate_i", "arrow_left", "arrow_right", "play_icon", "division_lower_glow", "division_upper_glow", "division_current_glow"]
const detached = []
for (const node of frame.findAll(n => n.type === "INSTANCE" && tiles.includes(n.name))) {
  detached.push(node.name)
  const tile = node.detachInstance()
  const used = new Set()
  for (const child of tile.findAll(() => true)) {
    if (child.name.startsWith("{")) continue
    const base = tile.name + "_" + child.name
    let name = base
    for (let i = 2; used.has(name); i += 1) name = base + i
    used.add(name)
    child.name = name
  }
}
const removed = []
for (const node of frame.findAll(n => n.name === "header_container" || n.name === "reward_card")) { removed.push(node.name); node.remove() }
for (const child of [...frame.children]) {
  if (child.name.includes("path_to_screen")) child.name = '{"path_to_screen":"/tests/divisions_gold"}'
  if (child.name.includes("od_promotion_light")) child.remove()
}
for (const node of frame.findAll(n => n.name.includes("need_export"))) node.remove()
return JSON.stringify({ frame: frame.id, detached, removed, meta: frame.children.filter(c => c.name.startsWith("{")).map(c => c.name) })
