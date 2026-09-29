"""Generate a benchmark scene for exported screen variants.

    python3 tools/bench/make_bench_scene.py tests/results_screen results_raster results_current ...
        [--layers 1,2,4] [--display 1080x2300]

For every variant <dir>/<variant>.gui it writes <variant>.gui_script (tests/bench_common/bench_gui.lua)
and <variant>.collection, then bench_scene.collection with tests/bench_common/bench_runner.script
(one collection proxy per variant), bench_runner.script and the build settings
bench_settings.ini (desktop, uncompressed textures) and bench_settings_android.ini (ASTC 4x4 like
Dexfut). The runner prints BENCH|LOAD|..., BENCH|CASE|..., BENCH|DONE, then keeps every variant
on screen for 30 s (BENCH|HOLD|<variant>) for the profiler.
"""
import os
import re
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

args = sys.argv[1:]
layers = [1, 4, 8]
if "--layers" in args:
    index = args.index("--layers")
    layers = [int(v) for v in args[index + 1].split(",")]
    del args[index:index + 2]
display = "1080x2300"
if "--display" in args:
    index = args.index("--display")
    display = args[index + 1]
    del args[index:index + 2]
folder = args[0].rstrip("/")
variants = args[1:]
resource_folder = "/" + folder

GUI_SCRIPT = '''local bench = require("tests.bench_common.bench_gui")

function init(self)
\tbench.init(self, "{variant}")
end

function update(self, dt)
\tbench.update(self, dt)
end

function on_message(self, message_id, message, sender)
\tbench.on_message(self, message_id, message, sender)
end

function final(self)
\tbench.final(self)
end
'''

COLLECTION = '''name: "{variant}"
scale_along_z: 0
embedded_instances {{
  id: "screen"
  data: "components {{\\n"
  "  id: \\"gui\\"\\n"
  "  component: \\"{folder}/{variant}.gui\\"\\n"
  "}}\\n"
  ""
}}
'''

PROXY = '''  "embedded_components {{\\n"
  "  id: \\"{variant}\\"\\n"
  "  type: \\"collectionproxy\\"\\n"
  "  data: \\"collection: \\\\\\"{folder}/{variant}.collection\\\\\\"\\\\n"
  "\\"\\n"
  "}}\\n"
'''

SETTINGS = '''[bootstrap]
main_collection = {folder}/bench_scene.collectionc

[display]
width = {width}
height = {height}
vsync = 0
update_frequency = 0

[android]
package = com.defigma.bench

[project]
title = defigma_bench
'''

ASTC = '''
[graphics]
texture_profiles = /tests/bench_common/bench_astc.texture_profiles
'''


def write(name, text):
    path = os.path.join(PROJECT, folder, name)
    open(path, "w").write(text)
    print("wrote", os.path.relpath(path, PROJECT))


for variant in variants:
    write(variant + ".gui_script", GUI_SCRIPT.format(variant=variant))
    write(variant + ".collection", COLLECTION.format(variant=variant, folder=resource_folder))
    gui = os.path.join(PROJECT, folder, variant + ".gui")
    text = open(gui).read()
    text = re.sub(r'^script: "[^"]*"', 'script: "%s/%s.gui_script"' % (resource_folder, variant), text, flags=re.M)
    open(gui, "w").write(text)

template = open(os.path.join(PROJECT, "tests/bench_common/bench_runner.script.template")).read()
cases = ["{ layers = 1, moving = false }"] + ["{ layers = %d, moving = true }" % count for count in layers]
runner = template.replace("__VARIANTS__", "{ " + ", ".join('"%s"' % v for v in variants) + " }").replace("__CASES__", "{\n\t" + ",\n\t".join(cases) + ",\n}")
write("bench_runner.script", runner)
scene = 'name: "bench_scene"\nscale_along_z: 0\nembedded_instances {\n  id: "runner"\n  data: "components {\\n"\n  "  id: \\"script\\"\\n"\n  "  component: \\"%s/bench_runner.script\\"\\n"\n  "}\\n"\n' % resource_folder
scene += "".join(PROXY.format(variant=v, folder=resource_folder) for v in variants)
scene += '  ""\n}\n'
write("bench_scene.collection", scene)
width, height = display.split("x")
write("bench_settings.ini", SETTINGS.format(folder=resource_folder, width=width, height=height))
write("bench_settings_android.ini", SETTINGS.format(folder=resource_folder, width=width, height=height) + ASTC)
