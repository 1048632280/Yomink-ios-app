from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


OUT_DIR = Path(__file__).resolve().parent
SCALE = 8
ICON_W = 17
ICON_H = 8
ROW_H = 14

BG = (249, 249, 249)
TEXT = (97, 97, 97)
HEADER = (176, 176, 176)
CONTENT = (62, 62, 62)
GREEN = (61, 186, 82)
LOW_RED = (214, 80, 70)
GRID = (226, 226, 226)


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        r"C:\Windows\Fonts\segoeuib.ttf" if bold else r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            pass
    return ImageFont.load_default()


FONT_12 = load_font(12)
FONT_13 = load_font(13)
FONT_14_BOLD = load_font(14, bold=True)
FONT_18_BOLD = load_font(18, bold=True)
FONT_22_BOLD = load_font(22, bold=True)


def rect(draw: ImageDraw.ImageDraw, xy, fill=None, outline=None, width=1, radius=0):
    x0, y0, x1, y1 = xy
    if radius:
        draw.rounded_rectangle((x0, y0, x1, y1), radius=radius, fill=fill, outline=outline, width=width)
    else:
        draw.rectangle((x0, y0, x1, y1), fill=fill, outline=outline, width=width)


def scaled_icon(draw_func, level=0.72, charging=False, low=False):
    img = Image.new("RGBA", (ICON_W * SCALE, ICON_H * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw_func(draw, 0, 0, ICON_W * SCALE, ICON_H * SCALE, level, charging, low, SCALE)
    return img


def current_icon(draw, x, y, w, h, level, charging, low, s):
    outline = HEADER
    fill = GREEN if charging else HEADER
    body = (x + 0.7 * s, y + 0.7 * s, x + (ICON_W - 3.0) * s, y + (ICON_H - 0.7) * s)
    cap = (body[2] + 0.8 * s, y + ICON_H * 0.31 * s, body[2] + 3.0 * s, y + ICON_H * 0.69 * s)
    rect(draw, body, outline=outline, width=max(1, round(1.1 * s)), radius=round(1.4 * s))
    rect(draw, cap, fill=outline, radius=round(0.5 * s))
    inner_w = (body[2] - body[0]) - 4.2 * s
    fill_w = max(0, inner_w * level)
    if fill_w > 0:
        rect(
            draw,
            (body[0] + 2.1 * s, body[1] + 2.1 * s, body[0] + 2.1 * s + fill_w, body[3] - 2.1 * s),
            fill=fill,
            radius=round(0.8 * s),
        )


def soft_pill(draw, x, y, w, h, level, charging, low, s):
    fill = GREEN if charging else (LOW_RED if low else HEADER)
    body = (x + 0.6 * s, y + 0.9 * s, x + 13.9 * s, y + 7.1 * s)
    cap = (x + 14.6 * s, y + 2.7 * s, x + 16.4 * s, y + 5.3 * s)
    rect(draw, body, outline=HEADER, width=s, radius=3 * s)
    rect(draw, cap, fill=HEADER, radius=1.0 * s)
    inner = (body[0] + 1.6 * s, body[1] + 1.45 * s, body[2] - 1.55 * s, body[3] - 1.45 * s)
    fw = max(0, (inner[2] - inner[0]) * level)
    if fw > 0:
        rect(draw, (inner[0], inner[1], inner[0] + fw, inner[3]), fill=fill, radius=2 * s)
    if charging:
        draw.line(
            [
                (x + 8.3 * s, y + 1.8 * s),
                (x + 6.8 * s, y + 4.2 * s),
                (x + 8.4 * s, y + 4.2 * s),
                (x + 7.3 * s, y + 6.5 * s),
            ],
            fill=(255, 255, 255),
            width=max(1, int(0.8 * s)),
        )


def segmented(draw, x, y, w, h, level, charging, low, s):
    fill = GREEN if charging else (LOW_RED if low else HEADER)
    body = (x + 0.7 * s, y + 0.9 * s, x + 14.1 * s, y + 7.1 * s)
    cap = (x + 14.8 * s, y + 2.6 * s, x + 16.4 * s, y + 5.4 * s)
    rect(draw, body, outline=HEADER, width=s, radius=1.7 * s)
    rect(draw, cap, fill=HEADER, radius=0.7 * s)
    segments = 4
    gap = 0.75 * s
    ix0 = body[0] + 1.7 * s
    iy0 = body[1] + 1.45 * s
    ih = body[3] - body[1] - 2.9 * s
    total = body[2] - body[0] - 3.4 * s
    seg_w = (total - gap * (segments - 1)) / segments
    active = math.ceil(level * segments - 1e-6)
    for i in range(segments):
        sx = ix0 + i * (seg_w + gap)
        alpha_fill = fill if i < active else (230, 230, 230)
        rect(draw, (sx, iy0, sx + seg_w, iy0 + ih), fill=alpha_fill, radius=0.6 * s)


def ink_line(draw, x, y, w, h, level, charging, low, s):
    stroke = HEADER
    fill = GREEN if charging else (LOW_RED if low else CONTENT)
    cy = y + 4 * s
    body = (x + 0.8 * s, y + 1.1 * s, x + 13.9 * s, y + 6.9 * s)
    rect(draw, body, outline=stroke, width=max(1, round(0.85 * s)), radius=1.2 * s)
    draw.line((x + 14.7 * s, y + 3 * s, x + 16.2 * s, y + 3 * s), fill=stroke, width=max(1, round(0.75 * s)))
    draw.line((x + 14.7 * s, y + 5 * s, x + 16.2 * s, y + 5 * s), fill=stroke, width=max(1, round(0.75 * s)))
    ix0 = body[0] + 1.7 * s
    ix1 = body[2] - 1.7 * s
    fill_end = ix0 + (ix1 - ix0) * level
    draw.line((ix0, cy, fill_end, cy), fill=fill, width=max(1, round(1.3 * s)))


def book_leaf(draw, x, y, w, h, level, charging, low, s):
    fill = GREEN if charging else (LOW_RED if low else HEADER)
    stroke = HEADER
    body = (x + 0.7 * s, y + 0.8 * s, x + 13.8 * s, y + 7.2 * s)
    cap = (x + 14.6 * s, y + 2.6 * s, x + 16.2 * s, y + 5.4 * s)
    rect(draw, body, outline=stroke, width=s, radius=1.3 * s)
    rect(draw, cap, fill=stroke, radius=0.6 * s)
    ix0 = body[0] + 1.45 * s
    iy0 = body[1] + 1.6 * s
    iw = body[2] - body[0] - 2.9 * s
    ih = body[3] - body[1] - 3.2 * s
    fw = iw * level
    if fw > 0:
        rect(draw, (ix0, iy0, ix0 + fw, iy0 + ih), fill=fill, radius=0.5 * s)
    # page crease: tiny readable accent at high DPI, harmless at device size.
    draw.line((body[0] + 4.7 * s, body[1] + 1.2 * s, body[0] + 4.7 * s, body[3] - 1.2 * s), fill=stroke, width=max(1, round(0.45 * s)))


def spark(draw, x, y, w, h, level, charging, low, s):
    fill = GREEN if charging else (LOW_RED if low else HEADER)
    stroke = GREEN if charging else HEADER
    body = (x + 0.7 * s, y + 0.9 * s, x + 14.1 * s, y + 7.1 * s)
    cap = (x + 14.8 * s, y + 2.8 * s, x + 16.3 * s, y + 5.2 * s)
    rect(draw, body, outline=stroke, width=s, radius=1.4 * s)
    rect(draw, cap, fill=stroke, radius=0.6 * s)
    ix0 = body[0] + 1.5 * s
    iy0 = body[1] + 1.4 * s
    iw = body[2] - body[0] - 3 * s
    ih = body[3] - body[1] - 2.8 * s
    rect(draw, (ix0, iy0, ix0 + iw * level, iy0 + ih), fill=fill, radius=0.7 * s)
    bolt = [
        (x + 8.4 * s, y + 0.9 * s),
        (x + 5.8 * s, y + 4.2 * s),
        (x + 7.8 * s, y + 4.2 * s),
        (x + 6.5 * s, y + 7.3 * s),
        (x + 11.1 * s, y + 3.3 * s),
        (x + 8.7 * s, y + 3.3 * s),
    ]
    draw.polygon(bolt, fill=(255, 255, 255) if charging else stroke)


STYLES = [
    ("A Current refined", "same contract, softer fill", current_icon),
    ("B Soft pill", "rounder, calmer in footer", soft_pill),
    ("C Segmented", "fast level scan, low-state friendly", segmented),
    ("D Ink line", "thin e-ink mark, very quiet", ink_line),
    ("E Book leaf", "subtle page-crease cue", book_leaf),
    ("F Charge spark", "clear charging affordance", spark),
]


def draw_widget_row(style_func, level, charging=False, low=False, scale=4, dark=False):
    global HEADER

    w, h = 230 * scale, 34 * scale
    bg = (22, 22, 22) if dark else BG
    text = (147, 151, 158) if dark else TEXT
    header = (109, 113, 121) if dark else HEADER
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    font = load_font(12 * scale)

    # Approximate ReaderBottomWidgetView left sequence: time, gap 5pt, battery, gap 5pt, percent.
    x = 10 * scale
    y = 10 * scale
    d.text((x, y - 4 * scale), "12:45", fill=text, font=font)
    x += 38 * scale + 5 * scale

    icon_img = Image.new("RGBA", (ICON_W * scale, ICON_H * scale), (0, 0, 0, 0))
    old_header = HEADER
    try:
        HEADER = header
        icon_draw = ImageDraw.Draw(icon_img)
        style_func(icon_draw, 0, 0, ICON_W * scale, ICON_H * scale, level, charging, low, scale)
    finally:
        HEADER = old_header
    img.paste(icon_img, (x, (ROW_H * scale - ICON_H * scale) // 2 + 10 * scale - 7 * scale), icon_img)
    x += ICON_W * scale + 5 * scale
    d.text((x, y - 4 * scale), f"{round(level * 100)}%", fill=text, font=font)
    d.text((w - 72 * scale, y - 4 * scale), "1/24  12.45%", fill=text, font=font)
    return img


def make_card(name, subtitle, func, idx):
    card_w, card_h = 460, 336
    img = Image.new("RGB", (card_w, card_h), BG)
    d = ImageDraw.Draw(img)
    d.text((24, 18), name, fill=CONTENT, font=FONT_18_BOLD)
    d.text((24, 43), subtitle, fill=TEXT, font=FONT_13)

    # Realistic footer row.
    d.text((24, 78), "Actual footer row context", fill=TEXT, font=FONT_12)
    row = draw_widget_row(func, 0.72, charging=False, scale=3)
    img.paste(row.resize((345, 51), Image.Resampling.LANCZOS), (24, 98))

    # Magnified icon states.
    d.text((24, 168), "Magnified states", fill=TEXT, font=FONT_12)
    states = [(0.18, False, True, "18%"), (0.72, False, False, "72%"), (0.72, True, False, "72% charging")]
    x = 24
    for level, charging, low, label in states:
        icon = scaled_icon(func, level=level, charging=charging, low=low)
        panel = Image.new("RGB", (120, 96), (255, 255, 255))
        pd = ImageDraw.Draw(panel)
        pd.rounded_rectangle((0, 0, 119, 95), radius=8, outline=GRID, width=1, fill=(255, 255, 255))
        # Add transparent icon over panel.
        panel.paste(icon, ((120 - ICON_W * SCALE) // 2, 12), icon)
        pd.text((10, 75), label, fill=TEXT, font=FONT_12)
        img.paste(panel, (x, 190))
        x += 132

    path = OUT_DIR / f"battery_style_{idx:02d}.png"
    img.save(path)
    return img, path


def make_sheet(cards):
    margin = 22
    gap = 18
    cols = 2
    rows = math.ceil(len(cards) / cols)
    card_w, card_h = cards[0][0].size
    sheet_w = margin * 2 + cols * card_w + (cols - 1) * gap
    sheet_h = 94 + rows * card_h + (rows - 1) * gap + margin
    sheet = Image.new("RGB", (sheet_w, sheet_h), BG)
    d = ImageDraw.Draw(sheet)
    d.text((margin, 20), "Reader battery widget redraw options", fill=CONTENT, font=FONT_22_BOLD)
    d.text(
        (margin, 50),
        "Based on the current 17x8pt icon inside a 14pt footer row. No app source files changed.",
        fill=TEXT,
        font=FONT_13,
    )
    for i, (card, _) in enumerate(cards):
        col = i % cols
        row = i // cols
        x = margin + col * (card_w + gap)
        y = 94 + row * (card_h + gap)
        sheet.paste(card, (x, y))
        sd = ImageDraw.Draw(sheet)
        sd.rounded_rectangle((x, y, x + card_w - 1, y + card_h - 1), radius=8, outline=GRID, width=1)
    sheet_path = OUT_DIR / "battery_widget_style_sheet.png"
    sheet.save(sheet_path)
    return sheet_path


def main():
    cards = [make_card(name, subtitle, func, i + 1) for i, (name, subtitle, func) in enumerate(STYLES)]
    sheet_path = make_sheet(cards)

    # A compact dark/bright comparison for the two most promising directions.
    compare = Image.new("RGB", (1060, 520), BG)
    d = ImageDraw.Draw(compare)
    d.text((24, 20), "Theme check: bright and dark backgrounds", fill=CONTENT, font=FONT_22_BOLD)
    d.text((260, 56), "Bright", fill=TEXT, font=FONT_14_BOLD)
    d.text((660, 56), "Dark", fill=TEXT, font=FONT_14_BOLD)
    choices = [(STYLES[1], 0.72), (STYLES[2], 0.18), (STYLES[5], 0.72)]
    y = 92
    for (name, subtitle, func), level in choices:
        d.text((24, y), name, fill=CONTENT, font=FONT_18_BOLD)
        d.text((24, y + 25), subtitle, fill=TEXT, font=FONT_13)
        bright = draw_widget_row(func, level, charging=False, low=level < 0.2, scale=2, dark=False)
        dark = draw_widget_row(func, level, charging=(name.startswith("F")), low=level < 0.2, scale=2, dark=True)
        compare.paste(bright, (260, y - 8))
        compare.paste(dark, (660, y - 8))
        y += 132
    compare_path = OUT_DIR / "battery_widget_theme_check.png"
    compare.save(compare_path)

    print(sheet_path)
    print(compare_path)
    for _, path in cards:
        print(path)


if __name__ == "__main__":
    main()
