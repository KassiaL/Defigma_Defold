"""Count what a Figma screen is made of, to decide which parts to export as vector shapes.

    python3 tools/figma/screen_census.py <node_id> [<node_id> ...] [--shots <dir>]

For every screen prints the atlas instances (masters inside a section) with their area share,
how many of them are stretched away from the master size (slice9 or vector candidates) and what
their masters contain (effects with radius, gradients, bitmaps, paths, blend modes), plus the same
for the nodes drawn directly on the screen. `--shots` also saves a PNG of every screen.
"""
import json
import os
import subprocess
import sys
import tempfile

BRIDGE = os.environ.get("FIGMA_BRIDGE", os.path.expanduser("~/figma_plugins/FigmaBridge"))
PORT = os.environ.get("BRIDGE_PORT", "8788")

SCRIPT = r"""
const ids = __IDS__
const inSection = n => { for (let c = n; c; c = c.parent) if (c.type === "SECTION") return true; return false }
const sectionName = n => { for (let c = n; c; c = c.parent) if (c.type === "SECTION") return c.name; return "" }
const visible = n => n.visible !== false
const paints = p => (p === figma.mixed || !p) ? [] : p.filter(x => x.visible !== false)
function describe(root, stats) {
  const walk = n => {
    if (!visible(n)) return
    if (n.isMask) stats.masks++
    for (const e of (n.effects || [])) if (e.visible !== false) {
      const key = e.type.toLowerCase()
      const r = Math.round(e.radius || 0)
      stats.effects[key] = (stats.effects[key] || 0) + 1
      stats.max_radius = Math.max(stats.max_radius, r)
      stats.effect_area += Math.round(n.width * n.height)
    }
    for (const p of paints(n.fills).concat(paints(n.strokes))) {
      if (p.type === "IMAGE") stats.bitmaps++
      else if (p.type.startsWith("GRADIENT_")) stats[p.type.slice(9).toLowerCase()] = (stats[p.type.slice(9).toLowerCase()] || 0) + 1
    }
    if (n.blendMode && !["NORMAL", "PASS_THROUGH"].includes(n.blendMode)) stats.blend++
    if (["VECTOR", "BOOLEAN_OPERATION", "STAR", "POLYGON", "LINE"].includes(n.type)) stats.paths++
    if (n.type === "TEXT") { stats.texts++; if ((n.effects || []).some(e => e.visible !== false)) stats.text_effects++ }
    if ("children" in n && n.type !== "BOOLEAN_OPERATION") for (const c of n.children) walk(c)
  }
  walk(root)
  return stats
}
const empty = () => ({ effects: {}, max_radius: 0, effect_area: 0, bitmaps: 0, blend: 0, paths: 0, masks: 0, texts: 0, text_effects: 0 })
const out = []
for (const id of ids) {
  const screen = await figma.getNodeByIdAsync(id)
  const area = screen.width * screen.height
  const atlas = {}
  const direct = empty()
  let atlasArea = 0
  const walk = async n => {
    if (!visible(n)) return
    if (n.type === "INSTANCE") {
      const main = await n.getMainComponentAsync()
      if (main && inSection(main)) {
        const key = main.id
        const a = atlas[key] || (atlas[key] = { name: (main.parent && main.parent.type === "COMPONENT_SET" ? main.parent.name + "/" : "") + main.name, section: sectionName(main), count: 0, stretched: 0, area: 0, size: [Math.round(main.width), Math.round(main.height)], content: describe(main, empty()) })
        a.count++
        a.area += Math.round(n.width * n.height)
        atlasArea += n.width * n.height
        if (Math.abs(n.width - main.width) > 1 || Math.abs(n.height - main.height) > 1) a.stretched++
        return
      }
    }
    if (n !== screen) {
      for (const e of (n.effects || [])) if (e.visible !== false) { const k = e.type.toLowerCase(); direct.effects[k] = (direct.effects[k] || 0) + 1; direct.max_radius = Math.max(direct.max_radius, Math.round(e.radius || 0)); direct.effect_area += Math.round(n.width * n.height) }
      for (const p of paints(n.fills).concat(paints(n.strokes))) {
        if (p.type === "IMAGE") direct.bitmaps++
        else if (p.type.startsWith("GRADIENT_")) direct[p.type.slice(9).toLowerCase()] = (direct[p.type.slice(9).toLowerCase()] || 0) + 1
      }
      if (["VECTOR", "BOOLEAN_OPERATION", "STAR", "POLYGON", "LINE"].includes(n.type)) direct.paths++
      if (n.type === "TEXT") { direct.texts++; if ((n.effects || []).some(e => e.visible !== false)) direct.text_effects++ }
      if (["RECTANGLE", "ELLIPSE"].includes(n.type)) direct.shapes = (direct.shapes || 0) + 1
      if (n.isMask) direct.masks++
    }
    if ("children" in n && n.type !== "BOOLEAN_OPERATION") for (const c of n.children) await walk(c)
  }
  await walk(screen)
  const masters = Object.values(atlas).sort((a, b) => b.area - a.area)
  out.push({ id, name: screen.name, size: [Math.round(screen.width), Math.round(screen.height)], atlas_share: +(atlasArea / area).toFixed(2), masters, direct })
}
return out
"""


