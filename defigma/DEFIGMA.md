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
| `gradient.lua` | Linear / radial / drop-shadow application and transform math. |
| `gradient_nodes.lua` | Registry of gradient nodes owned by one screen or widget: what is refreshed every frame and what on demand. |
| `text_shadow.lua` | Writes the offset and the blur of every text shadow into its node. |
| `materials/` | Matching materials and shaders; `*.glsl` are the parts they share through `#include`. |

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

The gradient shaders need the node rect (image gradients) or the inverse node transform (text
gradients) as a per-node material constant. Both are functions of the node's **world transform**, so
they have to be re-applied whenever that transform changes — a node moved by a scroll, an animation,
a window resize or a layout change would otherwise keep rendering with a stale gradient.

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
defigma.set_node_updating(self, "bar_fill", false)  -- one screen node
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
