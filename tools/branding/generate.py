#!/usr/bin/env python3
"""Generate app icons, the admin favicon and splash assets from vector sources.

    python3 tools/branding/generate.py           # writes SVG sources + PNG/ICO outputs
    (cd apps/customer && dart run flutter_launcher_icons && dart run flutter_native_splash:create)
    (cd apps/staff    && dart run flutter_launcher_icons && dart run flutter_native_splash:create)

Designs (design handoff, icon sheet):
  * Customer app  — "Car swoosh" (5b): navy tile, white car glyph, three azure sparkles top-right,
    azure gradient swoosh band rising left→right with a translucent echo band below.
  * Staff app     — "Hex bolt badge" (5f): navy tile, lighter navy disc offset bottom-left,
    azure hexagon with a white bolt.
  * Admin favicon — navy #203060 square + "S." (Outfit Bold); azure dot drops below 32 px,
    letter alone at 16 px.
Adaptive icons keep the glyph inside the inner 66 % safe zone and export foreground/background
as separate layers. Requires: cairosvg, pillow, fonttools (scratchpad venv `zx`).
"""
from __future__ import annotations

import math
import struct
from io import BytesIO
from pathlib import Path

import cairosvg
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SVG_DIR = Path(__file__).resolve().parent / "svg"
FONT = Path(__file__).resolve().parent / "fonts" / "Outfit-Bold.ttf"

NAVY = "#203060"
NAVY_DEEP = "#182650"
NAVY_DISC = "#1E4F86"
AZURE_DEEP = "#0A6DB0"
AZURE = "#1FA6E8"
AZURE_LIGHT = "#6FCBFF"
SPARKLE = "#8BD2FF"
WHITE = "#FFFFFF"

# --------------------------------------------------------------------------- glyphs

def sparkle(cx: float, cy: float, r: float, fill: str = SPARKLE) -> str:
    """Four-point star with concave sides."""
    k = r * 0.28
    d = (
        f"M{cx},{cy - r} Q{cx + k},{cy - k} {cx + r},{cy} Q{cx + k},{cy + k} {cx},{cy + r} "
        f"Q{cx - k},{cy + k} {cx - r},{cy} Q{cx - k},{cy - k} {cx},{cy - r} Z"
    )
    return f'<path d="{d}" fill="{fill}"/>'


def sparkles(scale: float = 1.0, ox: float = 0, oy: float = 0) -> str:
    """The three sparkles of the customer icon, in 1024-space around (760, 210)."""
    pts = [(742, 212, 46), (812, 170, 26), (812, 258, 24)]
    return "".join(sparkle(ox + x * scale, oy + y * scale, r * scale) for x, y, r in pts)


def car(cx: float, cy: float, w: float, fill: str = WHITE) -> str:
    """Front-view car glyph centred at (cx, cy) with total width w (height ≈ 0.8 w).

    One even-odd path: cabin + rounded body with the windshield and headlights as holes,
    so the cut-outs stay transparent on any background; wheel stubs are separate rects.
    """
    s = w / 380.0  # design units → px
    x0, y0 = cx - 190 * s, cy - 150 * s
    def P(x, y):
        return f"{x0 + x * s:.1f},{y0 + y * s:.1f}"
    body = (
        f"M{P(40, 118)} L{P(78, 14)} Q{P(84, 0)} {P(100, 0)} L{P(280, 0)} Q{P(296, 0)} {P(302, 14)} L{P(340, 118)} "
        f"L{P(380, 132)} L{P(380, 244)} Q{P(380, 262)} {P(362, 262)} L{P(18, 262)} Q{P(0, 262)} {P(0, 244)} L{P(0, 132)} Z "
        # windshield (hole)
        f"M{P(104, 30)} L{P(276, 30)} L{P(306, 116)} L{P(74, 116)} Z "
    )
    def hole(hx, hy, r):
        return (f"M{P(hx - r, hy)} A{r*s:.1f},{r*s:.1f} 0 1 0 {P(hx + r, hy)} "
                f"A{r*s:.1f},{r*s:.1f} 0 1 0 {P(hx - r, hy)} Z ")
    body += hole(66, 186, 26) + hole(314, 186, 26)
    r = 20 * s
    wheels = (
        f'<rect x="{x0 + 10*s:.1f}" y="{y0 + 226*s:.1f}" width="{50*s:.1f}" height="{74*s:.1f}" rx="{r:.1f}" fill="{fill}"/>'
        f'<rect x="{x0 + 320*s:.1f}" y="{y0 + 226*s:.1f}" width="{50*s:.1f}" height="{74*s:.1f}" rx="{r:.1f}" fill="{fill}"/>'
    )
    return f'<path d="{body}" fill="{fill}" fill-rule="evenodd"/>{wheels}'