def run(ids):
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
        f.write(SCRIPT.replace("__IDS__", json.dumps(ids)))
        path = f.name
    out = subprocess.run(["python3", "figma.py", "--port", PORT, "run", path, "--timeout", "600"], cwd=BRIDGE, capture_output=True, text=True)
    os.unlink(path)
    return json.loads(out.stdout)


def shot(node_id, folder):
    target = os.path.join(os.path.abspath(folder), node_id.replace(":", "_") + ".png")
    subprocess.run(["python3", "figma.py", "--port", PORT, "shot", node_id, "--max", "900", "-o", target], cwd=BRIDGE, capture_output=True)


def effects_text(stats):
    parts = ["%s %d" % (k, v) for k, v in sorted(stats["effects"].items())]
    if parts:
        parts.append("max r %d" % stats["max_radius"])
    for key in ("linear", "radial", "angular", "diamond"):
        if stats.get(key):
            parts.append("%s %d" % (key, stats[key]))
    for key in ("bitmaps", "paths", "blend", "masks", "text_effects"):
        if stats.get(key):
            parts.append("%s %d" % (key, stats[key]))
    return ", ".join(parts) or "-"


def master_class(content):
    effects = content["effects"]
    if content["bitmaps"]:
        return "bitmap"
    if content["blend"] or effects.get("inner_shadow") or effects.get("background_blur") or effects.get("layer_blur") or content["max_radius"] >= 24:
        return "heavy"
    return "light"


def summary(screen):
    area = screen["size"][0] * screen["size"][1]
    shares = {"bitmap": [0, 0.0], "heavy": [0, 0.0], "light": [0, 0.0]}
    for m in screen["masters"]:
        entry = shares[master_class(m["content"])]
        entry[0] += 1
        entry[1] += m["area"] / area
    stretched = sum(1 for m in screen["masters"] if m["stretched"])
    return "   summary: " + ", ".join("%s %d masters %.0f%%" % (k, v[0], v[1] * 100) for k, v in shares.items()) + ", stretched masters %d" % stretched


args = sys.argv[1:]
shots = None
if "--shots" in args:
    index = args.index("--shots")
    shots = args[index + 1]
    del args[index:index + 2]
    os.makedirs(shots, exist_ok=True)
result = run(args)
for screen in result:
    print("== %s %s %dx%d atlas share %.2f" % (screen["id"], screen["name"], screen["size"][0], screen["size"][1], screen["atlas_share"]))
    print(summary(screen))
    direct = screen["direct"]
    print("   direct: shapes %d, texts %d | %s" % (direct.get("shapes", 0), direct["texts"], effects_text(direct)))
    for m in screen["masters"]:
        share = m["area"] / (screen["size"][0] * screen["size"][1])
        print("   %5.1f%% x%-2d stretched %-2d %4dx%-4d %-40s %s" % (share * 100, m["count"], m["stretched"], m["size"][0], m["size"][1], m["name"][:40], effects_text(m["content"])))
    if shots:
        shot(screen["id"], shots)
