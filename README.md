# Defigma Extension for Defold

Runtime half of the Defigma Figma plugin: the `DefigmaShape` custom GUI node (vector rectangles,
ellipses, arcs and paths with gradients, strokes, shadows and blur), the `defigma_shape` Lua API,
text gradients and text shadows, and right-to-left mirroring.

## Installation

Add this dependency to your game.project file:

```text
https://github.com/KassiaL/Defigma/archive/master.zip
```

Install the Defigma Figma plugin and export your screens into the project.

## Usage

Shapes need no code: every exported rectangle, ellipse, arc and vector is drawn by the extension from
its custom properties. The generated `.gui_script` of a screen calls `defigma.screen`, which applies
the text gradients and text shadows of the `defigma_data` node:

```lua
local defigma = require("defigma.screen")

function init(self)
    defigma.init(self, "menu")
end

function update(self, dt)
    defigma.update(self, dt)
end
```

A progress ring is a Figma arc ellipse; the game changes its sweep:

```lua
defigma_shape.set_sweep(gui.get_node("progress"), 100 * completed / total)
```

The whole runtime, the measured costs and the risks: [defigma/DEFIGMA.md](defigma/DEFIGMA.md).

## Shape Nodes

Every rectangle, ellipse, arc, vector and frame visual outside an atlas section
becomes a `DefigmaShape` custom GUI node: gradients with up to 64 stops, strokes, per-corner
radii, drop shadows, layer blur and Figma arcs (start, sweep, ratio, rounded ends; changed at run
time with `defigma_shape.set_arc`) in one node, drawn by the native extension without any Lua and
batched into one draw call per run of shape nodes. The editor shows the preview and lets you resize
the node like a box. Details: [defigma/DEFIGMA.md](defigma/DEFIGMA.md#shape-nodes).

Requires Defold 1.13.1 or newer (custom GUI node properties).

## Test Project

This repository is also the test bed for the shape nodes:

- `tests/shapes_test/` - one frame with every shape feature, exported from the Figma frame
  `shapes_test` on the `draft` page of `DEXFUT_TEAM`;
- `tests/divisions_gold/` - a copy of the Dexfut draft battle division screen with the atlas tiles
  (`stage_bg`, `bg_i`, panels, buttons) detached into vector shapes;
- `tests/bench/` - 200 moving gradient rounded rectangles as material nodes (`bench.mode=old`)
  and as shape nodes (`bench.mode=new`);
- `tests/bench_screen/` - a store screen from the Figma frames `bench_raster`, `bench_material`,
  `bench_vector`, `bench_hybrid` (page `draft`) in four variants, loaded one by one through
  collection proxies by `bench_runner.script`, which measures 1, 4 and 8 stacked layers, static and
  moving, and prints `BENCH|...` lines (desktop log, `adb logcat` on Android). Build with
  `--settings tests/bench_screen/bench_settings.ini` (`bench_settings_android.ini` adds the ASTC
  texture profile); `--config=bench.hold=vector:1:1` keeps one variant on screen for the profiler.
  Results are in [defigma/DEFIGMA.md](defigma/DEFIGMA.md#cost);
- `tests/results_screen/` - the Dexfut match result screen (Figma 4575:231281) in the variants
  `results_raster` (atlases only, no shape node), `results_current` (atlases as in Dexfut, the
  native shapes as shape nodes), `results_bg_raster` (background image, panels as shape nodes),
  `results_vector` (everything but the emblems as shape nodes) and their `_plain` copies without
  effects. The vector copies detach the instances of the panel masters, the masters stay untouched;
- `tests/arcs_test/` - every Figma arc variant (`tools/figma/scenes/arcs_test.js`) and `arcs_api`, the
  same screen driven through `defigma_shape.set_arc` / `get_arc`;
- `tests/panels_screen/` - the `my_profile` background with its five panels as slice9 images and as
  shape nodes, plus a diagnostic copy with one fill; built and exported by
  `tools/figma/scenes/panels_screen.js`;
- `tools/` - export, accuracy, vertex count and benchmark scripts, see [tools/README.md](tools/README.md).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
