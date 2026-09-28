import os, re, shutil, sys

DEXFUT = "/home/sergey/defold_projects/Dexfut"
PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def copy_resource(resource):
    source = os.path.join(DEXFUT, resource.lstrip("/"))
    target = os.path.join(PROJECT, resource.lstrip("/"))
    if not os.path.exists(source):
        print("missing in Dexfut:", resource)
        return None
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copyfile(source, target)
    return target


def copy_atlas(atlas):
    target = copy_resource(atlas)
    if target:
        for image in re.findall(r'image: "([^"]+)"', open(target).read()):
            copy_resource(image)


def copy_font(font):
    target = copy_resource(font)
    if target:
        for ttf in re.findall(r'^font: "([^"]+)"', open(target).read(), re.M):
            copy_resource(ttf)


for gui in sys.argv[1:]:
    text = open(gui).read()
    for atlas in re.findall(r'texture: "(/[^"]+\.atlas)"', text):
        copy_atlas(atlas)
    for font in re.findall(r'font: "(/[^"]+\.font)"', text):
        copy_font(font)
    print("copied resources for", gui)
