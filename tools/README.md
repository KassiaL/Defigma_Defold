# Tools

Everything used to export the test screens, check them against Figma and measure them. Run all
commands from the project root. Python 3 with Pillow; the Figma tools need the Figma Bridge plugin
open in Figma (`~/figma_plugins/FigmaBridge`, port 8788, `BRIDGE_PORT` to change) and the Defigma
sources in `~/figma_plugins/Defigma` (`DEFIGMA` to change).

## `figma/` - export from Figma

| Script | What it does |
|---|---|
| `hot_export.py export <id>...` | Bundles the current Defigma sources with esbuild, runs the export inside the bridge plugin and writes the files into this project. No Defigma web server and no plugin reload. |
| `hot_export.py scenario <file.js>` | Runs a scenario: the body of an async function with `await exportNode(id)`; it returns `{ files }` plus any keys to print. |
| `screen_census.py <id>... [--shots dir]` | What a screen is made of: atlas instances per master with their area share, stretched instances, and what every master contains (effects with radius, gradients, bitmaps, paths, blend modes, masks), classified as `bitmap` / `heavy` / `light`. The input for *Choosing raster or vector* in `defigma/DEFIGMA.md`. |
| `scenes/build_shapes_test.js` | Builds the `shapes_test` frame (page `draft`) with every shape feature. |
| `scenes/build_divisions_gold.js` | Builds `divisions_gold_shapes`: a copy of the draft battle division screen with atlas tiles detached. |
| `scenes/build_bench_screen.js` | Builds the four `bench_*` store screen frames. |
| `scenes/build_results_screen.js` | Copies the match result screen (4575:231281) into `results_raster`, `results_current`, `results_bg_raster`, `results_vector` on page `draft`: detaches templates, unlocks locked layers, drops hidden-export metadata; the raster copy replaces the native shapes with instances of components in the section `/tests/results_screen/results_extra.atlas`. |
| `scenes/export_results_screen.js` | Adds `{"shape_nodes":true}` markers to the background and the 16 panel masters, exports the vector variant, removes the background marker, exports bg_raster, then removes every marker in `finally` and prints `markers_left` (must be `[]`), and exports current and raster. |

A scenario that changes masters must restore them in `finally` and prove it (`markers_left`):
other people work in the same Figma file.

## `test/` - make an export load here

| Script | What it does |
|---|---|
| `copy_dexfut_resources.py <gui>...` | Copies the atlases, images and fonts an exported `.gui` references from the Dexfut checkout. |
| `prepare_gui.py [--keep-script] <gui>...` | Drops textures that are missing or unused, sets `max_nodes` to 4096 (stacked benchmark layers) and writes a `defigma.screen` gui_script unless `--keep-script`. |
| `strip_effects.py <in.gui> <out.gui>` | Copy without any shape effects (no shadow, no blur): the "plain" variant, which shows what the effects cost. |

## `compare/` - accuracy against Figma

The reference is the Figma PNG export of the frame (`figma.py shot <id> --max <height>`, which is
`exportAsync` at the scale that gives that size); the candidate is an engine screenshot of the same
frame at the same pixel size (`bench/desktop.py shot`). Both are compared per pixel on the maximum
channel difference, 0-255.

| Script | What it does |
|---|---|
| `diff.py figma.png game.png out.png` | Mean, p99, max, pixels over 8 and over 24; writes the difference amplified 6x and a side-by-side `figma | game | diff`. |
| `regions.py figma.png game.png regions.json` / `--grid N` | The same per named region or per NxN block, to find where the difference is. `shapes_test_regions.json` holds the regions of `shapes_test`. |

Reading the numbers: under 1/255 mean is identical to the eye; AA edges and text rendering give
1-3; anything over 24 in a compact area is a real mismatch. Compare two engine variants of the same
screen against each other as well (for example raster vs vector): that removes what is common to
both (fonts, runtime logic) and leaves only the shape rendering.

## `geometry/` - vertex budget

| Script | What it does |
|---|---|
| `extract_shapes.py <gui> <out.txt>` | Dumps every `DefigmaShape` node's properties and size. |
| `vertex_count.cpp` | Builds the geometry of every dumped node with `commonsrc/shape_geometry.cpp` and prints vertices and build time per node and in total. Build: `g++ -O2 -std=c++17 -Idefigma/include tools/geometry/vertex_count.cpp defigma/commonsrc/shape_geometry.cpp -o vc`. |

## `bench/` - performance

| Script | What it does |
|---|---|
| `make_bench_scene.py <dir> <variant>... [--layers 1,4,8]` | Generates the variant collections and scripts, `bench_scene.collection` with one collection proxy per variant, and `bench_settings.ini` / `bench_settings_android.ini` (ASTC 4x4 like Dexfut). |
| `desktop.py build <settings>` | Builds the scene into `build/default` (debug engine). |
| `desktop.py run [--size WxH] [--out file]` | Runs the benchmark: every variant, static and moving, 1/4/8 stacked layers; prints `BENCH|CASE|...` lines (avg, p95, p99 frame time measured in Lua with `socket.gettime`). |
| `desktop.py shot <variant> <W>x<H> <out.png>` | Keeps one variant on screen and saves a screenshot at that window size. |
| `desktop.py profile <variant>:<layers>:<moving>` | Keeps one variant on screen and prints the engine profiler scopes (Remotery on port 17899). |
| `android.py build <settings>` | Debug APK for arm64-v8a and armeabi-v7a into `bench_bundles/`. |
| `android.py run [--serial S] [--no-install] [--profile] [--out file]` | Installs (`--no-install` reuses the installed build), starts, streams logcat into `build/bench_logs/android_logcat.txt`, waits for `BENCH|DONE`, prints the lines; `--profile` forwards Remotery and prints the scopes of every variant during its hold window. MIUI asks to confirm a USB install on the phone; the run stops if it is not confirmed. |

The runner loads the variants one by one, so only one is in memory; it stacks the screen with
`gui.clone_tree` to multiply the load (the "layers" column) and moves the layers for the moving
case. Frame time on a debug build includes the engine overhead of a debug build; compare variants
with each other, not with a release budget.
