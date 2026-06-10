from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


OUT_DIR = Path(__file__).resolve().parent

BG = (248, 248, 248)
PANEL = (255, 255, 255)
TEXT = (54, 54, 54)
MUTED = (105, 105, 105)
SHELL = (178, 178, 178)
SHELL_DARK = (154, 154, 154)
INNER = (186, 186, 186)
WHITE = (246, 246, 246)
GREEN = (64, 184, 86)
RED = (207, 82, 73)
GRID = (224, 224, 224)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\simhei.ttf" if bold else r"C:\Windows\Fonts\simhei.ttf",
        r"C:\Windows\Fonts\simsun.ttc",
        r"C:\Windows\Fonts\segoeuib.ttf" if bold else r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


FONT_11 = font(11)
FONT_12 = font(12)
FONT_13 = font(13)
FONT_14_BOLD = font(14, True)
FONT_18_BOLD = font(18, True)
FONT_22_BOLD = font(22, True)


def rounded(draw: ImageDraw.ImageDraw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def draw_ref_battery(
    w: int,
    h: int,
    level: float = 1.0,
    variant: int = 0,
    charging: bool = False,
    low: bool = False,
    dark: bool = False,
) -> Image.Image:
    """Draw a reference-style battery icon at arbitrary bitmap size."""
    scale = h / 14.0
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    shell = (128, 132, 138) if dark else SHELL
    shell_dark = (112, 116, 122) if dark else SHELL_DARK
    white = (42, 42, 42) if dark else WHITE
    inner = (126, 130, 136) if dark else INNER
    fill = GREEN if charging else (RED if low else inner)

    # Variant knobs stay close to the user's reference: mostly thickness/radius/shadow.
    knobs = [
        dict(name="soft", radius=3.3, stroke=2.0, cap_w=2.0, cap_h=6.0, inset=2.8, shadow=1.6, body_w=0.82),
        dict(name="fuller", radius=2.7, stroke=2.2, cap_w=2.0, cap_h=6.8, inset=2.5, shadow=1.3, body_w=0.84),
        dict(name="rounded", radius=4.0, stroke=2.1, cap_w=2.1, cap_h=5.7, inset=3.0, shadow=1.8, body_w=0.81),
        dict(name="crisp", radius=2.4, stroke=1.8, cap_w=1.8, cap_h=5.8, inset=2.4, shadow=0.6, body_w=0.84),
        dict(name="thick rim", radius=3.2, stroke=2.6, cap_w=2.1, cap_h=6.2, inset=3.4, shadow=1.5, body_w=0.80),
        dict(name="compact", radius=2.5, stroke=1.7, cap_w=1.7, cap_h=5.0, inset=2.2, shadow=1.0, body_w=0.85),
        dict(name="deep fill", radius=2.8, stroke=2.0, cap_w=2.0, cap_h=6.4, inset=2.2, shadow=1.5, body_w=0.84),
        dict(name="ios small", radius=2.2, stroke=1.65, cap_w=1.55, cap_h=4.8, inset=2.0, shadow=0.8, body_w=0.86),
    ][variant]

    pad_x = max(1.0, 1.0 * scale)
    pad_y = max(1.0, 1.3 * scale)
    cap_gap = max(0.6, 0.8 * scale)
    cap_w = knobs["cap_w"] * scale
    body_w = w * knobs["body_w"] - cap_w - cap_gap
    body_h = h - pad_y * 2
    body = (pad_x, pad_y, pad_x + body_w, pad_y + body_h)
    cap_h = knobs["cap_h"] * scale
    cap_y = (h - cap_h) / 2
    cap = (body[2] + cap_gap, cap_y, body[2] + cap_gap + cap_w, cap_y + cap_h)

    # Soft shadow/glow like the supplied screenshot.
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    offset = max(1, round(0.65 * scale))
    shadow_alpha = 75 if not dark else 30
    rounded(
        sd,
        (body[0] + offset, body[1] + offset, body[2] + offset, body[3] + offset),
        knobs["radius"] * scale,
        fill=(0, 0, 0, shadow_alpha),
    )
    rounded(
        sd,
        (cap[0] + offset, cap[1] + offset, cap[2] + offset, cap[3] + offset),
        0.8 * scale,
        fill=(0, 0, 0, shadow_alpha),
    )
    blur = max(0.2, knobs["shadow"] * scale)
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))

    d = ImageDraw.Draw(img)
    stroke_w = max(1, round(knobs["stroke"] * scale))
    radius = knobs["radius"] * scale

    # Main shell and cap.
    rounded(d, body, radius, fill=shell, outline=shell_dark, width=max(1, round(0.45 * scale)))
    rounded(d, cap, 0.7 * scale, fill=shell, outline=None)

    # The screenshot reads as a grey slab surrounded by a pale inner rim.
    inset = knobs["inset"] * scale
    inner_box = (
        body[0] + inset,
        body[1] + inset * 0.86,
        body[2] - inset * 0.8,
        body[3] - inset * 0.86,
    )
    rounded(d, inner_box, max(0.8, radius - inset * 0.45), fill=white)

    fill_pad = max(0.6, 0.55 * scale)
    fill_box_full = (
        inner_box[0] + fill_pad,
        inner_box[1] + fill_pad,
        inner_box[2] - fill_pad,
        inner_box[3] - fill_pad,
    )
    fill_w = max(0, (fill_box_full[2] - fill_box_full[0]) * max(0, min(1, level)))
    if fill_w > 0:
        fill_box = (
            fill_box_full[0],
            fill_box_full[1],
            fill_box_full[0] + fill_w,
            fill_box_full[3],
        )
        rounded(d, fill_box, max(0.6, radius - inset * 0.7), fill=fill)

    # Subtle top-left highlight keeps the icon close to the blurred reference.
    if variant in (0, 1, 2, 4, 6):
        d.line(
            (body[0] + 1.3 * scale, body[1] + 0.9 * scale, body[2] - 1.0 * scale, body[1] + 0.9 * scale),
            fill=(255, 255, 255, 70) if not dark else (255, 255, 255, 22),
            width=max(1, round(0.55 * scale)),
        )

    if charging:
        cx = (fill_box_full[0] + fill_box_full[2]) / 2
        cy = (fill_box_full[1] + fill_box_full[3]) / 2
        bolt = [
            (cx + 0.7 * scale, cy - 4.5 * scale),
            (cx - 2.6 * scale, cy + 0.2 * scale),
            (cx - 0.2 * scale, cy + 0.2 * scale),
            (cx - 1.5 * scale, cy + 4.4 * scale),
            (cx + 2.9 * scale, cy - 0.8 * scale),
            (cx + 0.4 * scale, cy - 0.8 * scale),
        ]
        d.polygon(bolt, fill=(255, 255, 255, 230))

    return img


