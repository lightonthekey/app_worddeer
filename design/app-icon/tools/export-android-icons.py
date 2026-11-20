#!/usr/bin/env python3
"""从 design/app-icon/source 的母版导出 Android 图标。

用法：
    python design/app-icon/tools/export-android-icons.py [--preview]

产物：
    android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png
    android/app/src/main/res/mipmap-{...}/ic_launcher_foreground.png
    android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
    android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml
    android/app/src/main/res/values/ic_launcher_background.xml

要点：
- 传统图标（API < 26）用整张母版铺满，与 iOS 观感一致。
- 自适应图标的前景层画布是 108dp，系统只保证中间 72dp 的圆形安全区可见
  （极端遮罩下只剩 66dp）。母版主体几乎顶到四边，直接铺满会被裁掉鹿耳，
  所以前景按 SCALE 缩到中间、四周用背景色补，耳朵刚好压在安全区边缘。
- 背景层用母版角落的暖米色，和母版无缝衔接，避免遮罩边缘出现色差。
"""

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "design/app-icon/source/deer-final-1536.png"
RES = ROOT / "android/app/src/main/res"

# 自适应图标前景缩放：母版四周有留白，0.76 时耳尖刚好压到圆形遮罩边缘，
# 0.80 开始裁耳（`--preview` 输出的 preview-android-mask.png 就是这条界线）
SCALE = 0.76
BG = (254, 240, 227)  # 母版角落采样

# 传统图标边长（dp）
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# 自适应图标 108dp 画布的实际像素
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""


def load_master() -> Image.Image:
    im = Image.open(SRC).convert("RGB")
    if im.width != im.height:
        raise SystemExit(f"母版必须是正方形，实际 {im.size}")
    return im


def legacy(im: Image.Image, size: int) -> Image.Image:
    return im.resize((size, size), Image.LANCZOS)


def legacy_round(im: Image.Image, size: int) -> Image.Image:
    """API < 26 的圆形启动图标：自己切圆、四角透明（系统不会再加遮罩）。"""
    from PIL import ImageDraw

    art = im.resize((size, size), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    art.putalpha(mask)
    return art


def foreground(im: Image.Image, canvas: int) -> Image.Image:
    """把母版缩到 SCALE，居中贴到背景色画布上。"""
    inner = round(canvas * SCALE)
    art = im.resize((inner, inner), Image.LANCZOS)
    out = Image.new("RGB", (canvas, canvas), BG)
    off = (canvas - inner) // 2
    out.paste(art, (off, off))
    return out


def preview(im: Image.Image) -> None:
    """打印几档缩放在圆形遮罩下的效果，人工看图决定 SCALE。"""
    from PIL import ImageDraw

    out = Image.new("RGB", (3 * 300, 300), (245, 245, 245))
    for i, s in enumerate((0.72, 0.76, 0.80)):
        canvas = 300
        inner = round(canvas * s)
        panel = Image.new("RGB", (canvas, canvas), BG)
        panel.paste(im.resize((inner, inner), Image.LANCZOS),
                    ((canvas - inner) // 2, (canvas - inner) // 2))
        mask = Image.new("L", (canvas, canvas), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, canvas - 1, canvas - 1), fill=255)
        out.paste(panel, (i * canvas, 0), mask)
    dst = ROOT / "design/app-icon/preview-android-mask.png"
    out.save(dst)
    print(f"遮罩预览（0.72 / 0.76 / 0.80）→ {dst}")


def main() -> None:
    im = load_master()
    if "--preview" in sys.argv:
        preview(im)
        return

    for _density, size in LEGACY.items():
        d = RES / f"mipmap-{_density}"
        d.mkdir(parents=True, exist_ok=True)
        legacy(im, size).save(d / "ic_launcher.png", optimize=True)
        legacy_round(im, size).save(d / "ic_launcher_round.png", optimize=True)

    for density, canvas in ADAPTIVE.items():
        d = RES / f"mipmap-{density}"
        d.mkdir(parents=True, exist_ok=True)
        foreground(im, canvas).save(d / "ic_launcher_foreground.png", optimize=True)

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(ADAPTIVE_XML, encoding="utf-8")
    (anydpi / "ic_launcher_round.xml").write_text(ADAPTIVE_XML, encoding="utf-8")

    values = RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">#{BG[0]:02X}{BG[1]:02X}{BG[2]:02X}</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    print("已导出 Android 传统图标 + 自适应图标")


if __name__ == "__main__":
    main()
