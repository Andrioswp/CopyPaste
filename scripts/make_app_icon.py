#!/usr/bin/env python3
"""Draws the CopyPaste app icon.

    python3 scripts/make_app_icon.py --variant C --install     # set the app icon
    python3 scripts/make_app_icon.py --sheet                   # comparison sheet
    python3 scripts/make_app_icon.py --variant B --out /tmp/x.png

Variants:
    A  синий градиент с белой карточкой (текущий)
    B  светлое стекло с контурным глифом
    C  тёмный неон
    D  минимал, системный серый
    E  стопка карточек
"""

from __future__ import annotations

import argparse
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

MASTER = 4096
SIZES = (16, 32, 64, 128, 256, 512, 1024)
TILE_FRACTION = 824 / 1024
CORNER_N = 5.0
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
PREVIEW_DIR = ROOT / "preview"


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

def squircle(size: int, n: float = CORNER_N) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    radius = size / 2.0
    centre = (size - 1) / 2.0
    distance = (np.abs((x - centre) / radius)) ** n + (np.abs((y - centre) / radius)) ** n
    return Image.fromarray(((distance <= 1.0) * 255).astype(np.uint8), "L")


def diagonal_gradient(size: int, top: tuple[int, int, int],
                      bottom: tuple[int, int, int], skew: float = 0.55) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    t = np.clip(x / (size - 1) * (1 - skew) + y / (size - 1) * skew, 0, 1)
    channels = [(top[i] + (bottom[i] - top[i]) * t).astype(np.uint8) for i in range(3)]
    return Image.fromarray(np.dstack(channels), "RGB").convert("RGBA")


