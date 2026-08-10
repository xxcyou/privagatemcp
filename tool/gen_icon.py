#!/usr/bin/env python3
"""PrivaGate MCP 图标 v3「暗夜霓虹锁」
- 背景：深紫→藏青对角渐变 + 中心紫光晕 + 右下青辉光（legacy 与 adaptive 完全一致）
- 前景：粗壮白色圆润锁（一体式锁梁+锁体）+ 品牌紫锁孔 + 底部青色反光
- 4x 超采样抗锯齿；图形严格落在 adaptive 安全区内（66~126/192）
输出：legacy PNG 5 密度 + adaptive foreground 432px + monochrome 432px + 预览 512px
"""
import os, math
from PIL import Image, ImageDraw, ImageFilter

# 配色
BG_A   = (42, 24, 88)    # 深紫
BG_B   = (13, 27, 60)    # 藏青
GLOW   = (123, 92, 255)  # 紫光晕
CYAN   = (0, 212, 255)   # 品牌青
LOCK_C = (255, 255, 255) # 锁体白
KEY_C  = (106, 75, 255)  # 锁孔品牌紫
SS = 4                    # 超采样

def diag_gradient(size, c1, c2):
    """45° 对角渐变：左上 c1 → 右下 c2（逐行线性插值）"""
    img = Image.new('RGB', (size, size))
    d = ImageDraw.Draw(img)
    step = max(1, size // 256)
    for y in range(0, size, step):
        for x in range(0, size, step):
            t = (x + y) / (2 * (size - 1))
            c = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
            d.rectangle([x, y, x + step - 1, y + step - 1], fill=c)
    return img

def radial_glow(size, cx, cy, radius, color, strength=0.5, power=2.0):
    """径向光晕（alpha 随距离二次衰减 + 高斯模糊）"""
    glow = Image.new('L', (size, size), 0)
    gd = ImageDraw.Draw(glow)
    step = max(1, radius // 64)
    for r in range(radius, 0, -step):
        a = int(255 * strength * (1 - r / radius) ** power)
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=a)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.045))
    overlay = Image.new('RGB', (size, size), color)
    return Image.composite(overlay, Image.new('RGB', (size, size), (0, 0, 0)), glow)

def draw_lock_layer(S, u, with_bg_glow=True):
    """绘制锁本体（透明底）。with_bg_glow=True 时含底部青色反光。"""
    lay = Image.new('RGBA', (S, S), (0, 0, 0, 0))

    # 锁底部青色反光（柔和，让锁有悬浮感）
    if with_bg_glow:
        ref = Image.new('L', (S, S), 0)
        rd = ImageDraw.Draw(ref)
        rd.ellipse([72 * u, 112 * u, 120 * u, 148 * u], fill=100)
        ref = ref.filter(ImageFilter.GaussianBlur(9 * u))
        cyan = Image.new('RGBA', (S, S), CYAN + (0,))
        ref_rgba = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        ref_rgba.putalpha(ref)
        lay = Image.alpha_composite(lay, Image.composite(cyan, ref_rgba, ref).convert('RGBA'))

    # 投影（锁整体）
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([70 * u, 64 * u, 122 * u, 130 * u], radius=14 * u, fill=(0, 0, 0, 140))
    shadow = shadow.filter(ImageFilter.GaussianBlur(6 * u))
    lay = Image.alpha_composite(lay, shadow)

    d = ImageDraw.Draw(lay)

    # ── 锁梁：粗圆弧（外半径 18，线宽 12，圆心 96,90；外缘 66~126 安全区内）──
    lx, ly = 96 * u, 89 * u
    lr, lw = 16.5 * u, 11 * u
    d.arc([lx - lr, ly - lr, lx + lr, ly + lr], start=180, end=360,
          fill=LOCK_C + (255,), width=int(lw))
    # 弧端圆头（PIL arc 两端是平的，补两个圆）
    for sx in (-1, 1):
        d.ellipse([lx + sx * lr - lw / 2, ly - lw / 2,
                   lx + sx * lr + lw / 2, ly + lw / 2], fill=LOCK_C + (255,))

    # ── 锁体：圆角矩形（略宽于锁梁，稳重）──
    body = [71 * u, 87 * u, 121 * u, 125 * u]
    d.rounded_rectangle(body, radius=12 * u, fill=LOCK_C + (255,))

    # ── 锁孔：品牌紫（圆 + 钥匙槽）──
    kx, ky = lx, 101 * u
    d.ellipse([kx - 6 * u, ky - 6 * u, kx + 6 * u, ky + 6 * u], fill=KEY_C + (255,))
    d.rounded_rectangle([kx - 3.2 * u, ky + 6 * u, kx + 3.2 * u, ky + 16 * u],
                        radius=3 * u, fill=KEY_C + (255,))

    return lay

