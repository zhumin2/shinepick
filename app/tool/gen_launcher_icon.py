#!/usr/bin/env python3
"""生成拾光 App 图标：琥珀圆角方块 + 白色描边太阳（对齐登录页 Logo）。

输出：
- mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png  传统方形图标（圆角）
- mipmap-*/ic_launcher_foreground.png                     自适应图标前景（透明底太阳）
- mipmap-anydpi-v26/ic_launcher.xml                       自适应图标声明
- values/colors.xml                                       ic_launcher_background

用 4 倍超采样后缩放，得到平滑边缘。
"""
import math
import os

from PIL import Image, ImageDraw

# 与 app_theme.dart / 登录页 Logo 一致的 token
AMBER = (232, 155, 60, 255)  # #E89B3C primary
WHITE = (255, 255, 255, 255)

SS = 4  # 超采样倍数
DENSITIES = {  # Android 传统图标边长（dp -> px）
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
ADAPTIVE_DP = 108  # 自适应图标画布
SUN_RATIO = 0.53  # 传统图标：太阳外径 / 图标边长（与登录页 34/64 一致）
# 自适应图标：圆形遮罩会裁掉四角，太阳按可见区的更大比例绘制才不显空
ADAPTIVE_SUN_RATIO = 0.62


def draw_sun(draw, cx, cy, outer_r, stroke):
    """画描边太阳：中心圆环 + 8 条圆头射线。"""
    ring_r = outer_r * 0.52  # 中心圆环半径
    ray_inner = ring_r + outer_r * 0.16
    ray_outer = outer_r * 0.95
    # 中心圆环（描边）
    draw.ellipse(
        [cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r],
        outline=WHITE,
        width=stroke,
    )
    # 8 条射线
    for i in range(8):
        a = math.radians(i * 45)
        x1 = cx + math.cos(a) * ray_inner
        y1 = cy + math.sin(a) * ray_inner
        x2 = cx + math.cos(a) * ray_outer
        y2 = cy + math.sin(a) * ray_outer
        draw.line([x1, y1, x2, y2], fill=WHITE, width=stroke)
        # 圆头：在线段两端画圆补齐（ImageDraw.line 无 cap 参数）
        for (px, py) in ((x1, y1), (x2, y2)):
            draw.ellipse(
                [px - stroke / 2, py - stroke / 2, px + stroke / 2, py + stroke / 2],
                fill=WHITE,
            )


def legacy_icon(size):
    """传统图标：琥珀圆角方块 + 太阳（圆角半径 28%）。"""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    radius = int(s * 0.28)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=radius, fill=AMBER)
    sun_r = s * SUN_RATIO / 2
    draw_sun(d, s / 2, s / 2, sun_r, stroke=max(2, int(s * 0.052)))
    return img.resize((size, size), Image.LANCZOS)


def adaptive_foreground(size_dp):
    """自适应前景：透明底 + 太阳，缩进到 66dp 安全区（画布 108dp）。"""
    s = size_dp * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 可见区约 72dp/108dp，太阳按可见区比例绘制
    visible = s * 72 / ADAPTIVE_DP
    sun_r = visible * ADAPTIVE_SUN_RATIO / 2
    draw_sun(
        d,
        s / 2,
        s / 2,
        sun_r,
        stroke=max(2, int(visible * 0.055)),
    )
    return img.resize((size_dp, size_dp), Image.LANCZOS)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # app/
    res = os.path.join(root, "android", "app", "src", "main", "res")
    for density, px in DENSITIES.items():
        out_dir = os.path.join(res, f"mipmap-{density}")
        os.makedirs(out_dir, exist_ok=True)
        legacy_icon(px).save(os.path.join(out_dir, "ic_launcher.png"))
        # 自适应前景按 108dp 画布输出对应 px
        fg_px = round(ADAPTIVE_DP * px / 48)
        adaptive_foreground(fg_px).save(
            os.path.join(out_dir, "ic_launcher_foreground.png")
        )
        print(f"{density}: legacy {px}px, foreground {fg_px}px")

    anydpi = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, "ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            "</adaptive-icon>\n"
        )

    values = os.path.join(res, "values")
    os.makedirs(values, exist_ok=True)
    colors_path = os.path.join(values, "colors.xml")
    if not os.path.exists(colors_path):
        with open(colors_path, "w", encoding="utf-8") as f:
            f.write(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                "<resources>\n"
                '    <color name="ic_launcher_background">#E89B3C</color>\n'
                "</resources>\n"
            )
        print("values/colors.xml 已创建")
    print("完成")


if __name__ == "__main__":
    main()
