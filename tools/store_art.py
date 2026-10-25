"""Generates the Wong logo and every Steam store/library image at exact sizes.

    python3 tools/store_art.py [out_dir]     (needs Pillow + numpy)

Everything is drawn procedurally in the Neon Arcade palette (scripts/vfx/palette.gd)
so the art always matches the game. Output defaults to ../pong-graphics/steam/.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "art", "font.ttf")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "pong-graphics", "steam")

NAME = "WONG"
BG = (7, 7, 15)
P1 = (0, 229, 255)
P2 = (255, 43, 214)
WALL = (230, 230, 255)
ACCENT = (255, 225, 77)


def f(c, k=1.0):
    return np.array(c, dtype=np.float32) / 255.0 * k


# --- Glow compositing (float RGB, values above 1 bloom) -------------------------

class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.base = np.zeros((h, w, 3), np.float32)
        self.base[:] = f(BG)
        self.emit = Image.new("RGB", (w, h))  # emissive layer, blurred into glow
        self.ed = ImageDraw.Draw(self.emit)

    def layer(self):
        img = Image.new("RGB", (self.w, self.h))
        return img, ImageDraw.Draw(img)

    def add(self, img, k=1.0, glow=True):
        a = np.asarray(img, np.float32) / 255.0 * k
        self.base += a
        if glow:
            self.emit = Image.fromarray(np.clip(np.asarray(self.emit, np.float32) + a * 255 / max(k, 1), 0, 255).astype(np.uint8))

    def over(self, img_rgba):
        a = np.asarray(img_rgba, np.float32) / 255.0
        self.base = self.base * (1 - a[..., 3:]) + a[..., :3] * a[..., 3:]

    def finish(self, glow_scale, strength=1.0):
        out = self.base.copy()
        for r, k in ((0.004, 0.9), (0.012, 0.7), (0.035, 0.5)):
            rad = max(1.0, r * glow_scale)
            b = np.asarray(self.emit.filter(ImageFilter.GaussianBlur(rad)), np.float32) / 255.0
            out += b * k * strength
        out = 1.0 - np.exp(-out * 1.15)  # soft tonemap keeps highlights from clipping flat
        out = out / (1.0 - math.exp(-1.15 * 1.6))
        return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


# --- Scene pieces -------------------------------------------------------------

def grid(cv, horizon, s):
    img, d = cv.layer()
    w, h = cv.w, cv.h
    col = (40, 26, 90)
    vx = w / 2
    for i in range(-24, 25):
        x0 = vx + i * 220 * s
        d.line([(vx + i * 6 * s, horizon), (x0, h)], fill=col, width=max(1, int(2 * s)))
    y, step = horizon, 6 * s
    while y < h:
        d.line([(0, y), (w, y)], fill=col, width=max(1, int(2 * s)))
        step *= 1.28
        y += step
    # fade the floor toward the horizon
    a = np.asarray(img, np.float32)
    ys = np.arange(h, dtype=np.float32)[:, None]
    fade = np.clip((ys - horizon) / max(1, (h - horizon)), 0, 1) ** 0.8
    cv.add(Image.fromarray((a * fade[..., None]).astype(np.uint8)), 1.0, glow=False)
    # sky: faint magenta haze on the horizon
    sky = np.zeros((h, w, 3), np.float32)
    dist = np.abs(ys - horizon) / (0.35 * h)
    sky += f((60, 10, 70)) * np.exp(-dist ** 2)[..., None]
    cv.base += sky


def rect(cv, box, col, k=1.8, core=True):
    img, d = cv.layer()
    d.rectangle(box, fill=col)
    cv.add(img, k)
    if core:
        x0, y0, x1, y1 = box
        cw = (x1 - x0) * 0.34
        cx = (x0 + x1) / 2
        img, d = cv.layer()
        c2 = tuple(int(255 * 0.6 + v * 0.4) for v in col)
        d.rectangle((cx - cw / 2, y0 + cw, cx + cw / 2, y1 - cw), fill=c2)
        cv.add(img, 0.5, glow=False)


def trail(cv, pts, col, size):
    """Ball trail along a polyline, fading and shrinking toward its tail."""
    img, d = cv.layer()
    dense = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(2, int(math.hypot(x1 - x0, y1 - y0) / (size * 0.25)))
        dense += [(x0 + (x1 - x0) * t / n, y0 + (y1 - y0) * t / n) for t in range(n)]
    dense.append(pts[-1])
    n = len(dense)
    for i, (x, y) in enumerate(dense):
        k = (i + 1) / n  # 0 at tail, 1 at ball
        sz = size * (0.25 + 0.75 * k)
        c = tuple(int(v * k ** 1.6) for v in col)
        d.rectangle((x - sz / 2, y - sz / 2, x + sz / 2, y + sz / 2), fill=c)
    cv.add(img, 1.3)


def sparks(cv, x, y, dir_deg, col, s, n=26, seed=1):
    rng = np.random.default_rng(seed)
    img, d = cv.layer()
    for _ in range(n):
        a = math.radians(dir_deg + rng.uniform(-70, 70))
        r = rng.uniform(20, 160) * s
        sz = rng.uniform(3, 7) * s
        k = 1 - r / (170 * s)
        c = tuple(int(v * (0.4 + 0.6 * k)) for v in col)
        px, py = x + math.cos(a) * r, y + math.sin(a) * r
        d.rectangle((px - sz / 2, py - sz / 2, px + sz / 2, py + sz / 2), fill=c)
    cv.add(img, 1.6)


def scene(w, h, inset=0.07, paddle_h=0.26, ball=(0.62, 0.42), floor=0.64, s=None, seed=1, walls=True):
    """The key-art moment: cyan just returned the ball off the top wall toward magenta."""
    s = s or h / 1080
    cv = Canvas(w, h)
    grid(cv, floor * h, s)
    pw, ph = 26 * s * 1.4, paddle_h * h
    lx, rx = inset * w, w - inset * w
    ly, ry = h * 0.58, h * 0.36
    if walls:
        img, d = cv.layer()
        t = max(2, 8 * s)
        d.rectangle((0, 0, w, t), fill=WALL)
        d.rectangle((0, h - t, w, h), fill=WALL)
        cv.add(img, 0.9)
    bx, by = ball[0] * w, ball[1] * h
    bounce = (lx + (bx - lx) * 0.42, 10 * s)
    bs = 26 * s * 1.4
    trail(cv, [(lx + pw, ly + ph * 0.1), bounce, (bx, by)], P1, bs)
    sparks(cv, bounce[0], bounce[1] + 6 * s, 90, WALL, s, 18, seed)
    sparks(cv, lx + pw, ly + ph * 0.1, 0, P1, s, 22, seed + 1)
    rect(cv, (lx - pw / 2, ly - ph / 2, lx + pw / 2, ly + ph / 2), P1)
    rect(cv, (rx - pw / 2, ry - ph / 2, rx + pw / 2, ry + ph / 2), P2)
    img, d = cv.layer()
    d.rectangle((bx - bs / 2, by - bs / 2, bx + bs / 2, by + bs / 2), fill=(255, 255, 255))
    cv.add(img, 2.0)
    return cv, s


# --- Logo ---------------------------------------------------------------------

def logo_rgba(height, glow=True, pad=0.35):
    """WONG wordmark: cyan-to-magenta gradient, offset magenta shadow, neon glow.
    Returns an RGBA image whose glyphs are `height` px tall."""
    font = ImageFont.truetype(FONT, int(height * 1.38))
    x0, y0, x1, y1 = font.getbbox(NAME)
    tw, th = x1 - x0, y1 - y0
    p = int(height * pad)
    w, h = tw + p * 2, th + p * 2
    mask = Image.new("L", (w, h))
    ImageDraw.Draw(mask).text((p - x0, p - y0), NAME, font=font, fill=255)
    m = np.asarray(mask, np.float32) / 255.0

    xs = np.linspace(0, 1, w, dtype=np.float32)[None, :, None]
    xs = np.clip((xs - p / w) / (tw / w), 0, 1)
    grad = f(P1) * (1 - xs) + f(P2) * xs
    shift = int(height * 0.06)
    shadow = np.zeros_like(m)
    shadow[shift:, shift:] = m[:-shift, :-shift]
    shadow *= 1 - m

    rgb = np.zeros((h, w, 3), np.float32)
    a = np.zeros((h, w), np.float32)
    if glow:
        g = Image.fromarray((m * 255).astype(np.uint8))
        halo = np.zeros((h, w, 3), np.float32)
        for r, k in ((0.05, 0.9), (0.16, 0.55)):
            b = np.asarray(g.filter(ImageFilter.GaussianBlur(height * r)), np.float32)[..., None] / 255.0
            halo += b * grad * k
        ha = np.clip(halo.max(axis=2), 0, 1)
        rgb += halo
        a = np.maximum(a, ha)
    sh_col = f((110, 10, 95))
    rgb = rgb * (1 - shadow[..., None]) + sh_col * shadow[..., None]
    a = np.maximum(a, shadow)
    # glyph face: gradient with a bright inner highlight
    face = grad * 0.55 + 0.45
    rgb = rgb * (1 - m[..., None]) + face * m[..., None]
    a = np.maximum(a, m)
    # straight (unpremultiplied) alpha
    out = np.zeros((h, w, 4), np.float32)
    safe = np.maximum(a, 1e-4)[..., None]
    out[..., :3] = np.clip(rgb / np.maximum(1, safe * 0 + 1) / safe * a[..., None], 0, 1)
    out[..., :3] = np.clip(rgb / safe, 0, 1)
    out[..., 3] = np.clip(a, 0, 1)
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA")


def place_logo(img, logo, cx, cy, max_w, max_h):
    k = min(max_w / logo.width, max_h / logo.height)
    lg = logo.resize((max(1, int(logo.width * k)), max(1, int(logo.height * k))), Image.LANCZOS)
    img = img.convert("RGBA")
    img.alpha_composite(lg, (int(cx - lg.width / 2), int(cy - lg.height / 2)))
    return img.convert("RGB")


# --- Assets -------------------------------------------------------------------

def capsule(w, h, logo, logo_box, **kw):
    cv, s = scene(w, h, **kw)
    img = cv.finish(glow_scale=max(w, h))
    cx, cy, mw, mh = logo_box
    return place_logo(img, logo, cx * w, cy * h, mw * w, mh * h)


def icon(size, logo_font_px=None):
    """Square icon: big W with the ball, on the dark grid."""
    cv = Canvas(size, size)
    s = size / 256
    grid(cv, size * 0.62, s * 0.35)
    font = ImageFont.truetype(FONT, int(size * 0.78))
    img, d = cv.layer()
    bb = font.getbbox("W")
    tx = (size - (bb[2] - bb[0])) / 2 - bb[0]
    ty = (size - (bb[3] - bb[1])) / 2 - bb[1] + size * 0.04
    d.text((tx, ty), "W", font=font, fill=P1)
    cv.add(img, 1.25)
    img, d = cv.layer()
    b = size * 0.12
    bx, by = size * 0.5, size * 0.16
    d.rectangle((bx - b / 2, by - b / 2, bx + b / 2, by + b / 2), fill=P2)
    cv.add(img, 1.8)
    return cv.finish(glow_scale=size * 1.4, strength=1.2)


def main():
    os.makedirs(OUT, exist_ok=True)
    logo = logo_rgba(400)
    jobs = {
        # name: (w, h, logo box (cx, cy, max_w, max_h as fractions) or None, scene kwargs)
        "header_capsule_920x430.png": (920, 430, (0.5, 0.47, 0.62, 0.56), dict(paddle_h=0.30, ball=(0.70, 0.30))),
        "small_capsule_462x174.png": (462, 174, (0.5, 0.5, 0.78, 0.86), dict(inset=0.05, paddle_h=0.40, ball=(0.80, 0.25))),
        "main_capsule_1232x706.png": (1232, 706, (0.5, 0.40, 0.56, 0.42), dict(paddle_h=0.26, ball=(0.70, 0.62))),
        "vertical_capsule_748x896.png": (748, 896, (0.5, 0.30, 0.80, 0.30), dict(inset=0.09, paddle_h=0.20, ball=(0.66, 0.62), floor=0.70)),
        "page_background_1438x810.png": (1438, 810, None, dict(ball=(0.66, 0.46))),
        "library_capsule_600x900.png": (600, 900, (0.5, 0.28, 0.82, 0.28), dict(inset=0.09, paddle_h=0.18, ball=(0.66, 0.64), floor=0.72)),
        "library_hero_3840x1240.png": (3840, 1240, None, dict(inset=0.05, paddle_h=0.24, ball=(0.70, 0.40))),
        "library_header_920x430.png": (920, 430, (0.5, 0.47, 0.62, 0.56), dict(paddle_h=0.30, ball=(0.70, 0.30))),
        "event_cover_800x450.png": (800, 450, (0.5, 0.45, 0.6, 0.5), dict(paddle_h=0.30, ball=(0.72, 0.30))),
    }
    for name, (w, h, box, kw) in jobs.items():
        if box:
            img = capsule(w, h, logo, box, **kw)
        else:
            cv, _ = scene(w, h, **kw)
            img = cv.finish(glow_scale=max(w, h))
            if name.startswith("page_background"):
                # Steam asks for a subtle, dark background.
                img = Image.blend(Image.new("RGB", img.size, BG), img, 0.45)
        img.save(os.path.join(OUT, name))
        print("wrote", name, img.size)

    # Library logo: transparent PNG, sits over the hero. Max 1280 wide / 720 tall.
    lg = logo_rgba(560)
    k = min(1280 / lg.width, 720 / lg.height)
    lg = lg.resize((int(lg.width * k), int(lg.height * k)), Image.LANCZOS)
    lg.save(os.path.join(OUT, "library_logo_%dx%d.png" % lg.size))
    print("wrote library_logo", lg.size)
    lg.save(os.path.join(OUT, "..", "wong_logo.png"))

    ic = icon(512)
    ic.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, "shortcut_icon_256x256.png"))
    ic.resize((184, 184), Image.LANCZOS).save(os.path.join(OUT, "app_icon_184x184.jpg"), quality=95)
    ic.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, "..", "icon_256.png"))
    print("wrote icons")


if __name__ == "__main__":
    main()
