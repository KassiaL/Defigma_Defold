# Defigma Extension for Defold

Defigma Extension adds advanced linear and radial gradient support to Defold projects using assets exported from the Defigma Figma Plugin.

## Installation

Add this dependency to your game.project file:

```text
https://github.com/KassiaL/Defigma/archive/master.zip
```

Make sure you've installed the Defigma Figma Plugin and have exported your design to your Defold project.

## Usage

Follow these steps to integrate gradients in your Defold project:

```lua
function init(self)
    -- 1. Import Defigma-generated data
    local menu_defigma_data = require("collections.menu.menu_defigma")

    -- 2. Import Defigma extension module
    local gradient = require("defigma.gradient")

    -- 3. Apply gradients (call in init)
    gradient.apply_all(menu_defigma_data)
end

function update(self, dt)
    -- 4. Update gradient transformations (call in update)
    gradient.apply_all_transform(menu_defigma_data)
end
```

## Advanced Usage

For static elements that don't change position, you can optimize by calling the transform function only when needed:

```lua
function on_position_changed(self)
    local gradient = require("defigma.gradient")
    local menu_defigma_data = require("collections.menu.menu_defigma")
    gradient.apply_all_transform(menu_defigma_data)
end
```

## Shape Nodes

Export a screen (or mark any frame or master component inside it) with `{"shape_nodes":true}` and every rectangle, ellipse, vector and frame visual
becomes a `DefigmaShape` custom GUI node: gradients with any number of stops, strokes, per-corner
radii, drop shadows and layer blur in one node, drawn by the native extension without any Lua and
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
  effects. Built from masters marked with `{"shape_nodes":true}` for the export only; the markers
  are removed from Figma afterwards;
- `tools/` - export, accuracy, vertex count and benchmark scripts, see [tools/README.md](tools/README.md).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
