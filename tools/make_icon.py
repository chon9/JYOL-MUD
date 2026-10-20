"""產生遊戲圖示：用擁有者提供的角色立繪裁胸像，放進紅底金框圓章（呼應右側燈籠選單）。
用法：python -I make_icon.py <src.png> <out_dir> [head_frac]
輸出：icon_1024.png（預覽）、icon.png（256，給 Godot 視窗）、icon.ico（16–256 多尺寸，給 .exe）"""
import sys, os
from PIL import Image, ImageDraw, ImageFilter

src, out = sys.argv[1], sys.argv[2]
head_frac = float(sys.argv[3]) if len(sys.argv) > 3 else 0.42
os.makedirs(out, exist_ok=True)
S = 1024

im = Image.open(src).convert("RGBA")
bbox = im.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
im = im.crop(bbox)
w, h = im.size
# 取上方 head_frac 的高度當胸像（頭＋肩），左右以頭部為中心取正方形
crop_h = int(h * head_frac)
top = im.crop((0, 0, w, crop_h))
# 頭部中心：上方 25% 高度內不透明像素的水平中心
head = top.crop((0, 0, w, max(1, int(crop_h * 0.55)))).getchannel("A").point(lambda a: 255 if a > 16 else 0)
hb = head.getbbox() or (0, 0, w, crop_h)
cx = (hb[0] + hb[2]) // 2
side = crop_h
left = max(0, min(w - side, cx - side // 2)) if w >= side else 0
bust = Image.new("RGBA", (side, side), (0, 0, 0, 0))
bust.paste(top.crop((left, 0, left + min(side, w), side)), ((side - min(side, w)) // 2, 0))

canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(canvas)
# 外金框、內暗紅底（和燈籠同色系），再一圈細金線
d.ellipse((8, 8, S - 8, S - 8), fill=(201, 160, 72, 255))
d.ellipse((44, 44, S - 44, S - 44), fill=(120, 22, 18, 255))
d.ellipse((64, 64, S - 64, S - 64), outline=(230, 196, 110, 255), width=10)
# 內圈淡淡的放射暗角，讓人物從底色浮出
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse((150, 150, S - 150, S - 150), fill=110)
glow = glow.filter(ImageFilter.GaussianBlur(120))
canvas = Image.composite(Image.new("RGBA", (S, S), (170, 52, 34, 255)), canvas, glow)

inner = S - 2 * 84
bust = bust.resize((inner, inner), Image.LANCZOS)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse((84, 84, S - 84, S - 84), fill=255)
layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
layer.paste(bust, (84, 96), bust)
layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", (S, S), 0), mask))
canvas = Image.alpha_composite(canvas, layer)
ImageDraw.Draw(canvas).ellipse((44, 44, S - 44, S - 44), outline=(90, 60, 20, 255), width=6)

canvas.save(os.path.join(out, "icon_1024.png"))
canvas.resize((256, 256), Image.LANCZOS).save(os.path.join(out, "icon.png"))
canvas.save(os.path.join(out, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("ok", bbox, (left, side))