def radial_glow(size: int, centre: tuple[float, float], radius: float,
                colour: tuple[int, int, int], alpha: int) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    distance = np.sqrt((x - centre[0]) ** 2 + (y - centre[1]) ** 2) / radius
    fade = np.clip(1.0 - distance, 0, 1) ** 2 * alpha
    rgba = np.zeros((size, size, 4), dtype=np.uint8)
    rgba[..., 0], rgba[..., 1], rgba[..., 2] = colour
    rgba[..., 3] = fade.astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def top_sheen(tile_size: int, alpha: int) -> Image.Image:
    sheen = Image.new("RGBA", (tile_size, tile_size), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse(
        (-tile_size * 0.15, -tile_size * 0.72, tile_size * 1.15, tile_size * 0.34),
        fill=(255, 255, 255, alpha),
    )
    return sheen.filter(ImageFilter.GaussianBlur(tile_size * 0.045))


def inner_hairline(tile_size: int, colour: tuple[int, int, int, int], width: float) -> Image.Image:
    layer = Image.new("RGBA", (tile_size, tile_size), (0, 0, 0, 0))
    inset = tile_size * 0.012
    ImageDraw.Draw(layer).rounded_rectangle(
        (inset, inset, tile_size - inset, tile_size - inset),
        radius=tile_size * 0.19, outline=colour, width=max(1, int(tile_size * width)),
    )
    return layer.filter(ImageFilter.GaussianBlur(tile_size * 0.002))


def glyph_card_stack(glyph: Image.Image, unit: float, *, front: tuple[int, int, int, int],
                     front_edge: tuple[int, int, int, int] | None,
                     back_near: tuple[int, int, int, int],
                     back_far: tuple[int, int, int, int],
                     lines: tuple[int, int, int, int]) -> None:
    """The 'stack of cards' glyph: a white card with a couple of cards behind."""
    draw = ImageDraw.Draw(glyph)

    def box(x0: float, y0: float, x1: float, y1: float):
        return (x0 * unit, y0 * unit, x1 * unit, y1 * unit)

    draw.rounded_rectangle(box(300, 190, 800, 690), radius=84 * unit, fill=back_far)
    draw.rounded_rectangle(box(240, 240, 740, 740), radius=84 * unit, fill=back_near)
    if front_edge is None:
        draw.rounded_rectangle(box(180, 290, 680, 810), radius=88 * unit, fill=front)
    else:
        draw.rounded_rectangle(box(180, 290, 680, 810), radius=88 * unit, fill=front,
                               outline=front_edge, width=int(12 * unit))
    for index, x1 in enumerate((600, 560, 640)):
        y0 = 430 + index * 112
        draw.rounded_rectangle(box(268, y0, x1, y0 + 48), radius=24 * unit, fill=lines)


def glyph_clipboard(glyph: Image.Image, unit: float, *, card: tuple[int, int, int, int],
                    edge: tuple[int, int, int, int] | None, clip: tuple[int, int, int, int],
                    lines: tuple[int, int, int, int], back_card: tuple[int, int, int, int] | None,
                    outline_only: bool = False,
                    notch: tuple[int, int, int, int] = (255, 255, 255, 235),
                    line_widths: tuple[float, float, float] = (310, 266, 352)) -> None:
    """Draws the clipboard glyph on a 1000x1000 grid."""
    draw = ImageDraw.Draw(glyph)

    def box(x0: float, y0: float, x1: float, y1: float):
        return (x0 * unit, y0 * unit, x1 * unit, y1 * unit)

    if back_card is not None:
        draw.rounded_rectangle(box(268, 214, 748, 700), radius=88 * unit, fill=back_card)

    if outline_only:
        draw.rounded_rectangle(box(206, 268, 686, 800), radius=92 * unit,
                               fill=card, outline=edge, width=int(26 * unit))
    else:
        draw.rounded_rectangle(box(206, 268, 686, 800), radius=92 * unit, fill=card)
        if edge is not None:
            draw.rounded_rectangle(box(206, 268, 686, 800), radius=92 * unit,
                                   outline=edge, width=int(10 * unit))

    draw.rounded_rectangle(box(374, 222, 518, 314), radius=44 * unit, fill=clip)
    draw.rounded_rectangle(box(398, 244, 494, 292), radius=24 * unit, fill=notch)

    for index, (width, alpha) in enumerate(zip(line_widths, (235, 200, 200))):
        y0 = 404 + index * 118
        colour = (lines[0], lines[1], lines[2], min(alpha, lines[3]))
        draw.rounded_rectangle(box(290, y0, 290 + width, y0 + 52), radius=26 * unit, fill=colour)


def compose_tile(body: Image.Image, mask: Image.Image) -> Image.Image:
    tile = Image.new("RGBA", body.size, (0, 0, 0, 0))
    tile.paste(body, (0, 0), mask)
    return tile


# --------------------------------------------------------------------------- #
# variants
# --------------------------------------------------------------------------- #

def build_master(variant: str) -> Image.Image:
    canvas = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    tile_size = int(MASTER * TILE_FRACTION)
    offset = (MASTER - tile_size) // 2
    mask = squircle(tile_size)

    # drop shadow
    shadow = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (tile_size, tile_size), (12, 18, 40, 120)),
                 (offset, offset + int(MASTER * 0.018)), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(MASTER * 0.022))
    canvas = Image.alpha_composite(canvas, shadow)

    glyph = Image.new("RGBA", (tile_size, tile_size), (0, 0, 0, 0))
    unit = tile_size / 1000.0

    if variant == "A":  # синий градиент, белая карточка
        body = diagonal_gradient(tile_size, (86, 152, 255), (74, 62, 214))
        body = Image.alpha_composite(body, radial_glow(tile_size, (tile_size * 0.2, tile_size * 0.14),
                                                       tile_size * 0.75, (255, 255, 255), 90))
        body = Image.alpha_composite(body, radial_glow(tile_size, (tile_size * 0.86, tile_size * 0.9),
                                                       tile_size * 0.7, (255, 138, 190), 55))
        body = Image.alpha_composite(body, top_sheen(tile_size, 110))
        body = Image.alpha_composite(body, inner_hairline(tile_size, (255, 255, 255, 120), 0.008))
        glyph_clipboard(glyph, unit, card=(255, 255, 255, 246), edge=None,
                        clip=(37, 82, 226, 255), lines=(58, 106, 226, 255),
                        back_card=(255, 255, 255, 92))

    elif variant == "B":  # светлое стекло, контурный глиф
        body = diagonal_gradient(tile_size, (255, 255, 255), (206, 224, 255), skew=0.7)
        body = Image.alpha_composite(body, radial_glow(tile_size, (tile_size * 0.22, tile_size * 0.18),
                                                       tile_size * 0.8, (255, 255, 255), 150))
        body = Image.alpha_composite(body, radial_glow(tile_size, (tile_size * 0.85, tile_size * 0.88),
                                                       tile_size * 0.75, (120, 170, 255), 90))
        body = Image.alpha_composite(body, top_sheen(tile_size, 190))
        body = Image.alpha_composite(body, inner_hairline(tile_size, (255, 255, 255, 200), 0.010))
        glyph_clipboard(glyph, unit, card=(255, 255, 255, 70), edge=(46, 74, 140, 220),
                        clip=(46, 74, 140, 235), lines=(58, 112, 226, 255),
                        back_card=(46, 74, 140, 40), outline_only=True)

    elif variant == "C":  # тёмный неон
        body = diagonal_gradient(tile_size, (26, 32, 56), (44, 24, 84))
        body = Image.alpha_composite(body, radial_glow(tile_size, (tile_size * 0.2, tile_size * 0.16),
                                                       tile_size * 0.8, (90, 140, 255), 70))
        body = Image.alpha_composite(body, radial_glow(tile_size, (tile_size * 0.85, tile_size * 0.9),
                                                       tile_size * 0.75, (170, 70, 255), 70))
        body = Image.alpha_composite(body, top_sheen(tile_size, 60))
        body = Image.alpha_composite(body, inner_hairline(tile_size, (150, 200, 255, 90), 0.010))
        glyph_clipboard(glyph, unit, card=(236, 244, 255, 250), edge=None,
                        clip=(64, 196, 255, 255), lines=(64, 196, 255, 255),
                        back_card=(120, 200, 255, 60))

    elif variant == "D":  # минимал
        body = diagonal_gradient(tile_size, (246, 248, 252), (214, 221, 233), skew=0.65)
        body = Image.alpha_composite(body, radial_glow(tile_size, (tile_size * 0.25, tile_size * 0.2),
                                                       tile_size * 0.85, (255, 255, 255), 160))
        body = Image.alpha_composite(body, top_sheen(tile_size, 150))
        body = Image.alpha_composite(body, inner_hairline(tile_size, (255, 255, 255, 190), 0.009))
        glyph_clipboard(glyph, unit, card=(78, 88, 110, 250), edge=None,
                        clip=(255, 255, 255, 240), lines=(120, 170, 255, 255),
                        back_card=(78, 88, 110, 45))

    elif variant == "E":  # стопка карточек
        body = diagonal_gradient(tile_size, (38, 48, 92), (96, 120, 240))
        body = Image.alpha_composite(body, radial_glow(tile_size, (tile_size * 0.8, tile_size * 0.15),
                                                       tile_size * 0.8, (140, 190, 255), 80))
        body = Image.alpha_composite(body, top_sheen(tile_size, 90))
        body = Image.alpha_composite(body, inner_hairline(tile_size, (255, 255, 255, 110), 0.009))
        draw = ImageDraw.Draw(glyph)

        def box(x0: float, y0: float, x1: float, y1: float):
            return (x0 * unit, y0 * unit, x1 * unit, y1 * unit)

        draw.rounded_rectangle(box(300, 190, 800, 690), radius=84 * unit, fill=(255, 255, 255, 70))
        draw.rounded_rectangle(box(240, 240, 740, 740), radius=84 * unit, fill=(255, 255, 255, 120))
        draw.rounded_rectangle(box(180, 290, 680, 810), radius=88 * unit, fill=(255, 255, 255, 248))
        for index, x1 in enumerate((600, 560, 640)):
            y0 = 430 + index * 112
            draw.rounded_rectangle(box(268, y0, x1, y0 + 48), radius=24 * unit,
                                   fill=(70, 110, 220, 235))

    elif variant in ("J", "K", "L"):
        # The card-stack glyph the user liked, on different flat backgrounds.
        if variant == "J":
            body = Image.new("RGBA", (tile_size, tile_size), (255, 255, 255, 255))
            glyph_card_stack(glyph, unit, front=(255, 255, 255, 255),
                             front_edge=(199, 214, 240, 255),
                             back_near=(238, 244, 255, 255),
                             back_far=(214, 228, 255, 255),
                             lines=(10, 132, 255, 255))
        elif variant == "K":
            body = Image.new("RGBA", (tile_size, tile_size), (242, 245, 250, 255))
            glyph_card_stack(glyph, unit, front=(255, 255, 255, 255),
                             front_edge=(213, 222, 238, 255),
                             back_near=(230, 238, 252, 255),
                             back_far=(206, 220, 246, 255),
                             lines=(10, 132, 255, 255))
        else:
            body = Image.new("RGBA", (tile_size, tile_size), (10, 132, 255, 255))
            glyph_card_stack(glyph, unit, front=(255, 255, 255, 255), front_edge=None,
                             back_near=(169, 204, 255, 255),
                             back_far=(120, 178, 255, 255),
                             lines=(10, 132, 255, 255))

    elif variant in ("F", "G", "H", "I"):
        # Flat family: plain tile, blue glyph, no gradients or shadows.
        draw = ImageDraw.Draw(glyph)

        def flat_box(x0: float, y0: float, x1: float, y1: float):
            return (x0 * unit, y0 * unit, x1 * unit, y1 * unit)

        if variant == "I":  # синяя плитка, белая карточка
            body = Image.new("RGBA", (tile_size, tile_size), (10, 132, 255, 255))
            glyph_clipboard(glyph, unit, card=(255, 255, 255, 255), edge=None,
                            clip=(255, 255, 255, 255), lines=(10, 132, 255, 255),
                            back_card=None, notch=(10, 132, 255, 255))
        else:
            body = Image.new("RGBA", (tile_size, tile_size), (255, 255, 255, 255))

        if variant == "F":  # синий клипборд, белые строки
            glyph_clipboard(glyph, unit, card=(10, 132, 255, 255), edge=None,
                            clip=(10, 132, 255, 255), lines=(255, 255, 255, 255),
                            back_card=None, notch=(255, 255, 255, 255))

        elif variant == "G":  # контурный синий
            glyph_clipboard(glyph, unit, card=(255, 255, 255, 0),
                            edge=(10, 132, 255, 255), clip=(10, 132, 255, 255),
                            lines=(10, 132, 255, 255), back_card=None,
                            outline_only=True, notch=(255, 255, 255, 255))

        elif variant == "H":  # синий клипборд + светлая карточка сзади
            glyph_clipboard(glyph, unit, card=(10, 132, 255, 255), edge=None,
                            clip=(10, 132, 255, 255), lines=(255, 255, 255, 255),
                            back_card=(150, 200, 255, 255), notch=(255, 255, 255, 255))

    else:
        raise SystemExit(f"unknown variant {variant}")

    if variant in ("F", "G", "H", "I", "J", "K", "L"):
        # Crisp hairline so a white tile stays visible on a white background.
        border = Image.new("RGBA", (tile_size, tile_size), (0, 0, 0, 0))
        ImageDraw.Draw(border).rounded_rectangle(
            (2, 2, tile_size - 2, tile_size - 2), radius=tile_size * 0.20,
            outline=(22, 28, 44, 38), width=max(2, int(tile_size * 0.006)),
        )
        tile = compose_tile(body, mask)
        tile = Image.alpha_composite(tile, Image.alpha_composite(glyph, border))
        canvas.paste(tile, (offset, offset), tile)
        return canvas

    if variant == "C":
        glow = glyph.filter(ImageFilter.GaussianBlur(unit * 30))
        glyph = Image.alpha_composite(glow, glyph)
    else:
        glow = glyph.filter(ImageFilter.GaussianBlur(unit * 26))
        glyph = Image.alpha_composite(glow, glyph)

    tile = compose_tile(body, mask)
    tile = Image.alpha_composite(tile, glyph)
    canvas.paste(tile, (offset, offset), tile)
    return canvas


