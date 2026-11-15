"""Frame Simulator screenshots as device mockups for the README.

Usage: python3 scripts/frame-screenshots.py <raw-shots-dir> docs/screenshots

The raw shots are full-size `xcrun simctl io booted screenshot` PNGs from an iPhone 17 Pro
with the status bar overridden to 9:41, named as in SHOTS below. Needs Pillow (`pip3 install pillow`); the app itself stays free of
third-party dependencies.
"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)

BG = (0xE8, 0xE7, 0xE3)
INK = (0x12, 0x12, 0x12)
SECONDARY = (0x5A, 0x59, 0x54)
SIGNAL = (0x1F, 0x3B, 0xD6)
MONO = "/System/Library/Fonts/SFNSMono.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"

SHOTS = [
    ("01-recipes", "001", "RECIPES", "Your film recipes, filed like an archive."),
    ("02-recipe", "002", "RECIPE", "Every setting on one card, one key to push it."),
    ("03-camera", "003", "CAMERA", "The custom slots C1–C7, read over USB."),
    ("04-darkroom", "004", "DARKROOM", "The camera develops your RAW files."),
    ("05-lighttable", "005", "LIGHT TABLE", "Import photos straight from the card."),
]

BEZEL = 34
SCREEN_RADIUS = 170


def device(path):
    shot = Image.open(path).convert("RGB")
    w, h = shot.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], SCREEN_RADIUS, fill=255)
    W, H = w + 2 * BEZEL, h + 2 * BEZEL
    dev = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(dev)
    d.rounded_rectangle([0, 0, W - 1, H - 1], SCREEN_RADIUS + BEZEL, fill=(0x1A, 0x1A, 0x19, 255))
    d.rounded_rectangle([3, 3, W - 4, H - 4], SCREEN_RADIUS + BEZEL - 3, outline=(0x3A, 0x3A, 0x38, 255), width=3)
    dev.paste(shot, (BEZEL, BEZEL), mask)
    return dev


def shadow(size, radius):
    W, H = size
    pad = 120
    s = Image.new("RGBA", (W + 2 * pad, H + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(s).rounded_rectangle([pad, pad + 30, pad + W, pad + H + 30], radius, fill=(0, 0, 0, 70))
    return s.filter(ImageFilter.GaussianBlur(45)), pad


def tile(name, number, label, caption):
    dev = device(os.path.join(SRC, name + ".png"))
    W, H = dev.size
    margin_x, top, text_h = 140, 120, 330
    canvas = Image.new("RGB", (W + 2 * margin_x, top + H + text_h), BG)
    sh, pad = shadow((W, H), SCREEN_RADIUS + BEZEL)
    canvas.paste(sh, (margin_x - pad, top - pad), sh)
    canvas.paste(dev, (margin_x, top), dev)
    d = ImageDraw.Draw(canvas)
    y = top + H + 80
    mono = ImageFont.truetype(MONO, 46)
    d.text((margin_x, y), number, font=mono, fill=SIGNAL)
    nx = margin_x + d.textlength(number + "  ", font=mono)
    d.text((nx, y), label, font=mono, fill=INK)
    sans = ImageFont.truetype(SANS, 54)
    d.text((margin_x, y + 82), caption, font=sans, fill=SECONDARY)
    return canvas


tiles = []
for spec in SHOTS:
    t = tile(*spec)
    tiles.append(t)
    small = t.resize((t.width // 2, t.height // 2), Image.LANCZOS)
    small.save(os.path.join(OUT, spec[0] + ".png"), optimize=True)

# One overview strip with all screens side by side.
gap = 0
strip_w = sum(t.width for t in tiles) + gap * (len(tiles) - 1)
strip_h = tiles[0].height
head = 260
strip = Image.new("RGB", (strip_w + 160, strip_h + head + 60), BG)
d = ImageDraw.Draw(strip)
d.text((220, 110), "DARKSLIDE", font=ImageFont.truetype(MONO, 72), fill=INK)
d.text((220 + d.textlength("DARKSLIDE   ", font=ImageFont.truetype(MONO, 72)), 110),
       "FILM RECIPES · CUSTOM SLOTS · DARKROOM · LIGHT TABLE",
       font=ImageFont.truetype(MONO, 72), fill=SECONDARY)
x = 80
for t in tiles:
    strip.paste(t, (x, head))
    x += t.width + gap
overview = strip.resize((strip.width // 3, strip.height // 3), Image.LANCZOS)
overview.save(os.path.join(OUT, "overview.png"), optimize=True)
print("ok", overview.size)