def hexagon(cx: float, cy: float, r: float, fill: str) -> str:
    pts = [(cx + r * math.cos(math.radians(90 + 60 * i)), cy - r * math.sin(math.radians(90 + 60 * i))) for i in range(6)]
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts) + " Z"
    return f'<path d="{d}" fill="{fill}" stroke="{fill}" stroke-width="{r * 0.06}" stroke-linejoin="round"/>'


def bolt(cx: float, cy: float, h: float, fill: str = WHITE) -> str:
    """Material Symbols 'bolt' (rounded) scaled so the bolt is h tall, centred at (cx, cy)."""
    d = ("M11 21h-1l1-7H7.5c-.88 0-.33-.75-.31-.78C8.48 10.94 10.42 7.54 13.01 3h1l-1 7h3.51c.4 0 .62.19.4.66"
         "C12.97 17.55 11 21 11 21z")
    s = h / 18.0
    return (f'<g transform="translate({cx - 12 * s},{cy - 12 * s}) scale({s})">'
            f'<path d="{d}" fill="{fill}" stroke="{fill}" stroke-width="1.1" stroke-linejoin="round" stroke-linecap="round"/></g>')


def swoosh(scale: float = 1.0, ox: float = 0, oy: float = 0, echo: bool = True) -> str:
    """Azure band rising left→right across a 1024 tile (with translucent echo band)."""
    g = ("<linearGradient id=\"swoosh\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\">"
         f"<stop offset=\"0\" stop-color=\"{AZURE_DEEP}\"/><stop offset=\"0.45\" stop-color=\"{AZURE}\"/>"
         f"<stop offset=\"1\" stop-color=\"{AZURE_LIGHT}\"/></linearGradient>")
    def p(x, y):
        return f"{ox + x * scale:.1f},{oy + y * scale:.1f}"
    band = f'<path d="M{p(-40, 740)} L{p(1064, 560)} L{p(1064, 720)} L{p(-40, 860)} Z" fill="url(#swoosh)"/>'
    out = f"<defs>{g}</defs>{band}"
    if echo:
        out += (f'<path d="M{p(-40, 878)} L{p(736, 764)} Q{p(790, 756)} {p(792, 796)} Q{p(794, 830)} {p(748, 838)} '
                f'L{p(-40, 954)} Z" fill="{AZURE_LIGHT}" fill-opacity="0.32"/>')
    return out


def s_glyph_path() -> tuple[str, float, float]:
    """Outfit Bold 'S' outline (font units, y-up) + advance width + cap height."""
    f = TTFont(str(FONT))
    gs = f.getGlyphSet()
    g = gs[f.getBestCmap()[ord("S")]]
    pen = SVGPathPen(gs)
    g.draw(pen)
    return pen.getCommands(), g.width, f["OS/2"].sCapHeight


# --------------------------------------------------------------------------- tiles

def svg(w: int, h: int, body: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
            f"{body}</svg>")


def navy_bg(size: int = 1024, rounded: int = 0) -> str:
    grad = ('<linearGradient id="navy" x1="0" y1="0" x2="1" y2="1">'
            f'<stop offset="0" stop-color="#26397A"/><stop offset="1" stop-color="{NAVY_DEEP}"/></linearGradient>')
    return f'<defs>{grad}</defs><rect width="{size}" height="{size}" rx="{rounded}" fill="url(#navy)"/>'


def customer_background(size: int = 1024) -> str:
    return svg(size, size, navy_bg(size) + swoosh(size / 1024))


def customer_foreground(size: int = 1024, safe: bool = True) -> str:
    # Adaptive foreground: everything inside the inner 66 % (≈ 676 px of 1024).
    k = 0.78 if safe else 1.0
    cx = size / 2
    body = car(cx * 0.95, size * 0.49, 360 * (size / 1024) * k) + sparkles(0.72 * k * size / 1024, size * 0.11, size * 0.13)
    return svg(size, size, body)