# --------------------------------------------------------------------------- #
# output
# --------------------------------------------------------------------------- #

def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in ("/System/Library/Fonts/SFNS.ttf",
                 "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                 "/System/Library/Fonts/Supplemental/Arial.ttf"):
        if pathlib.Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def build_sheet(variants: list[str]) -> Image.Image:
    cell = 300
    gap = 46
    pad = 54
    width = pad * 2 + cell * len(variants) + gap * (len(variants) - 1)
    height = pad * 2 + cell + 96
    sheet = Image.new("RGBA", (width, height), (238, 240, 245, 255))

    gradient = diagonal_gradient(height, (248, 249, 252), (222, 226, 236))
    sheet = Image.alpha_composite(sheet, gradient.resize((width, height)))

    draw = ImageDraw.Draw(sheet)
    font_label = load_font(46)
    font_caption = load_font(30)
    captions = {
        "A": "синий градиент",
        "B": "светлое стекло",
        "C": "тёмный неон",
        "D": "минимал",
        "E": "стопка карточек",
        "F": "плоский синий",
        "G": "плоский контур",
        "H": "плоский + стопка",
        "I": "белый на синем",
        "J": "карточка на белом",
        "K": "карточка на светлом",
        "L": "карточка на синем",
    }

    for index, variant in enumerate(variants):
        icon = build_master(variant).resize((cell, cell), Image.LANCZOS)
        x = pad + index * (cell + gap)
        sheet.alpha_composite(icon, (x, pad))
        label = f"{variant}"
        bbox = draw.textbbox((0, 0), label, font=font_label)
        draw.text((x + (cell - (bbox[2] - bbox[0])) / 2, pad + cell + 6), label,
                  font=font_label, fill=(40, 46, 60, 255))
        caption = captions.get(variant, "")
        bbox = draw.textbbox((0, 0), caption, font=font_caption)
        draw.text((x + (cell - (bbox[2] - bbox[0])) / 2, pad + cell + 58), caption,
                  font=font_caption, fill=(110, 118, 134, 255))
    return sheet


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", default="A", choices=list("ABCDEFGHIJKL"))
    parser.add_argument("--install", action="store_true", help="write the appiconset")
    parser.add_argument("--sheet", action="store_true", help="render the comparison sheet")
    parser.add_argument("--out", type=pathlib.Path, help="write a single 512px preview")
    args = parser.parse_args()

    if args.sheet:
        PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
        sheet = build_sheet(list("ABCDE"))
        path = PREVIEW_DIR / "icon_variants.png"
        sheet.save(path)
        print(f"sheet → {path}")
        for variant in "ABCDE":
            single = build_master(variant).resize((512, 512), Image.LANCZOS)
            single.save(PREVIEW_DIR / f"icon_{variant}.png")
        return

    master = build_master(args.variant)

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        master.resize((512, 512), Image.LANCZOS).save(args.out)
        print(f"preview → {args.out}")

    if args.install:
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        for size in SIZES:
            master.resize((size, size), Image.LANCZOS).save(OUT_DIR / f"app_icon_{size}.png")
        master.resize((512, 512), Image.LANCZOS).save(OUT_DIR / "app_icon_preview.png")
        print(f"installed variant {args.variant} → {OUT_DIR}")


if __name__ == "__main__":
    main()
