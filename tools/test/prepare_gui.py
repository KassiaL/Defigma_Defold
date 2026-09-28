"""Make an exported .gui load in this test project: drop textures that are missing or unused,
raise max_nodes for stacked benchmark layers and write a defigma.screen gui_script
(--keep-script leaves the script file alone).
"""
import os, re, sys

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def exists(resource):
    return os.path.exists(os.path.join(PROJECT, resource.lstrip("/")))


def strip_missing_textures(text):
    def keep(match):
        return match.group(0) if exists(match.group(2)) else ""
    return re.sub(r'textures \{\n  name: "([^"]*)"\n  texture: "([^"]*)"\n\}\n', keep, text)


SCRIPT = """local defigma = require("defigma.screen")

function init(self)
\tdefigma.init(self, "{screen}")
end

function update(self, dt)
\tdefigma.update(self, dt)
end

function on_message(self, message_id, message, sender)
\tdefigma.on_message(self, message_id, message, sender)
end

function final(self)
\tdefigma.final(self)
end
"""


def ensure_script(text):
    match = re.search(r'^script: "([^"]*)"', text, re.M)
    if match and match.group(1):
        path = os.path.join(PROJECT, match.group(1).lstrip("/"))
        screen = os.path.splitext(os.path.basename(path))[0]
        open(path, "w").write(SCRIPT.format(screen=screen))
    return text


def strip_unused_textures(text):
    used = set(re.findall(r'\n  texture: "([^"/]+)/', text))
    return re.sub(r'textures \{\n  name: "([^"]*)"\n  texture: "[^"]*"\n\}\n', lambda m: m.group(0) if m.group(1) in used else "", text)


def set_max_nodes(text, count):
    return re.sub(r'^max_nodes: \d+', "max_nodes: %d" % count, text, flags=re.M)


args = sys.argv[1:]
keep_script = "--keep-script" in args
max_nodes = 4096
paths = [a for a in args if not a.startswith("--")]
for path in paths:
    text = open(path).read()
    text = set_max_nodes(strip_unused_textures(strip_missing_textures(text)), max_nodes)
    if not keep_script:
        text = ensure_script(text)
    open(path, "w").write(text)
    print("prepared", path)