def customer_icon(size: int = 1024) -> str:
    s = size / 1024
    body = navy_bg(size) + swoosh(s) + car(size * 0.45, size * 0.42, 400 * s) + sparkles(s)
    return svg(size, size, body)


def staff_background(size: int = 1024) -> str:
    s = size / 1024
    disc = f'<circle cx="{300 * s}" cy="{760 * s}" r="{520 * s}" fill="{NAVY_DISC}" fill-opacity="0.85"/>'
    return svg(size, size, navy_bg(size) + disc)


def hex_bolt(cx: float, cy: float, r: float) -> str:
    grad = ('<linearGradient id="hex" x1="0" y1="0" x2="0.4" y2="1">'
            f'<stop offset="0" stop-color="{AZURE}"/><stop offset="1" stop-color="{AZURE_DEEP}"/></linearGradient>')
    return f"<defs>{grad}</defs>" + hexagon(cx, cy, r, "url(#hex)") + bolt(cx, cy, r * 0.92)


def staff_foreground(size: int = 1024, safe: bool = True) -> str:
    k = 0.66 if safe else 0.84
    return svg(size, size, hex_bolt(size / 2, size / 2, size * 0.5 * k * 0.86))


def staff_icon(size: int = 1024) -> str:
    s = size / 1024
    disc = f'<circle cx="{300 * s}" cy="{760 * s}" r="{520 * s}" fill="{NAVY_DISC}" fill-opacity="0.85"/>'
    return svg(size, size, navy_bg(size) + disc + hex_bolt(size / 2, size * 0.5, 300 * s))


def favicon(size: int, dot: bool, disc: bool, rounded_ratio: float = 0.24) -> str:
    path, adv, cap = s_glyph_path()
    rx = size * rounded_ratio
    body = f'<rect width="{size}" height="{size}" rx="{rx}" fill="{NAVY}"/>'
    if disc:
        body += f'<circle cx="{size * 0.86}" cy="{size * 0.92}" r="{size * 0.66}" fill="{NAVY_DISC}" fill-opacity="0.9"/>'
        body = f'<clipPath id="fc"><rect width="{size}" height="{size}" rx="{rx}"/></clipPath><g clip-path="url(#fc)">{body}</g>'
    cap_px = size * (0.62 if dot else (0.72 if size <= 16 else 0.64))
    sc = cap_px / cap
    letter_w = adv * sc
    total_w = letter_w + (size * 0.13 + size * 0.06 if dot else 0)
    x = (size - total_w) / 2 - (size * 0.03 if dot else 0)
    y = size / 2 + cap_px / 2
    body += f'<g transform="translate({x:.2f},{y:.2f}) scale({sc:.5f},{-sc:.5f})"><path d="{path}" fill="{WHITE}"/></g>'
    if dot:
        body += f'<circle cx="{x + letter_w + size * 0.16:.2f}" cy="{y - size * 0.06:.2f}" r="{size * 0.065:.2f}" fill="{SPARKLE}"/>'
    return svg(size, size, body)


def splash_glyph_customer(size: int = 1152) -> str:
    # Android 12 splash: content must sit inside the centre circle (2/3 of the canvas).
    s = size / 1024
    body = car(size * 0.5, size * 0.52, 360 * s) + sparkles(0.66 * s, size * 0.14, size * 0.16)
    return svg(size, size, body)


def splash_glyph_staff(size: int = 1152) -> str:
    return svg(size, size, hex_bolt(size / 2, size / 2, size * 0.26))


def splash_art_customer(w: int = 1284, h: int = 2778) -> str:
    """Full-bleed portrait art (used for the iOS launch storyboard background)."""
    s = w / 1024
    grad = ('<linearGradient id="navy" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="#26397A"/><stop offset="1" stop-color="{NAVY_DEEP}"/></linearGradient>')
    body = f'<defs>{grad}</defs><rect width="{w}" height="{h}" fill="url(#navy)"/>'
    body += swoosh(s * 1.3, -w * 0.2, h * 0.36, echo=True)
    return svg(w, h, body)


# --------------------------------------------------------------------------- output

def render(svg_text: str, out: Path, width: int | None = None) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(bytestring=svg_text.encode(), write_to=str(out), output_width=width, output_height=width)


def write_svg(name: str, text: str) -> None:
    SVG_DIR.mkdir(parents=True, exist_ok=True)
    (SVG_DIR / name).write_text(text)


