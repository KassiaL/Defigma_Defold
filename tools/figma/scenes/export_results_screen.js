// Exports the four results screen variants built by build_results_screen.js. Atlas instances
// export as images, so results_vector and results_bg_raster detach the instances of the panel
// masters (and of the background for results_vector) inside their own copies: the masters
// themselves are never touched.
const page = figma.root.children.find(p => p.name === "draft")
await page.loadAsync()
const FRAMES = {}
for (const child of page.children) {
  if (child.name.startsWith("results_")) FRAMES[child.name] = child
  if (child.name === "/tests/results_screen/results_extra.atlas") FRAMES.section = child
}
const BACKGROUND = "4575:154592"
const MASTERS = ["4575:231002", "4575:231011", "4601:225273", "4601:225282", "4601:225291", "4601:223073", "4601:223078",
  "4601:223083", "4601:223088", "4601:223096", "4601:223098", "4601:223100", "4601:223102", "4601:223104", "4601:223093", "4547:232876"]

const detachAll = async (frame, masterIds) => {
  for (;;) {
    let detached = 0
    for (const instance of frame.findAll(n => n.type === "INSTANCE")) {
      const master = await instance.getMainComponentAsync()
      if (master && masterIds.includes(master.id)) { instance.detachInstance(); detached++ }
    }
    if (detached === 0) return
  }
}

await detachAll(FRAMES.results_vector, [BACKGROUND, ...MASTERS])
await detachAll(FRAMES.results_bg_raster, MASTERS)
const files = []
for (const name of ["results_vector", "results_bg_raster", "results_current", "results_raster"]) files.push(...await exportNode(FRAMES[name].id))
files.push(...await exportNode(FRAMES.section.id))
return { files }
