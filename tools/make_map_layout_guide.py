"""產生「江湖全圖」構圖參考圖，給 ChatGPT 照著畫手繪地圖（docs/ART_REQUEST.md §10）。
地點座標取自 data/regions.json 的 world_pos（0–1000，原作 2001 座標 ÷ 24），地形分區是依原作地理大略標出。
用法：python -I tools/make_map_layout_guide.py   → docs/map_layout_guide.png（有字，給人看）、docs/map_layout_guide_nolabel.png（無字，給 ChatGPT）"""
import json, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 1600, 1200                      # 4:3，和原作座標比例一致
FONT = os.path.join(ROOT, "assets", "fonts", "LXGWWenKaiTC-Regular.ttf")
regions = json.load(open(os.path.join(ROOT, "data", "regions.json"), encoding="utf-8"))["rows"]

def P(x, y):                           # world_pos(0..1000) → 畫布像素（留 60px 邊）
    return (60 + x / 1000 * (W - 120), 60 + y / 1000 * (H - 120))

def blob(draw, cx, cy, rx, ry, color):
    x, y = P(cx, cy); sx = rx / 1000 * (W - 120); sy = ry / 1000 * (H - 120)
    draw.ellipse((x - sx, y - sy, x + sx, y + sy), fill=color)

def build(labels: bool) -> Image.Image:
    base = Image.new("RGBA", (W, H), (226, 211, 176, 255))
    zones = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    z = ImageDraw.Draw(zones)
    # 地形分區（大略）：沙漠／雪山／山脈／森林／湖
    for cx, cy, rx, ry in [(120, 90, 140, 90), (170, 330, 120, 150), (60, 470, 80, 120)]:
        blob(z, cx, cy, rx, ry, (214, 178, 110, 200))      # 大漠、高昌、星宿、血刀西陲
    for cx, cy, rx, ry in [(210, 30, 120, 50), (60, 500, 60, 70), (330, 70, 60, 40)]:
        blob(z, cx, cy, rx, ry, (236, 242, 248, 230))      # 天山雪峰、血刀雪山、西夏北郊雪地
    for cx, cy, rx, ry in [(720, 400, 160, 120), (850, 360, 70, 60), (600, 590, 90, 70), (940, 650, 60, 70), (630, 260, 60, 40)]:
        blob(z, cx, cy, rx, ry, (128, 140, 110, 210))      # 中原山脈：華山、終南、武當、峨嵋、衡山、恆山
    for cx, cy, rx, ry in [(470, 650, 110, 90), (860, 240, 80, 50)]:
        blob(z, cx, cy, rx, ry, (110, 150, 95, 190))       # 峨嵋道林區、絕情谷
    blob(z, 230, 760, 45, 35, (120, 160, 190, 235))        # 洱海（大理旁）
    zones = zones.filter(ImageFilter.GaussianBlur(28))
    base = Image.alpha_composite(base, zones)
    d = ImageDraw.Draw(base)
    # 河流（藍色細線）：西夏南坡沿河川古道到大理；衡陽一帶
    for pts in [[(300, 160), (262, 214), (230, 330), (196, 560), (240, 700), (230, 760)],
                [(880, 470), (900, 520), (943, 678), (960, 760)],
                [(420, 118), (520, 200), (610, 275), (705, 350), (850, 330), (980, 300)]]:
        d.line([P(*p) for p in pts], fill=(90, 130, 170, 255), width=7, joint="curve")
    font = ImageFont.truetype(FONT, 26) if labels else None
    small = ImageFont.truetype(FONT, 20) if labels else None
    for r in regions:
        wp = r.get("world_pos")
        if not wp:
            continue
        x, y = P(*wp)
        t = r.get("type", "")
        rad = 16 if t == "CITY" else 12 if t in ("SECT", "DUNGEON") else 7
        col = {"CITY": (170, 30, 30), "SECT": (40, 40, 40), "DUNGEON": (90, 40, 110)}.get(t, (110, 90, 60))
        # 留一塊空地（給遊戲疊上地點標記），只畫空心圓
        d.ellipse((x - rad, y - rad, x + rad, y + rad), outline=col + (255,), width=4)
        if labels:
            f = font if t in ("CITY", "SECT") else small
            d.text((x + rad + 4, y - 14), r["name"], fill=(40, 30, 20, 255), font=f)
    if labels:
        legend = "構圖參考：紅圈＝城市、黑圈＝門派、紫圈＝洞窟迷宮、小圈＝野外；黃褐＝大漠、白＝雪山、灰綠＝山脈、綠＝林地、藍＝河湖"
        d.text((60, H - 46), legend, fill=(60, 40, 20, 255), font=small)
    return base

os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
build(True).convert("RGB").save(os.path.join(ROOT, "docs", "map_layout_guide.png"))
build(False).convert("RGB").save(os.path.join(ROOT, "docs", "map_layout_guide_nolabel.png"))
print("ok")