def draw_footer_row(variant: int, level: float, charging=False, low=False, dark=False) -> Image.Image:
    scale = 4
    w, h = 250 * scale, 34 * scale
    bg = (22, 22, 22) if dark else BG
    text = (147, 151, 158) if dark else (96, 96, 96)
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    f = font(12 * scale)

    x = 10 * scale
    y = 6 * scale
    d.text((x, y), "12:45", fill=text, font=f)
    x += 43 * scale

    icon = draw_ref_battery(26 * scale, 14 * scale, level, variant, charging, low, dark)
    img.paste(icon, (x, 9 * scale), icon)
    x += 32 * scale
    d.text((x, y), f"{round(level * 100)}%", fill=text, font=f)
    d.text((165 * scale, y), "1/24  12.45%", fill=text, font=f)
    return img


VARIANT_TITLES = [
    ("A 贴近原图", "厚灰边、白内缘、柔和阴影"),
    ("B 更饱满", "主体更宽，填充块更接近截图"),
    ("C 更圆润", "圆角更大，整体更软"),
    ("D 更清晰", "降低阴影，适合直接手绘"),
    ("E 厚边框", "外框更重，低分辨率更稳"),
    ("F 小尺寸", "为 17x8pt 约束做的压缩版"),
    ("G 深填充", "内部灰块更满，轮廓更像截图"),
    ("H UIKit 小图标", "更像可直接落到当前 widget 的版本"),
]


def make_card(idx: int) -> Image.Image:
    title, subtitle = VARIANT_TITLES[idx]
    card = Image.new("RGB", (474, 340), PANEL)
    d = ImageDraw.Draw(card)
    d.text((24, 20), title, fill=TEXT, font=FONT_18_BOLD)
    d.text((24, 46), subtitle, fill=MUTED, font=FONT_13)

    d.text((24, 84), "widget 行内效果", fill=MUTED, font=FONT_12)
    row = draw_footer_row(idx, 0.72)
    card.paste(row.resize((360, 49), Image.Resampling.LANCZOS), (24, 104))

    d.text((24, 174), "放大细节", fill=MUTED, font=FONT_12)
    states = [
        (1.0, False, False, "满电复刻"),
        (0.72, False, False, "72%"),
        (0.18, False, True, "18%"),
        (0.72, True, False, "充电"),
    ]
    x = 24
    for level, charging, low, label in states:
        panel = Image.new("RGB", (96, 118), (252, 252, 252))
        pd = ImageDraw.Draw(panel)
        pd.rounded_rectangle((0, 0, 95, 117), radius=8, outline=GRID, fill=(252, 252, 252))
        icon = draw_ref_battery(76, 42, level, idx, charging, low)
        panel.paste(icon, (10, 22), icon)
        pd.text((11, 85), label, fill=MUTED, font=FONT_11)
        card.paste(panel, (x, 196))
        x += 106
    return card