def ico(out: Path, sizes: dict[int, str]) -> None:
    """Build a multi-size .ico from {size: svg}; PNG-compressed entries."""
    entries = []
    for size, text in sorted(sizes.items()):
        buf = BytesIO()
        cairosvg.svg2png(bytestring=text.encode(), write_to=buf, output_width=size, output_height=size)
        entries.append((size, buf.getvalue()))
    header = struct.pack("<HHH", 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    dirs, blobs = b"", b""
    for size, png in entries:
        dirs += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(png), offset)
        blobs += png
        offset += len(png)
    out.write_bytes(header + dirs + blobs)


def main() -> None:
    cust = ROOT / "apps/customer/assets"
    staff = ROOT / "apps/staff/assets"
    admin = ROOT / "apps/admin"

    # ---- sources
    write_svg("customer_icon.svg", customer_icon())
    write_svg("customer_icon_background.svg", customer_background())
    write_svg("customer_icon_foreground.svg", customer_foreground())
    write_svg("staff_icon.svg", staff_icon())
    write_svg("staff_icon_background.svg", staff_background())
    write_svg("staff_icon_foreground.svg", staff_foreground())
    write_svg("admin_favicon_96.svg", favicon(96, dot=True, disc=True))
    write_svg("admin_favicon_32.svg", favicon(32, dot=False, disc=False))
    write_svg("customer_splash_glyph.svg", splash_glyph_customer())
    write_svg("staff_splash_glyph.svg", splash_glyph_staff())
    write_svg("customer_splash_art.svg", splash_art_customer())

    # ---- launcher icons (flutter_launcher_icons reads these)
    render(customer_icon(), cust / "icon/app_icon.png", 1024)
    render(customer_background(), cust / "icon/app_icon_background.png", 1024)
    render(customer_foreground(), cust / "icon/app_icon_foreground.png", 1024)
    render(staff_icon(), staff / "icon/app_icon.png", 1024)
    render(staff_background(), staff / "icon/app_icon_background.png", 1024)
    render(staff_foreground(), staff / "icon/app_icon_foreground.png", 1024)

    # ---- splash (flutter_native_splash reads these): the Sparkling wordmark centred on navy.
    # Only a 231 px master exists, so it is upscaled with Lanczos + unsharp mask; sized so the
    # image is treated as 4x (Android) / 3x (iOS) → ≈185 dp / 247 pt wide on screen.
    from PIL import ImageFilter
    wm = Image.open(admin / "public/logo-dark.png").convert("RGBA")
    big = wm.resize((wm.width * 32 // 10, wm.height * 32 // 10), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=2, percent=90, threshold=2))
    a12 = Image.new("RGBA", (1152, 1152), (0, 0, 0, 0))            # Android 12: content inside the 768 px launch circle
    a12w = 690
    a12l = wm.resize((a12w, wm.height * a12w // wm.width), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=2, percent=90, threshold=2))
    a12.alpha_composite(a12l, ((1152 - a12l.width) // 2, (1152 - a12l.height) // 2))
    for target in (cust, staff):
        (target / "splash").mkdir(parents=True, exist_ok=True)
        big.save(target / "splash/splash_center.png")
        a12.save(target / "splash/splash_glyph.png")
        for stale in ("branding.png",):
            (target / "splash" / stale).unlink(missing_ok=True)

    # ---- admin favicon family
    render(favicon(512, dot=True, disc=True), admin / "public/icon-512.png", 512)
    render(favicon(192, dot=True, disc=True), admin / "public/icon-192.png", 192)
    render(favicon(180, dot=True, disc=True, rounded_ratio=0.0), admin / "public/apple-touch-icon.png", 180)
    (admin / "public/icon.svg").write_text(favicon(96, dot=True, disc=True))
    ico(admin / "src/app/favicon.ico", {16: favicon(16, dot=False, disc=False, rounded_ratio=0.2), 32: favicon(32, dot=False, disc=False), 48: favicon(48, dot=True, disc=True)})

    # ---- preview sheet for the docs
    render(customer_icon(512), ROOT / "docs/branding/customer-icon.png", 512)
    render(staff_icon(512), ROOT / "docs/branding/staff-icon.png", 512)
    render(favicon(96, dot=True, disc=True), ROOT / "docs/branding/admin-favicon.png", 192)
    print("ok")


if __name__ == "__main__":
    main()
