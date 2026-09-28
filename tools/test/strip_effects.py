"""Copy an exported .gui with the effects of every shape node removed (no shadows, no blur):
the diagnostic "plain shapes" variant of a benchmark.

    python3 tools/test/strip_effects.py tests/x/screen.gui tests/x/screen_plain.gui
"""
import os
import re
import sys

source, target = sys.argv[1], sys.argv[2]
text = open(source).read()
text = re.sub(r'(id: "effects"\n    type: TYPE_STRING\n    string: )".*"', r'\1"[]"', text)
name = os.path.splitext(os.path.basename(source))[0]
text = text.replace("/%s.gui_script" % name, "/%s.gui_script" % os.path.splitext(os.path.basename(target))[0])
open(target, "w").write(text)
print("wrote", target)