def make_sheet(cards: list[Image.Image]) -> Path:
    margin = 22
    gap = 18
    cols = 2
    card_w, card_h = cards[0].size
    rows = math.ceil(len(cards) / cols)
    sheet_w = margin * 2 + cols * card_w + gap
    sheet_h = 96 + rows * card_h + (rows - 1) * gap + margin
    sheet = Image.new("RGB", (sheet_w, sheet_h), BG)
    d = ImageDraw.Draw(sheet)
    d.text((margin, 20), "复刻参考图的电池小组件样式", fill=TEXT, font=FONT_22_BOLD)
    d.text((margin, 53), "围绕同一种外观微调：灰色厚壳、浅色内缘、灰色填充、右侧电极、轻微阴影。", fill=MUTED, font=FONT_13)
    for idx, card in enumerate(cards):
        col = idx % cols
        row = idx // cols
        x = margin + col * (card_w + gap)
        y = 96 + row * (card_h + gap)
        sheet.paste(card, (x, y))
        d.rounded_rectangle((x, y, x + card_w - 1, y + card_h - 1), radius=8, outline=GRID)
    out = OUT_DIR / "battery_reference_style_sheet.png"
    sheet.save(out)
    return out


def make_size_sheet() -> Path:
    sheet = Image.new("RGB", (980, 420), BG)
    d = ImageDraw.Draw(sheet)
    d.text((24, 22), "尺寸对照", fill=TEXT, font=FONT_22_BOLD)
    d.text((24, 54), "同一复刻风格在 17x8pt、20x10pt、24x12pt、26x14pt 下的可读性。", fill=MUTED, font=FONT_13)

    sizes = [(17, 8), (20, 10), (24, 12), (26, 14)]
    variants = [0, 4, 7]
    y = 102
    for variant in variants:
        title, subtitle = VARIANT_TITLES[variant]
        d.text((24, y), title, fill=TEXT, font=FONT_18_BOLD)
        d.text((24, y + 25), subtitle, fill=MUTED, font=FONT_13)
        x = 230
        for pt_w, pt_h in sizes:
            panel = Image.new("RGB", (160, 82), PANEL)
            pd = ImageDraw.Draw(panel)
            pd.rounded_rectangle((0, 0, 159, 81), radius=8, fill=PANEL, outline=GRID)
            icon = draw_ref_battery(pt_w * 6, pt_h * 6, 0.72, variant)
            panel.paste(icon, ((160 - pt_w * 6) // 2, 12), icon)
            pd.text((15, 60), f"{pt_w}x{pt_h}pt", fill=MUTED, font=FONT_12)
            sheet.paste(panel, (x, y - 6))
            x += 174
        y += 108
    out = OUT_DIR / "battery_reference_size_check.png"
    sheet.save(out)
    return out


def make_theme_sheet() -> Path:
    sheet = Image.new("RGB", (1000, 350), BG)
    d = ImageDraw.Draw(sheet)
    d.text((24, 22), "明暗主题对照", fill=TEXT, font=FONT_22_BOLD)
    d.text((24, 54), "保留参考图灰色质感；暗色主题只降低亮度，不改成其它图标语言。", fill=MUTED, font=FONT_13)
    variants = [0, 4, 7]
    y = 104
    for variant in variants:
        title, _ = VARIANT_TITLES[variant]
        d.text((24, y + 12), title, fill=TEXT, font=FONT_14_BOLD)
        bright = draw_footer_row(variant, 0.72, dark=False).resize((375, 51), Image.Resampling.LANCZOS)
        dark = draw_footer_row(variant, 0.72, dark=True).resize((375, 51), Image.Resampling.LANCZOS)
        sheet.paste(bright, (230, y))
        sheet.paste(dark, (610, y))
        y += 76
    out = OUT_DIR / "battery_reference_theme_check.png"
    sheet.save(out)
    return out


def main():
    cards = [make_card(i) for i in range(len(VARIANT_TITLES))]
    out_paths = [
        make_sheet(cards),
        make_size_sheet(),
        make_theme_sheet(),
    ]
    for i, card in enumerate(cards, start=1):
        path = OUT_DIR / f"battery_reference_style_{i:02d}.png"
        card.save(path)
        out_paths.append(path)
    for path in out_paths:
        print(path)


if __name__ == "__main__":
    main()
