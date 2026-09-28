import re, sys, json
t = open(sys.argv[1]).read()
out = []
for n in t.split("\nnodes {")[1:]:
    if "TYPE_CUSTOM" not in n:
        continue
    nid = re.search(r'\n  id: "([^"]+)"', n).group(1)
    size = re.search(r'size \{\n    x: ([\d.e-]+)\n    y: ([\d.e-]+)', n)
    props = {}
    for m in re.finditer(r'custom_properties \{\n    id: "(\w+)"\n    type: (\w+)\n((?:    .*\n)+?)  \}', n):
        pid, typ, body = m.groups()
        if typ == "TYPE_STRING":
            props[pid] = json.loads(re.search(r'string: (".*")', body).group(1))
        elif typ == "TYPE_NUMBER":
            props[pid] = re.search(r'number: ([\d.e-]+)', body).group(1)
        else:
            props[pid] = " ".join(re.findall(r'[xyzw]: ([\d.e-]+)', body))
    out += [nid, props.get("shape", "rect"), props.get("corner_radius", "0 0 0 0"), props.get("fills", ""), props.get("strokes", ""), props.get("stroke_width", "0"), props.get("stroke_align", "inside"), props.get("effects", ""), props.get("path", ""), props.get("clip", ""), "%s %s" % size.groups()]
open(sys.argv[2], "w").write("\n".join(out) + "\n")
