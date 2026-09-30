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
| `scenes/arcs_test.js` | Builds `arcs_test` on page `draft` (round and square ends, pies, donut, partial corner radius, tiny and wide sweeps, elliptical and translucent arcs) and exports it as shape nodes. |
| `scenes/arcs_fx_test.js` | Builds `arcs_fx_test` on page `draft` (glow, offset / spread / pie shadows, inside / center / outside strokes, layer blur, an elliptical arc with everything, a translucent arc, a full ring) and exports it to `tests/arcs_fx_test`. |
| `scenes/glass_test.js` | Builds `glass_test` on page `draft` (a glass tile with a rim stroke, a transparent `glass_sheen` overlay, three blurred glints and a spinner arc) and exports it to `tests/glass_test`; `glass_fx.lua` animates it (sheen sweep via `set_paints`, glints running along the rim, spinner `set_sweep`). Run: `desktop.py build tests/glass_test/settings.ini`, then the engine. |
| `scenes/panels_screen.js` | Builds `panels_raster` / `panels_vector` on page `draft` (the `my_profile` background and its five visible panels) and exports both; `panels_vector` detaches its panel instances. |
| `scenes/export_results_screen.js` | Detaches the instances of the 16 panel masters (and of the background for `results_vector`) inside the vector copies, so they export as shape nodes while the masters stay untouched, then exports vector, bg_raster, current, raster and the extra atlas. |

A scenario never changes masters: other people work in the same Figma file. Detach instances in
the scenario's own copies instead.

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

## `memcheck/` - memory safety of the shape code

`memcheck.cpp` links `commonsrc/shape_geometry.cpp` and `pluginsrc/plugin.cpp` (`stub/dmsdk/sdk.h`
stands in for the SDK) and drives them with dumps from `geometry/extract_shapes.py`:

| Mode | What it does |
|---|---|
| `real <dump>...` | Builds every dumped node directly and through `DefigmaShape_Build` + `DefigmaShape_CopyVertices` into a buffer of exactly the returned size; fails if a node does not parse, the two results differ, or the vertices are not whole finite triangles. |
| `dump <dump>...` | The same, printing vertex count and a hash of the vertex bytes per node: diff it before and after a geometry change to prove valid output did not move. |
| `fuzz <iterations> <seed> <dump>...` | Edge cases (truncated and deeply nested JSON, missing keys, short arrays, 1 MB strings) in every JSON property, then random shapes (NaN / inf / negative / huge sizes, radii and stroke widths, up to 3000 stops, pieces and clips over 96 points, hundreds of edges) and byte-level mutations of the real nodes. |
| `threads <threads> <rounds> <dump>...` | Calls the plugin API from several threads at once and compares every result with a single-threaded build. |

`run.sh` extracts every `.gui` under `tests/` into `build/memcheck/shapes/`, builds three binaries
into `build/memcheck/` and runs: `real`, `fuzz` and `threads` under AddressSanitizer +
UndefinedBehaviorSanitizer (with `float-cast-overflow`, any report aborts), `threads` under
ThreadSanitizer, and `real`, a shorter `fuzz` and `threads` under `valgrind --leak-check=full
--error-exitcode=1`. It stops at the first failure and prints `memcheck: all passed` at the end.
`ITERATIONS` (20000), `VALGRIND_ITERATIONS` (1500), `SEED` (1) and `THREADS` (8) override the
defaults. About two minutes; it does not touch the Defold build.

`engine_leak.py` runs `DefigmaShape` in the engine. `tests/leak_stress` is a copy of
`results_vector.gui` (168 shape nodes, an empty `stress` layout added) behind a collection proxy;
every cycle loads it, runs `leak.frames` frames and unloads it. Every frame it resizes all shape
nodes (geometry rebuild), toggles every second one, every 5 frames deletes the previous
`gui.clone_tree` copy of the whole screen and clones it again (resizing the copies too), every
50 frames switches the layout with `gui.set_layout` (`SetNodeDesc` again on every node). After
each load and unload it prints `LEAK|LOADED|` / `LEAK|CYCLE|<n>|lua_kb|mem_kb|rss_kb` (Lua after
a full collect, `profiler.get_memory_usage()`, `/proc/self/statm`), then leaves with `sys.exit`.

| Command | What it does |
|---|---|
| `build [--root DIR] [--variant debug\|headless\|release]` | Builds into `build/leak/default` and `build/leak/<variant>/x86_64-linux/dmengine`; `build/default` is left alone. |
| `run [--variant V] [--cycles 40] [--frames 300] [--ops size,clone,enable,layout\|none]` | Runs and prints start, after warm-up (cycle 6), end and the least-squares slope per cycle of each memory column. `--ops` picks the stress operations, `none` only loads and unloads. |
| `run ... --tool heaptrack\|valgrind [--snapshot-exit]` | Runs the unstripped engine under heaptrack (prints the summary and the leak backtraces through `dmDefigma` / `defigma::`) or `valgrind --leak-check=full` (use `--variant headless --cycles 3 --frames 60`: no GL driver, about 40 s). `--snapshot-exit` leaves with `os.exit`, so heaptrack counts everything alive after the last unload as leaked (static destructors still run). |

`--root` builds and runs a copy of the project (`rsync -a --exclude=build --exclude=.git`), so a
snapshot can be tested while the sources are being edited. Results on 1.13.1, 60 cycles x 300
frames: release RSS +62 KB/cycle with every operation, +33 KB/cycle with `none`; debug +1.8 MB
and +0.39 MB. The debug growth is the engine, not the extension: `dmGui::CloneNode` names every
clone `__node<N>` and a debug build keeps each name in the reverse hash table, and the basic
profiler allocates about 295 KB of thread data for every new resource load thread. heaptrack and
valgrind find nothing left by the extension at exit.

## `bench/` - performance

| Script | What it does |
|---|---|
| `make_bench_scene.py <dir> <variant>... [--layers 1,4,8] [--display 1080x2300]` | Generates the variant collections and scripts, `bench_scene.collection` with one collection proxy per variant, and `bench_settings.ini` / `bench_settings_android.ini` (ASTC 4x4 like Dexfut); `--display` sets the window and GUI reference size (the exported frame size). |
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
