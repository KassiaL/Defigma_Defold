// Exports the four results screen variants built by build_results_screen.js.
// results_vector and results_bg_raster need {"shape_nodes":true} inside the atlas masters: the
// markers are added here and always removed before the job returns, so the masters end up exactly
// as they were.
const page = figma.root.children.find(p => p.name === "draft")
await page.loadAsync()
const FRAMES = {}
for (const child of page.children) {
  if (child.name.startsWith("results_")) FRAMES[child.name] = child.id
  if (child.name === "/tests/results_screen/results_extra.atlas") FRAMES.section = child.id
}
const BACKGROUND = "4575:154592"
const MASTERS = ["4575:231002", "4575:231011", "4601:225273", "4601:225282", "4601:225291", "4601:223073", "4601:223078",
  "4601:223083", "4601:223088", "4601:223096", "4601:223098", "4601:223100", "4601:223102", "4601:223104", "4601:223093", "4547:232876"]
const MARKER = '{"shape_nodes":true}'

const markers = new Map()
const addMarker = async (id) => {
  const master = await figma.getNodeByIdAsync(id)
  const marker = figma.createRectangle()
  master.appendChild(marker)
  marker.name = MARKER
  marker.resize(8, 8)
  marker.visible = false
  markers.set(id, marker)
}
const removeMarker = (id) => { const marker = markers.get(id); if (marker && !marker.removed) marker.remove(); markers.delete(id) }

const files = []
try {
  for (const id of [BACKGROUND, ...MASTERS]) await addMarker(id)
  files.push(...await exportNode(FRAMES.results_vector))
  removeMarker(BACKGROUND)
  files.push(...await exportNode(FRAMES.results_bg_raster))
} finally {
  for (const id of [...markers.keys()]) removeMarker(id)
}
const left = []
for (const id of [BACKGROUND, ...MASTERS]) {
  const master = await figma.getNodeByIdAsync(id)
  if (master.children.some(c => c.name === MARKER)) left.push(master.name)
}
files.push(...await exportNode(FRAMES.results_current))
files.push(...await exportNode(FRAMES.results_raster))
files.push(...await exportNode(FRAMES.section))
return { files, markers_left: left }
