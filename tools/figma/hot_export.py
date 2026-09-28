"""Run the current Defigma exporter sources inside the open Figma Bridge plugin and write the
exported files into this project, without the Defigma web server.

    python3 tools/figma/hot_export.py export <node_id> [<node_id> ...]
    python3 tools/figma/hot_export.py scenario tools/figma/scenes/<scene>.js

A scenario is the body of an async function. It can call `await exportNode(id)`, which returns
the exported files, and must return `{ files }` (it may add more keys, they are printed).
"""
import base64
import json
import os
import subprocess
import sys
import tempfile

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BRIDGE = os.environ.get("FIGMA_BRIDGE", os.path.expanduser("~/figma_plugins/FigmaBridge"))
DEFIGMA = os.environ.get("DEFIGMA", os.path.expanduser("~/figma_plugins/Defigma"))
PORT = os.environ.get("BRIDGE_PORT", "8788")
TIMEOUT = os.environ.get("BRIDGE_TIMEOUT", "600")
PNG_END = b"IEND\xaeB`\x82"

PRELUDE = """
const __exportNode = async (id) => {
  const node = await figma.getNodeByIdAsync(id)
  if (!node) throw new Error("node not found: " + id)
  const result = await __hot_defigma.export_defigma_nodes([node], { require_path_to_screen: true })
  if (result.kind !== "export") throw new Error(JSON.stringify(result))
  const files = []
  for (const data of result.export_data) {
    for (const file of data.exports) {
      if (typeof file.data === "string") files.push({ folder: data.folder_path, name: file.name, data: file.data })
      else files.push({ folder: data.folder_path, name: file.name, base64: figma.base64Encode(file.data) })
    }
  }
  return files
}
const exportNode = __exportNode
"""


def bundle(work):
    entry = os.path.join(work, "entry.ts")
    open(entry, "w").write('export { export_defigma_nodes } from "%s/public_api"\n' % DEFIGMA)
    out = os.path.join(work, "bundle.js")
    script = "require('esbuild').buildSync({entryPoints:[%s], bundle:true, format:'iife', globalName:'__hot_defigma', target:'es2017', outfile:%s, logLevel:'error'})" % (json.dumps(entry), json.dumps(out))
    subprocess.run(["node", "-e", script], cwd=BRIDGE, check=True)
    return open(out).read()


def run_job(code, work):
    path = os.path.join(work, "job.js")
    open(path, "w").write(code)
    out = subprocess.run(["python3", "figma.py", "--port", PORT, "run", path, "--timeout", TIMEOUT], cwd=BRIDGE, capture_output=True, text=True)
    text = out.stdout.strip()
    try:
        return json.loads(text)
    except ValueError:
        sys.exit("bridge job failed:\n%s\n%s" % (text[:4000], out.stderr[:2000]))


def write_files(files):
    for f in files:
        folder = os.path.join(PROJECT, f["folder"].lstrip("/"))
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, f["name"])
        if "base64" in f:
            data = base64.b64decode(f["base64"])
            if path.endswith(".png") and not data.endswith(PNG_END):
                sys.exit("truncated png: " + path)
            open(path, "wb").write(data)
        else:
            data = f["data"]
            open(path, "w").write(data)
        print("wrote", os.path.relpath(path, PROJECT), len(data))


def main():
    mode = sys.argv[1]
    work = tempfile.mkdtemp(prefix="defigma_export_")
    code = bundle(work) + PRELUDE
    if mode == "export":
        for node_id in sys.argv[2:]:
            result = run_job(code + "return JSON.stringify({ files: await exportNode(%s) })" % json.dumps(node_id), work)
            write_files(result["files"])
    elif mode == "scenario":
        body = open(sys.argv[2]).read()
        result = run_job(code + "const __result = await (async () => {\n" + body + "\n})()\nreturn JSON.stringify(__result)", work)
        write_files(result.pop("files"))
        print(json.dumps(result, indent=1))
    else:
        sys.exit(__doc__)


main()
