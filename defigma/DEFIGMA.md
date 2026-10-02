# Defigma runtime

Runtime half of the Figma → Defold exporter. Everything the Figma plugin cannot express as a Defold
node property travels inside the `.gui` itself and is applied here.

Plugin side: `/home/sergey/figma_plugins/Defigma` (`Defigma_RU.md` → *Runtime Data Node*).
Script generation: `python/sync_defigma.py`, documented in `python/sync_defigma.md`.

## Files

| File | Role |
|---|---|
| `data.lua` | Decodes the `defigma_data` node into `{ gradients, text_shadows, params }`. |
| `screen.lua` | Hook dispatcher used by every generated `.gui_script`. Knows nothing about concrete features. |
| `rtl.lua` | Feature: horizontal mirroring for right-to-left locales. |
| `gradient.lua` | Text gradient (`linear_text`) application and transform math. |
| `gradient_nodes.lua` | Registry of text gradient and text shadow nodes owned by one screen or widget: what is refreshed every frame and what on demand. |
| `text_shadow.lua` | Writes the offset and the blur of every text shadow into its node. |
| `materials/` | `shape` (every shape node) and the text materials `linear_text`, `text_shadow`, `linear_text_shadow`; `*.glsl` are the parts they share through `#include`. There is no box gradient or shadow material any more. |
| `ext.manifest`, `src/` | Native extension: the `DefigmaShape` custom GUI node type. |
| `commonsrc/`, `include/defigma/` | Shape geometry and property parsing, shared by the engine and the editor library. |
| `pluginsrc/` | Editor library entry points (`DefigmaShape_Build`) and the bob plugin that registers the custom type. |
| `plugins/` | Built editor libraries per platform and the bob plugin jar. |
| `api/` | `defigma_shape` Lua API description: `.script_api` for the editor, `---@meta` file for LuaLS. |
| `editor/src/defigma_shape.clj` | Editor node type: properties, save format and the preview. |

## The data node

Defigma adds one node to every exported `.gui`:

```text
id: "defigma_data"   type: TYPE_TEXT   parent: "root"   enabled: false
```

Its text is single-line JSON:

```json
{"gradients":{"bar_fill":{"type":"linear","data":[[0,0.5,0],[1,0.5,0]],"stops":[…]}},"params":{"title":"rtl"}}
```

- `gradients` — derived by the plugin from Figma fills and effects.
- `params` — authored in Figma through the `custom_parameters` metadata key, or inherited from a
  container via `child_custom_parameters` / `child_text_custom_parameters` /
  `child_non_text_custom_parameters`. The value is whatever JSON was written there: a string, an
  object, an array, a number.
