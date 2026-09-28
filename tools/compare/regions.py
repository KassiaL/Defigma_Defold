"""Per-region version of diff.py: where on the screen the difference is.

    python3 tools/compare/regions.py figma.png game.png regions.json
    python3 tools/compare/regions.py figma.png game.png --grid 48

regions.json maps a name to [x0, y0, x1, y1] in pixels of the images; --grid prints the mean
difference of every NxN block instead, which finds the hot spots without knowing the layout.
"""
import json
import sys

from PIL import Image, ImageChops

a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
difference = ImageChops.difference(a, b)


def stats(box):
    values = sorted(max(p) for p in difference.crop(box).getdata())
    return sum(values) / len(values), values[int(len(values) * 0.99)], values[-1]


if sys.argv[3] == "--grid":
    size = int(sys.argv[4])
    for y in range(0, a.height, size):
        print("%5d " % y + " ".join("%5.1f" % stats((x, y, min(x + size, a.width), min(y + size, a.height)))[0] for x in range(0, a.width, size)))
else:
    for name, box in json.load(open(sys.argv[3])).items():
        mean, p99, top = stats(tuple(box))
        print("%-20s mean %6.2f p99 %4d max %4d" % (name, mean, p99, top))
