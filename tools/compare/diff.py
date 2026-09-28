"""Pixel difference between a Figma export and an engine screenshot of the same size.

    python3 tools/compare/diff.py figma.png game.png out.png

Prints the mean, 99th percentile and maximum of the per-pixel maximum channel difference (0-255)
and how many pixels differ by more than 8 and 24 levels. Writes out.png (difference amplified 6x)
and out_side.png (figma | game | difference).
"""
import statistics
import sys

from PIL import Image, ImageChops

a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
if a.size != b.size:
    sys.exit("sizes differ: %s vs %s" % (a.size, b.size))
difference = ImageChops.difference(a, b)
values = sorted(max(p) for p in difference.getdata())
print("mean", round(statistics.mean(values), 3), "p99", values[int(len(values) * 0.99)], "max", values[-1],
      "over8", sum(1 for v in values if v > 8), "over24", sum(1 for v in values if v > 24))
amplified = difference.point(lambda v: min(255, v * 6))
amplified.save(sys.argv[3])
side = Image.new("RGB", (a.width * 3, a.height))
side.paste(a, (0, 0))
side.paste(b, (a.width, 0))
side.paste(amplified, (a.width * 2, 0))
side.save(sys.argv[3].replace(".png", "_side.png"))