def draw_icon(size):
    """完整图标（背景 + 光晕 + 锁），size 为最终输出尺寸"""
    S = size * SS
    u = S / 192.0
    # 1. 渐变底
    img = diag_gradient(S, BG_A, BG_B)
    # 2. 中心紫光晕
    glow = radial_glow(S, S * 0.5, S * 0.45, int(S * 0.60), GLOW, 0.42)
    img = Image.blend(img, glow, 0.55)
    # 3. 右下青色微光
    glow2 = radial_glow(S, S * 0.72, S * 0.78, int(S * 0.42), CYAN, 0.22)
    img = Image.blend(img, glow2, 0.40)
    # 4. 锁
    lock = draw_lock_layer(S, u)
    img = Image.alpha_composite(img.convert('RGBA'), lock)
    return img.resize((size, size), Image.LANCZOS)

BASE = 'android/app/src/main/res'

# legacy PNG（全背景）
for name, sz in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    icon = draw_icon(sz)
    icon.convert('RGB').save(f'{BASE}/mipmap-{name}/ic_launcher.png')
    print('生成', f'mipmap-{name}/ic_launcher.png')

# adaptive foreground：透明底，仅锁 + 反光（安全区内）
S = 432
sc = S / 192.0
fg = draw_lock_layer(S, sc, with_bg_glow=False)
fg.save(f'{BASE}/drawable/ic_launcher_foreground.png')
print('生成 adaptive foreground 432px')

# monochrome（Android 13+ 主题图标）：纯白锁
mono = Image.new('RGBA', (S, S), (0, 0, 0, 0))
md = ImageDraw.Draw(mono)
lx, ly, lr, lw = 96 * sc, 89 * sc, 16.5 * sc, 11 * sc
md.arc([lx - lr, ly - lr, lx + lr, ly + lr], 180, 360, fill=(255, 255, 255, 255), width=int(lw))
for sx in (-1, 1):
    md.ellipse([lx + sx * lr - lw / 2, ly - lw / 2, lx + sx * lr + lw / 2, ly + lw / 2],
               fill=(255, 255, 255, 255))
md.rounded_rectangle([71 * sc, 87 * sc, 121 * sc, 125 * sc], radius=12 * sc, fill=(255, 255, 255, 255))
mono.save(f'{BASE}/drawable/ic_launcher_monochrome.png')
print('生成 monochrome 432px')

# 预览 512px
draw_icon(512).convert('RGB').save('/tmp/priva_gate_preview_v3.png')
print('预览图 /tmp/priva_gate_preview_v3.png')

# ── App 内品牌图标(完整图标,首页/设置/关于页圆角显示,与桌面图标一致)──
import os as _os
_os.makedirs('assets/brand', exist_ok=True)
for _name, _sz in [('app_icon.png', 256), ('app_icon@2x.png', 512)]:
    draw_icon(_sz).convert('RGB').save(f'assets/brand/{_name}')
    print('生成', f'assets/brand/{_name}')