- `text_shadows` — `[[x, y, sigma], …]`, one or two drop shadows of a text in Figma order, see
  [Text shadows](#text-shadows). Only a `.gui` with a shadowed text has this section; `data.load`
  returns an empty table otherwise.
- Keys are the **local** node ids of that `.gui`. A template carries its own data, so one widget
  module serves any number of visual variants.

`data.load(node)` rebuilds `vmath` vectors from the flat arrays and returns the table.

```lua
local data = require("defigma.data")

local screen_data = data.load(gui.get_node(data.NODE_ID))   -- screen
local widget_data = data.load(self:get_node(data.NODE_ID))  -- Druid widget
```

The id `defigma_data` is reserved — an exported Figma object with that id fails plugin validation.

## `screen.lua`

Required by every generated `.gui_script` as `defigma` and called from every hook:

```lua
defigma.init(self, SCREEN_ID)                             -- after monarch.add_listener()
defigma.on_message(self, message_id, message, sender)     -- last in on_message
defigma.on_input(self, action_id, action)
defigma.update(self, dt)
defigma.language_changed(self)                            -- from the local language_changed()
defigma.final(self)
```

It loads the data node, applies gradients and text shadows, and dispatches `params` to registered
features. It has no dependency on any feature or on the localization layer.

Also exposes:

- `defigma.param(self, node_id)` — the raw `custom_parameters` value for a node.
- `defigma.register_runtime_param(self, node_id, value)` — registers a runtime node in the same
  feature lifecycle and immediately runs its `init` callbacks.
- `defigma.unregister_runtime_param(self, node_id)` — runs the runtime node's `final` callbacks and
  removes it before the GUI node is deleted.
- `defigma.release_touch_input(self)` — shared helper, previously duplicated into every `.gui_script`.

## Gradients

Only text has gradients here: every other node is a shape node and carries its gradients in its own
geometry. The `linear_text` shader needs the inverse node transform and the text bounds as per-node
material constants. Both are functions of the node's **world transform**, so they have to be
re-applied whenever that transform changes — a text moved by a scroll, an animation, a window resize
or a layout change would otherwise keep rendering with a stale gradient.

### The node transform

`gradient.lua` takes the node transform from the engine: `gui.get_screen_position` for the origin and
two `gui.screen_to_local` probes for the basis, so every parent transform, adjust mode, anchor and
safe area offset the engine renders with is already in it. Nothing is cached and no parent chain is
walked, so `gradient.apply` / `gradient.apply_transform` cost the same for one node as for many and
window events need no context refresh — only a `gradient_nodes.refresh`.

### The registry

`gradient_nodes.lua` owns the per-screen and per-widget lists:

```lua
local gradient_nodes = require("defigma.gradient_nodes")

local state = gradient_nodes.create(gradients)     -- explicit node list
gradient_nodes.add(state, node_name, node)         -- applies stops + transform once
local state = gradient_nodes.create_for_widget(self) -- loads the widget data node, adds every gradient

gradient_nodes.update(state)                       -- entries kept in the per-frame update
gradient_nodes.refresh(state)                      -- every entry, regardless of the flag
```

`gradient_nodes.add` puts the node **into the per-frame update by default**. Screens follow that
default: `defigma.init` registers every gradient node of the `.gui` and `defigma.update(self, dt)`
refreshes them each frame, so a screen needs no extra wiring.

### Turning the per-frame work off

Per-frame gradient work is cheap for a handful of nodes and expensive when it is multiplied by
dozens of widget instances — each refresh queries the transform of every node it owns. Two ways to
opt out:

```lua
defigma.set_node_updating(self, "title", false)     -- one screen node
defigma.set_all_nodes_updating(self, false)         -- the whole screen

gradient_nodes.set_updating(state, node_name, false) -- one widget node
gradient_nodes.set_all_updating(state, false)        -- the whole widget
```

An excluded node is still refreshed on window/layout events; anything else has to be triggered
explicitly — after a data change that alters the node's text or size, call `gradient_nodes.refresh`.

Nodes carried by a scroll are the usual reason to opt out: bind the registry to the scroll and it is
refreshed on real movement only (the guard compares the scroll content node position, so the
`on_scroll` events a scroll keeps firing while it settles cost nothing).

```lua
gradient_nodes.bind_scroll(state, scroll)   -- druid.scroll or any component with on_scroll + content_node
gradient_nodes.unbind_scroll(state)         -- in the widget on_remove
defigma.bind_scroll(self, scroll)           -- same for the screen registry
```

Several scrolls can be bound to one registry — a node moved by nested scrolls needs all of them.

## Text shadows

Defigma exports the first two visible drop shadows of a Figma text; the shadows of images are not
exported yet. Figma stacks the effects of a layer in list order, the first one lowest, and a
multi-layer Defold font draws the shadow layer of every glyph, then the outline layer, then the
face: the first shadow takes the shadow layer, the second one the outline layer. Three things carry
them:

- The font. The text node uses `<font>_shadow` for one shadow or `<font>_shadow2` for two, which
  `python/sync_defigma.py` writes next to `<font>.font` whenever an exported `.gui` refers to them:
  the same glyphs in `MODE_MULTI_LAYER` with `outline_width: 4` and `shadow_blur: 11`, and in
  `_shadow2` also `outline_alpha: 1` to turn the outline layer on. Multi-layer makes the engine emit
  each layer of all glyphs before the next one, so no shadow covers a neighbouring letter. The two
  widths give every glyph 16 px of padding for the blur to spread into and a distance field that
  measures 5.4 px into the glyph; the shadow channel they also create is not read. The glyph cache
  is fixed at 1024x512: GLSL ES 1.00 has no `textureSize`, so `GLYPH_CACHE_SIZE` in
  `materials/text_shadow.glsl` holds it, and the two change together.
- The material, `text_shadow`, or `linear_text_shadow` over a gradient fill (the gradient runs
  exactly as in `linear_text`). The vertex shader moves each shadow layer by its offset. The
  fragment shader blurs the glyph with a Gaussian: 5x5 taps one sigma apart with Gaussian weights,
  each tap a glyph coverage softened by 0.4 sigma straight from the distance field, which together
  make one Gaussian of the full sigma. A shadow pixel farther from the glyph than the taps reach
  returns before sampling. The first shadow takes its colour and alpha from the node `shadow` /
  `shadow_alpha`, the second from `outline` / `outline_alpha`, so `gui.set_shadow`,
  `gui.set_outline` and the palette variants keep working; a text with two shadows has no stroke.
- The constants `text_shadow` and `text_shadow2` = `(x, y, sigma, 0)` in units of the font (32 px):
  the Figma offset with +Y up and the Gaussian sigma of the Figma blur, `0.43 * radius`, both divided
  by the text scale, so the shadow scales with the text. `defigma.init` writes them into every
  screen node listed in `text_shadows`, `gradient_nodes.create_for_widget` into the nodes of the
  widget's template, and `gui.clone` copies them along with the node. Nothing refreshes them later:
  they do not depend on the node transform.

The engine counts the padding of these fonts into the layout of a line: `resource.get_text_metrics`
returns 30 font units more than for the base font whatever the text, and the glyphs of a left
aligned text start 15 units (`outline_width + shadow_blur`) to the right of the pivot, of a right
aligned one end 15 units to the left of it; a centred text stays put. The exporter grows the box of
a shadowed text by those 15 units times the text scale on both sides, so the glyphs sit where Figma
draws them. Code that measures such a text gets the padding too; centring it by the measured width
is still right, since the padding is the same on both ends.

Measured against Figma exports of the same texts (offset 4, blur 8, 26-42 px): the offset and the
peak match, the blur comes out 3-7% wider and up to 10% denser on the thinnest and smallest texts,
where the softened taps thicken the strokes a little.

Limits:

- The offset is applied along the screen axes: a rotated text keeps its shadow straight down.
- The blur must fit into the 16 px of padding: sigma up to about 5 font units is clean, that is the
  Figma blur 8 on a text of 22 px and more, a glow of 16 on a text of 44 px; a wider one is cut at
  the edge of the glyph quad.
- A third shadow and inner shadows are not exported, and a text with two shadows loses its stroke.
- The shadows of neighbouring letters are mixed by alpha blending instead of added, which only
  matters where both are dense.

## Shape nodes

Every Figma rectangle, ellipse, arc, vector and frame fill or stroke outside an atlas section is one
`TYPE_CUSTOM` node, `custom_type_name: "DefigmaShape"`, material `shape` (there is no metadata that
switches it on or off). Its look lives in custom properties, so it needs no `defigma_data` entry and
no Lua:

| Property | Type | Meaning |
|---|---|---|
| `shape` | string | `rect` (default), `ellipse` or `path` |
| `corner_radius` | vector4 | top-left, top-right, bottom-right, bottom-left, Figma pixels |
| `fills`, `strokes` | string | JSON array of paints: `{"type":"solid","color":[r,g,b,a]}` or `{"type":"linear"\|"radial","transform":[6],"stops":[[pos,r,g,b,a],...]}` with 1-64 stops; `transform` is the Figma `gradientTransform` |
| `stroke_width`, `stroke_align` | number, string | `inside` (default), `center`, `outside` |
| `effects` | string | JSON array: `{"type":"drop_shadow","offset":[x,y],"radius","spread","color","show_behind"}`, `{"type":"layer_blur","radius"}` |
| `path` | string | `{"fill":{"polygons":[[x,y,...],...],"edges":[...]},"stroke":{...}}` in node pixels, Figma axes: convex pieces (the exporter writes at most 60 points, points past 96 are dropped) and the outline edges, which keep the filled side on the right |
| `arc_start`, `arc_sweep`, `arc_ratio` | number | an ellipse arc with the Figma arc controls: start in degrees (clockwise from the right, as in Figma), sweep and ratio in percent; defaults 0 / 100 / 0 (a full ellipse). `corner_radius.x` rounds the arc corners like the Figma corner radius |
| `clip` | string | JSON `[x,y,...]`, the convex outline of the `Clip content` frame in node pixels, Figma axes; every piece of the node is cut by it (hard edge); points past 96 are dropped |

A shape filled with one solid color is exported like a box: the fill color and its opacity are the
node color and alpha, and `fills` is plain white. A stroke or a drop shadow of the same color (a rim,
a glow) follows it: it is written white with its alpha relative to the fill, so recoloring the node
recolors the glow too. `gui.get_color`,
`gui.set_color` and `color.w` tweens then read and change the fill exactly as they did on the atlas
boxes before. Any other shape keeps its colors in `fills` / `strokes` and a white node color, which
tints everything the node draws; change such colors with `defigma_shape.set_paints`.

A property value that is not valid JSON, nests deeper than 16 levels, holds a number outside the
finite float range, misses a key or has an array shorter than its format (a color of fewer than 4
numbers, a transform of fewer than 6, a stop of fewer than 5), or a gradient with more than 64 stops
is rejected: the engine logs `DefigmaShape '<id>': invalid <property>` and keeps the paints or
effects read before the bad entry, the editor preview draws nothing for the node. A node whose size
is not a positive finite number builds no vertices.

Memory: `tools/memcheck/run.sh` runs the geometry and the editor library on every exported node,
a fuzzer and 8 concurrent threads under AddressSanitizer + UndefinedBehaviorSanitizer,
ThreadSanitizer and valgrind (0 errors, all heap blocks freed). `tools/memcheck/engine_leak.py`
runs the node in the engine: load/unload through a proxy, resize every frame, enable toggling,
`gui.clone_tree` / `gui.delete_node` every 5 frames, layout switches. valgrind (headless engine):
0 bytes definitely or indirectly lost, no report through the extension; heaptrack diff of 10 vs 40
release cycles: nothing allocated through `dmDefigma` / `defigma::` stays alive, the growth is the
NVIDIA driver (shader compilation on every proxy load) and the debug-build clone name table.

### How it renders

`GetVertices` builds the geometry once per node size (`commonsrc/shape_geometry.cpp`) and copies the
cached vertices every frame; the engine applies the node transform, color and opacity. Nothing
depends on the node transform, so scrolls, animations and layouts need no refresh, and every shape
node of one material batches into one draw call - the node carries no material constants.

Everything a pixel needs travels in the standard GUI vertex:

- `color` - the paint color at that vertex. Pieces are cut along the gradient stops (linear) or
  along rings at the stops and 12-32 sectors, one per 12 pixels of gradient radius (radial), so the
  interpolated color is the gradient. The antialiasing fringe of a path is not cut.
- `texcoord0` - the distance field coordinate: for a rounded rectangle the position folded into
  one quadrant minus the inner corner box, for an ellipse the position over the half size, for a
  blur the same in units of sigma, for a path edge the signed distance to the edge, for an arc the
  position over the half size, turned so that the nearer arc end lies on the +y axis.
- `page_index` - a packed integer: the mode (rounded rect, ellipse, their blurs, three ellipse
  stroke alignments, path edge or arc) and its constants (radius, stroke width, radius and inner box
  over sigma, axis ratio, arc ratio and corner). `shape.vp` decodes it.

The inside of a rounded rectangle or ellipse fill, away from its edge, is a separate flat piece:
the fragment shader returns the vertex color there without any distance math or derivatives, so
only the thin border band pays for the antialiasing.

### Arcs

An ellipse with `arc_sweep` below 100 or `arc_ratio` above 0 is an arc, exported from the Figma
`arcData` and `cornerRadius` of the ellipse. It is drawn in two halves split at the middle of the
sweep; each half is covered by ring sectors of at most 30 degrees plus the corner overhang and
evaluates one analytic distance: the ring (inner radius = ratio, outer = 1 in half-size units)
intersected with the half-plane of its own end, the corner rounded with the rounded-box formula.
A progress ring is 60 vertices whatever the sweep, a full donut 96. Fills (solid, linear, radial)
work, and so do strokes (all three alignments), drop shadows and layer blur.

Strokes, shadows and blur of an arc reuse the rounded-rectangle modes: the geometry is cut into an
angle x radius grid (a chord deviates at most 0.2 px from the curve for a stroke, 0.5 px for a
blur, cut at the centre line and at the middle of the sweep) and every vertex gets a "warped"
distance coordinate, the arc unrolled into a straight rounded bar: along = distance from the nearer
end along the centre line, across = distance from the centre line. `shape.fp` evaluates it as an
ordinary rounded rectangle or its Gaussian blur, so the shader did not change and an arc without
these effects costs exactly what it did. The effects follow `arc_start` / `arc_sweep` /
`arc_ratio`, so `set_arc` / `set_sweep` move them too. Figma semantics kept: an arc shadow's spread
grows the whole ellipse (the inner edge moves out, the ends stay on their radial lines), sigma is
0.43 x the Figma radius, a shadow without offset and without `show behind` is knocked out under the
fill, an outside stroke underlaps the fill by one antialiasing step like on rectangles.

Against the Figma export of `tests/arcs_test` (round and square ends, pies, a donut, partial corner
radius, tiny and wide sweeps, an elliptical arc, translucent fill) the mean difference is 0.2/255.
Two known differences: the corners of a non-circular arc are rounded in the ellipse's own scaled
space (Figma rounds in pixels), and a partial corner radius on a thick arc rounds the inner corners
a little less than Figma. A sweep shorter than the corner radius (a dot) is slightly flattened.

Effects against the Figma export of `tests/arcs_fx_test` (glow, offset and spread shadows, a pie
shadow, the three stroke alignments, layer blur, an elliptical arc with everything, a translucent
arc, a full ring): under 1/255 mean per region, the elliptical arc 1.8/255. Known differences:
stroke, shadow and blur of an elliptical arc use the average radius of the ellipse (the inner edge
of the effect can sit ~1 px off on a strongly elliptical arc); a shadow with an offset is not
knocked out (visible only under a translucent fill); layer blur blurs the fills only, as on
rectangles.

### Lua API

The extension registers the `defigma_shape` module (implemented in C++, `src/gui_node_shape.cpp`),
callable from a gui_script on a `DefigmaShape` node:

```lua
defigma_shape.set_sweep(node, sweep)                      -- percent, keeps start and ratio
defigma_shape.set_arc(node, start, sweep, ratio)          -- degrees, percent, percent
local start, sweep, ratio = defigma_shape.get_arc(node)
defigma_shape.set_paints(node, fills, strokes)            -- JSON arrays, the fills / strokes format
local fills, strokes = defigma_shape.get_paints(node)
```

`set_arc` / `set_sweep` replace the node's arc (a full ellipse node becomes an arc) and rebuild only
that node's vertices on the next frame, so animating a progress ring every frame costs a few
microseconds; the description is changed in place when no clone shares it, so a tween allocates
nothing. `set_paints` replaces the fills and strokes (for example a stroke recolored by state, or
the look of one node copied to another with `get_paints`); an invalid JSON raises an error. The
values are also written into the node's custom properties, so `gui.clone` / `gui.clone_tree`
copies keep them; a layout change restores the values of the layout, like every other static
property. Any other node raises `not a DefigmaShape node`. `tests/arcs_test/arcs_api.gui_script`
exercises it. `api/defigma_shape.script_api` gives the editor completion, `api/defigma_shape.lua`
the LuaLS annotations (`---@meta`).


Antialiasing uses the screen derivatives of the distance (`GL_OES_standard_derivatives` on GLES2);
`shape.vp` and `shape.fp` are `highp` throughout. Blurs are Gaussian: sigma is `0.43 * radius` for shadows and layer
blur, a rounded rectangle uses the Evan Wallace integration, an ellipse the same integration over
its chords. A drop shadow is cut out under the shape unless `show_behind` is set.

Measured against Figma exports of the same frames, the mean difference is under 1/255 on shapes;
the largest remaining ones are tiny blurred ellipses (layer blur of a radial gradient is
approximated as blurred shape times the unblurred gradient) and the outer edge of thick ellipse
strokes (first-order distance).

### Cost

The engine calls `GetVertices` for every custom node every frame, then transforms each vertex on
the CPU and uploads the whole GUI vertex buffer again: there is no static buffer for custom nodes.
The CPU cost of a shape screen is therefore proportional to its vertex count, and the GPU cost to
the covered area times the mode (a blur runs a 4-sample integration per pixel). Keep both down:
no large blurred shapes in vector form (bake glows into the background image), few radial
gradients over big areas.

Measured on the `tests/bench_screen` store screen (background with two blurred glows and a
vignette, header, nine cards with shadow, stroke, glow, badge and plate, a button, texts), debug
build, milliseconds per frame, one layer / eight stacked layers moving:

| Variant | Desktop i5-12400F + RTX 4060, 486x1035 | Redmi Note 10 Pro (SD 732G, Adreno 618), 1080x2400 | Draw calls | Vertices |
|---|---|---|---|---|
| raster atlas (ASTC 4x4) | 0.21 / 0.55 | 2.15 / 10.2 | 32 | 72 |
| material gradients + Lua refresh (the removed path) | 0.62 / 4.03 | 4.96 / 37.6 | 94 | 1116 |
| shape nodes | 0.37 / 2.14 | 8.55 / 64.4 | 32 | 14622 |
| shape nodes, background as image | 0.36 / 1.98 | 4.40 / 29.8 | 33 | 13290 |

On the phone the shape screen waits 3.2 ms for the GPU (raster 0.5 ms) and spends 1.5 ms on the
vertex path; the background glows alone account for about 2 ms of GPU time. The raster screen
needs an 8 MB ASTC atlas (32 MB uncompressed), the shape screen no texture and about 0.6 MB of
cached vertices. Shape nodes are faster and look better than the material gradients (shadows,
clipping and vectors the material path cannot do), a raster atlas stays the cheapest to draw.

#### Cheap and expensive operations

CPU cost is the vertex count (built once per size, transformed and uploaded every frame), GPU cost
is the covered area times the shader mode, plus overdraw: every shape node is blended, so a panel
made of six stacked full-size shapes shades its area six times where an atlas image shades it once.
Vertex counts for a 300x120 rounded rectangle (`tools/geometry/vertex_count.cpp`):

| Operation | Vertices | Pixel cost | Use |
|---|---|---|---|
| solid fill, rect or rounded rect | 54 (flat inside + antialiased border band) | flat inside, distance only in the border band | freely |
| solid ellipse | 30 | flat inscribed rectangle, distance around it | freely |
| linear gradient | +12 per stop | same as solid | freely |
| stroke on rect / ellipse (any alignment) | 48-126 (the hole is cut only when it is at least 32x32 px) | ring area | freely |
| drop shadow, small radius (up to ~16) | ~180 (shape knocked out of the shadow) | (w + 6 sigma)(h + 6 sigma), 4-sample integral | a few per screen |
| radial gradient | 330-430 (rings at the stops x 12-32 sectors) | same as solid | small shapes; not on dozens of instances |
| arc (progress ring, pie, donut) | 60 for a ring of any sweep, 24 for a pie, 96 for a full donut | ring sector area | freely; animate with `defigma_shape.set_arc` |
| arc stroke / shadow / layer blur | stroke 580-850, shadow or glow 290-420 (knocked-out translucent arc ~1 600), blur ~220 | stroke: ring area; shadow: the blurred ring band, 4-sample integral | a few per screen; the arc without them keeps its 60 vertices |
| `path` (vectors, boolean ops) | convex pieces + 2 per outline edge; curves flattened every 6 px | 1x area | icons with few points; a round-cap stroke of a small check mark is already ~360 |
| `clip` (child crossing a `Clip content` frame) | every piece cut by the outline | - | fine; hard edge |
| large drop shadow / glow (radius 24+) | ~200 | a quad of (w + 6 sigma)(h + 6 sigma), 4-sample integral | avoid on big nodes; bake into the image |
| layer blur | 24 | same as a large shadow, over the whole blurred quad | avoid; bake into the image |
| many stacked translucent full-size layers | - | overdraw per layer | flatten into one image |
| background blur, inner shadow, blend modes, angular / diamond gradients, image fills | not supported | - | keep as raster |

Every `CompGuiNodeTypeSet*Fn`, and the context, has to be set in `GuiNodeTypeCreate`: the engine
does not initialize `CompGuiNodeType`, and an unset update callback crashed the Android build.

Limits: no inner shadow, no angular or diamond gradient, no blur or shadow on a `path`, no blend
modes; the `clip` edge is not antialiased. A shape node is not a stencil clipper that follows its
corners; use a box clipper.

### Results screen: four ways to export one real screen

`tests/results_screen` is the Dexfut match result screen (Figma 4575:231281) exported four ways
from the same masters; the vector copies detach the master instances, so they export as shape nodes:

| Variant | What is raster | Shape nodes | Shape vertices | Effects in shape nodes |
|---|---|---|---|---|
| `results_raster` | everything, the native progress bars and pills too; text keeps the shadow material | 0 | 0 | - |
| `results_current` | atlases as in Dexfut, native shapes (bars, pills) as shape nodes | 17 | 1 056 | 3 nodes with shadows |
| `results_bg_raster` | background image; panels, chips, rings, task plates as shape nodes | 140 | 23 166 | 39 nodes with shadows, 9 with layer blur |
| `results_vector` | only emblems and flags | 169 | 32 619 | 49 nodes with shadows, 9 with layer blur |

`_plain` copies of the last three have every effect removed: they are the "no blur, no shadow"
measurement, the lower bound of what the geometry itself costs. The masters of this screen are not
effect-free: the panels carry glows (layer blur) and drop shadows, `league_chip` an inner shadow
(not supported, lost in the vector variants).

Against the Figma export all four differ by 6.8-7.1/255 mean, almost all of it common to every
variant (fonts, the round flag mask and the task checks, which are runtime logic). Against the
raster variant in the engine: current 0.21, bg_raster 1.43, vector 2.0 - antialiased edges and the
blurred tile glints.

Frame time, debug build, milliseconds, 1 layer static / 8 layers moving. The Redmi 9C (Helio G35,
PowerVR GE8320, 3 GB, 720x1600, armeabi-v7a) is a phone on which the home screen already lags; its
profile columns are for 1 static layer: GPU wait (`OpenGLFlip`), CPU of the GUI render pass
(`RenderNodes`, of it `DefigmaShape` copying the cached vertices) and the vertex count the engine
reports.

| Variant | Desktop i5-12400F + RTX 4060, 432x920 | Redmi 9C | GPU wait | RenderNodes / DefigmaShape | GUI vertices |
|---|---|---|---|---|---|
| raster | 0.34 / 1.30 | 23.9 / 150 | 9.1 | 1.09 / - | 312 |
| current | 0.37 / 1.52 | 24.8 / 157 | 7.6 | 1.48 / 0.14 | 1 266 |
| current, plain | 0.37 / 1.46 | 24.3 / 153 | 7.5 | 1.50 / 0.13 | 726 |
| bg raster | 0.54 / 3.12 | 34.8 / 232 | 13.9 | 4.53 / 1.11 | 13 936 |
| bg raster, plain | 0.49 / 2.55 | 28.3 / 184 | 9.5 | 3.57 / 0.95 | 8 347 |
| vector | 0.66 / 5.09 | 67.6 / 499 | 33.5 | 9.23 / 2.22 | 23 383 |
| vector, plain | 0.60 / 3.65 | 42.1 / 293 | 18.2 | 6.19 / 1.68 | 17 794 |

On the weak phone even the raster screen runs at 41 fps (debug build, GPU-bound: full-screen
background plus translucent panels). `current` costs the same as raster (+4%). Panels as shape
nodes cost +18% without effects and +45% with their glows and shadows; the whole screen in vector
+76% / +183%. The extra time is both CPU (vertices: 1 ms of GUI work per ~3 000 vertices on this
phone) and GPU (overdraw of stacked panel layers, blurs).

### Panels: one light master, raster slice9 vs shape node

`tests/panels_screen` isolates the cheapest real case: the `my_profile` background (image) and its
five `panel_bg` / `panel_bg_small` panels (Figma 3260:43499), one rounded rectangle each with two
linear fills (2 and 4 stops) and a 3 px linear stroke, 204-216 vertices per panel. Redmi 9C,
milliseconds, 1 / 4 / 8 layers moving (1 layer static for the first column):

| Variant | Frame time | GUI vertices |
|---|---|---|
| raster, slice9 atlas image | 5.6 / 8.3 / 12.9 | 228 |
| shape nodes | 10.4 / 21.1 / 41.7 | 1 062 |
| shape nodes, first fill only | 9.4 / 11.9 / 23.6 | 762 |
| shape nodes, shader without the blur code | 10.6 / 21.1 / 41.6 | 1 062 |
| both | 10.8 / 11.9 / 23.6 | 762 |

After the flat interior (the inside of a fill skips the distance math, see *How it renders*), in a
new run of the same phone (runs differ by up to 30%, compare within one run):

| Variant | Frame time |
|---|---|
| raster, slice9 atlas image | 6.8 / 10.9 / 16.3 |
| shape nodes | 10.9 / 16.2 / 31.1 |
| shape nodes, first fill only | 8.8 / 13.3 / 18.8 |

The CPU part is small (0.4 ms of GUI work). The cost is GPU fill: every fill of a node is its own
pass over the whole node area, so the second fill nearly doubles the time. Removing the blur
branches changed nothing, but computing the distance and its screen derivatives for every pixel did
cost: with the flat interior one fill is within 16% of the slice9 image at 8 layers (was 1.8x), and
two fills 1.9x (was 3.2x). A large panel with several fills is cheaper as a raster image on weak
GPUs; `panel_bg` already stretches correctly through slice9.

### Choosing raster or vector

- **Keep as raster** whatever has image fills, background blur, blend modes, inner shadows, large
  glows or many stacked translucent layers: full-screen backgrounds, big decorated tiles and
  buttons, pack art. A baked image is one quad; the vector version is several blended layers.
- **Use shape nodes where a raster is wrong or wasteful**: small elements that stretch in a way
  slice9 cannot follow (bars, pills, rings), progress bars and rings that change at run time, and
  simple shapes that repeat in many sizes (each size would be another atlas image). A large panel that slice9 can stretch stays a
  raster image: its area, times the number of fills, is what the weak GPU pays for.
- **Do not vectorize a whole screen.** A decorated panel becomes dozens of nodes and thousands of
  vertices, and on a weak GPU its overdraw and glows cost more than the atlas it replaces. The
  `current` variant - atlases plus shape nodes only for the native shapes - costs the same as full
  raster.
- `tools/figma/screen_census.py` lists, per screen, which masters are `bitmap` / `heavy` / `light`
  and how many instances are stretched: `light` + stretched is the vector candidate.

### Editor

`editor/src/defigma_shape.clj` registers the node type (Add > Defigma Shape), shows the properties
and renders the preview with the real `shape.material`, getting the vertices from the editor
library in `plugins/lib/<platform>/` through JNA: `DefigmaShape_Build` returns the vertex count and
keeps the vertices in thread-local storage, `DefigmaShape_CopyVertices` copies them out, so both
must be called on the same thread (the editor evaluates nodes on several threads at once). Resizing
the node rebuilds the shape. After a
change in `commonsrc/` or `pluginsrc/` rebuild the libraries for every desktop platform and copy
them into `plugins/`:

```bash
java -jar bob.jar --platform x86_64-linux --variant headless --build-artifacts=plugins build
```

(`x86_64-macos`, `arm64-macos`, `x86_64-win32` the same; results land in `build/<platform>/defigma/`,
the bob plugin jar in `build/x86_64-linux/defigma/pluginDefigmaShape.jar` goes to `plugins/share/`.)
The editor loads the libraries once: restart it after replacing them.

## Risks and measured numbers

Everything measured while the shape nodes were built, in one place. Debug builds unless noted; frame
times in milliseconds. Devices: desktop i5-12400F + RTX 4060; Redmi Note 10 Pro (Snapdragon 732G,
Adreno 618, 1080x2400); Redmi 9C (Helio G35, PowerVR GE8320, 3 GB, 720x1600, armeabi-v7a - a phone on
which the home screen already lags). Tools: `tools/` (see `tools/README.md`).

### Numbers

| What | Result |
|---|---|
| Accuracy against the Figma export | shapes under 1/255 mean (`shapes_test` 0.72), arcs 0.2/255 (`arcs_test`); a real screen as vector vs as raster in the engine 1.4-2.0/255, all of it antialiased edges |
| Results screen, Redmi 9C, 1 layer | raster 23.9, atlases + native shapes 24.8, panels as shapes 34.8 (28.3 without effects), everything as shapes 67.6 (42.1 without effects) |
| Results screen, desktop, 1 / 8 layers | raster 0.34 / 1.30, current 0.37 / 1.52, panels as shapes 0.54 / 3.12, everything 0.66 / 5.09 |
| Store screen, Redmi Note 10 Pro, 1 / 8 layers | raster 2.15 / 10.2, shapes 8.55 / 64.4, shapes with the background as an image 4.40 / 29.8, the removed material path 4.96 / 37.6 |
| Five `panel_bg` panels, Redmi 9C, 1 / 4 / 8 layers (same run) | slice9 image 6.8 / 10.9 / 16.3; shape nodes (two fills + stroke) 10.9 / 16.2 / 31.1; one fill 8.8 / 13.3 / 18.8 |
| Vertex cost on the CPU, Redmi 9C | about 1 ms of GUI work per 3 000-4 000 vertices, every frame (no static buffer, see *Cost*) |
| Vertices per node | solid rounded rect 54, linear +12 per stop, radial 330-430, stroke 48-126, small shadow ~180, ring or pie arc 60 / 24, donut 96, arc stroke 580-850, arc shadow 290-420, a real decorated panel 200-300 |
| Arc effects, Redmi 9C, 1000x760 scene of 11 arcs, 1 / 4 / 8 layers | with shadows, glows and blur 12.2 / 22.4 / 44.3; same arcs with effects stripped 8.5 / 13.3 / 17.8 (large glows dominate: cost follows the blurred area) |
| Dexfut on the Redmi 9C (before the migration, debug) | 30-50 fps; the main thread is the limit: a draw call costs 40-65 us in the PowerVR driver (draft screens 250-275 calls = 18-19 ms), ~12-14 ms fixed per frame; GPU time only 3.5-8.6 ms (Draft Battle divisions 12-17) |
| Memory | sanitizers, TSan, valgrind and a fuzzer on the geometry and the editor library: 0 errors, 0 leaks; engine stress (load/unload, clone/delete, resize, layouts) under valgrind and heaptrack: nothing through the extension stays alive |

### Risks

- **Fill cost on weak GPUs.** Every fill of a shape is its own pass over the node area, so a big
  panel with several fills costs a multiple of its slice9 image (1.9x for `panel_bg` on the
  Redmi 9C). Glows, large shadows and layer blur run a 4-sample integral over the blurred area.
  Keep big decorated panels, glows and backgrounds in atlases.
- **Vertex cost on the CPU.** The engine transforms and uploads every vertex every frame. Radial
  gradients, round-cap path strokes and long lists of cloned shapes multiply it. Count before a
  list of dozens of shapes goes into a scroll (`tools/geometry/vertex_count.cpp`).
- **Not drawn by a shape**: image fills, background blur, inner shadow, blend modes, angular and
  diamond gradients, blur and shadows of a `path`. They silently
  disappear from the node: put such elements into an atlas.
- **Stencil.** A shape node is a rectangle rounded by the shader, so as a stencil clipper it cuts a
  square. Round masks stay `TYPE_PIE` (metadata, `Defigma_EN.md` "Pie Nodes"). The `clip` property
  of a shape cut by a `Clip content` frame has a hard, not antialiased edge.
- **Arcs.** A non-circular arc rounds its corners in the scaled ellipse space (Figma rounds in
  pixels), and its stroke, shadow and blur follow the average radius; a partial corner radius on a thick arc rounds the inner corners a little less than
  Figma; a sweep shorter than the corner radius is slightly flattened. The Figma start angle is in
  the rotated frame of the ellipse: top is `-90 + rotation`. `gui.animate` cannot animate a custom
  property: tween in Lua and call `defigma_shape.set_sweep`. A layout change restores the layout's
  arc values.
- **Engine and build.** Needs Defold 1.13.1+ (custom node properties) and the native build server.
  Every `CompGuiNodeTypeSet*Fn` and the context must be set (an unset update callback crashed
  Android). The shader needs screen derivatives (`GL_OES_standard_derivatives` on GLES2): after a
  shader change build for `arm64-android` and read the `SHADERC` lines.
- **`mediump` in `shape.fp`.** On a Mali-G68 (driver r32p1) the fp16 vector operations are wrong
  for negative components: `abs(vec2)` returns `max(v, 0)`, and `max(v, -v)`, `dot(v, v)` and
  `length(v)` break the same way, while the scalar `abs(v.x)` and `v.x * v.x` are right. Ellipses,
  ellipse strokes, arcs and blurred shadows came out square everywhere but their top-right corner.
  A `highp` varying alone or a scalar rewrite of `length` does not fix it (the strokes and the blurs
  keep vector math, and a compiler may vectorize scalar code again); the shader math is `highp`.
  Cost on that phone: 30 overlapping 900x900 blurred ellipses, 27.1 ms per frame in `mediump`
  vs 31.8 ms in `highp` (+17 %, fragment-bound worst case). Do not bring `mediump` back into the
  shape shaders. After a shader change compare an ellipse on a Mali phone with the desktop.
  The same phone draws the `linear_text` gradient right in all four directions in `mediump` (its
  position arrives as a `highp` varying, the direction comes from a uniform), and so do the
  `linear` / `radial` materials of the pre-shape Defigma, so those stay `mediump`.
- **Data format.** The runtime reads the shape properties and the text gradient data from the `.gui`.
  A change of either format means exporting every `.gui` again from Figma; a `.gui` from before
  the migration that
  still names the removed `linear` / `radial` / `drop_shadow` materials does not load. Every
  `TYPE_CUSTOM` override (a template child recolored by an instance, a layout override) must
  carry `custom_type`: bob and the engine take the type from the template and build it, but the
  editor fails with `Unable to locate GUI node type info ... custom-type=0` and cannot open the
  `.gui`. Open the project in the editor after an export, a green bob build does not prove it.
- **Editor.** The editor loads the libraries in `plugins/lib/<platform>/` once: restart it after
  replacing them, and rebuild all four platforms after any change in `commonsrc/` or `pluginsrc/`.
- **Export.** An atlas section that only holds preview placeholders (Dexfut `clubs`, `nations`,
  `leagues`, `card_fons_out`) must never be exported over the game atlas (hundreds of images vs a
  few placeholders), and a `.gui` whose nodes a script or a person sets up in Defold (spine
  placeholders, texture lists written by a script) must not be exported over; each project lists
  them in its `md/FIGMA_BRIDGE.md`.

## Features

A feature is a table of optional callbacks, registered once at load time:

```lua
---@type defigma_feature
local feature = {
	init            = function(self, node_id, value, state) end,
	layout_changed  = function(self, node_id, value, state) end,
	language_changed = function(self, node_id, value, state) end,
	final           = function(self, node_id, value, state) end,
}

require("defigma.screen").register(feature)
```

Each callback runs once per node that has `custom_parameters`, so it must ignore values it does not
recognise. Implement only the moments you need — a feature that does not care about layouts simply
omits `layout_changed`.

`state` is a table owned by this feature for this screen, created in `defigma.init` and thrown away
with the screen. Features never share it and never need a namespace key.

`update` and `on_input` are deliberately not dispatched: a per-node callback every frame or every
input event is the wrong shape. A feature that needs those should subscribe to its own source.

### When each callback fires

| Callback | Fires | Node transform state |
|---|---|---|
| `init` | screen init, after gradients | as authored |
| `layout_changed` | after `<screen>.on_change_layout` | restored by Defold to the layout values |
| `language_changed` | on `polyglot.EVENT_LANGUAGE_CHANGED` | unchanged since the last hook |
| `final` | screen final, before the state is dropped | — |

The `layout_changed` distinction matters: `on_change_layout` puts static nodes back into their editor
state, so anything a feature wrote into a node transform has to be re-applied there.

## `rtl.lua`

Reacts to `{"custom_parameters":"rtl"}` by negating the node's own `scale.x` while a right-to-left
locale is active. No extra nodes are created and the hierarchy is untouched.

The authored `scale` — and, for text nodes, the authored `pivot` — is captured into `state` on `init`
and re-captured on `layout_changed`, where Defold restores nodes to their editor state. Switching
back to a left-to-right locale writes those values back, so the node returns exactly to how it was
exported.

Scale composes down the hierarchy, so a tag inside an already mirrored subtree flips back to a world
scale of `+1`. That is how artwork and text stay readable inside a mirrored container.

### Text pivots

A mirrored text node renders un-mirrored but its anchor ends up on the wrong side of the reflected
box, so a horizontal pivot is swapped while an RTL locale is active:

```text
PIVOT_W ↔ PIVOT_E     PIVOT_NW ↔ PIVOT_NE     PIVOT_SW ↔ PIVOT_SE
```

`PIVOT_CENTER`, `PIVOT_N` and `PIVOT_S` have no horizontal component and stay as authored.

### Wiring

`rtl.lua` must not depend on the game's localization module, so it learns the language from an event
and stores it inside the module:

```lua
-- collections/update/start_menu.script
defigma_rtl.init(polyglot.EVENT_LANGUAGE_CHANGED)   -- before the first set_language
```

`polyglot.set_language` triggers that event with the new language as its payload; nothing else in the
project triggers it by hand. The subscription is process-wide and is never removed. Requiring
`defigma.rtl` is also what registers the feature with `screen.lua` — no other module pulls it in.

Adding another RTL locale is one entry in `RTL_LANGUAGES`.

### Cloning RTL nodes

The exported RTL node is registered from `defigma_data`, but a clone has a generated id and is not
registered automatically. Keep the source RTL node handle, obtain its clone from the table returned
by `gui.clone_tree`, restore the authored scale, and register the generated id:

```lua
local defigma_rtl = require("defigma.rtl")

local function clone_rtl_tree(self, template, template_rtl)
	local clone_tree = gui.clone_tree(template)
	local root = assert(clone_tree[gui.get_id(template)])
	local rtl_node = assert(clone_tree[gui.get_id(template_rtl)])

	gui.set_scale(rtl_node, vmath.vector3(1, 1, 1))
	defigma_rtl.track(self, gui.get_id(rtl_node))

	return root, rtl_node
end
```

Do not depend on exported names such as `note_rtl3`: find or store the source node during template
initialization and use `gui.get_id(template_rtl)` as the `clone_tree` key.

Restoring the authored scale before `track` is required when cloning in an RTL locale. The source
node may already have `scale.x` negated; tracking that transformed scale would capture the wrong
baseline and mirror it a second time.

Unregister the generated id before deleting the cloned tree:

```lua
defigma_rtl.untrack(self, gui.get_id(rtl_node))
gui.delete_node(root)
```
