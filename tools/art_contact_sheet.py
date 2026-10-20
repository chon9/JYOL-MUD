#!/usr/bin/env python3
"""美術聯絡表（M3C_PLAN §2.5 第 7 點）：把單位 idle 圖依 art.json 的 scale 縮放，旁邊放 1.0 的 player_m 當比例尺，
底下寫 id 與 scale，給擁有者肉眼比對大小。只需要 Python 3 + Pillow。

用法（在專案根目錄）：
    python -I tools/art_contact_sheet.py [--out FILE] [--all] [--ids a,b,c] [--art-json FILE] [--art-dir DIR]

  * 預設涵蓋 M3c 第四批 47 條（§2.1）與 16 個初始造型（§2.2）；--all 涵蓋全部有 sprite 的條目。
  * 輸出到 --out（預設 K:/Project/JY-Mini-OL-Work/shots/m3c_art_contact.png）；一頁放不下時分頁 _2.png、_3.png…
  * 每格：左邊灰色的 player_m（1.0），右邊條目本身（scale 倍）；兩者腳底對齊同一條地平線。
"""
from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEF_OUT = "K:/Project/JY-Mini-OL-Work/shots/m3c_art_contact.png"
DEF_ART_JSON = os.path.join(ROOT, "data", "art.json")
DEF_ART_DIR = os.path.join(ROOT, "assets", "art")
FONT = os.path.join(ROOT, "assets", "fonts", "LXGWWenKaiTC-Regular.ttf")

BATCH4 = [
    "m_lf_zhizhu", "m_lf_xiezi", "m_lf_wugong", "m_lf_qingshe",
    "m_dl_mingjiao", "m_hn_mojiao", "m_xx_laodenuo", "m_ym_qiangdao",
    "n_xx_qiaofeng", "n_amb_etou_xe", "n_amb_etou_dlw", "n_amb_etou_ss", "n_ym_qiangdao", "n_ym_hufei", "n_wd_yuanye",
    "n_xx_palace_guard_l", "n_xx_palace_guard_r", "n_hn_longmen",
    "n_dl_cunmin", "n_dl_limochou", "n_dl_wangbutou", "n_dlw_guiyi", "n_hg_lincai", "n_hn_dizi", "n_hn_liugongzi",
    "n_hn_lulianrong", "n_hn_mimike", "n_hn_moda", "n_hn_teaman", "n_hs_chengbuyou", "n_hs_lanyihan",
    "n_hs_linghuchong", "n_lf_lanfenghuang", "n_lj_baiyong", "n_sl_daopin", "n_wd_yuanyin", "n_wd_zhaomin",
    "n_xd_pantu", "n_xx_abao", "n_xx_ada", "n_xx_azi", "n_xx_laodenuo", "n_xx_litaian", "n_xx_xuzhu", "n_xx_yuner",
    "n_xx_zhangbao", "n_ym_lingzhi",
]
LOOKS = ["look_%s%02d" % (g, n) for g in "mf" for n in range(1, 9)]

PX_PER_UNIT = 200      # 1.0 的人在聯絡表上的高度（畫布 256 → 200）
CANVAS_H = 256         # import_art.py 的角色畫布高度
CELL_W, CELL_H = 360, 330
COLS, ROWS = 6, 4
BG = (46, 42, 38)
GROUND = (120, 104, 84)
REF_TINT = 0.45


def load_font(size: int):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        try:
            return ImageFont.load_default(size=size)
        except TypeError:
            return ImageFont.load_default()


def sprite_of(units: dict, key: str) -> tuple[str | None, float]:
    """跟 ArtRegistry 一樣沿 alias 找：回傳 (sprite 名, scale)。scale 取鏈上第一個有 scale 的。"""
    scale = None
    k, seen = key, set()
    while k and k in units and k not in seen:
        seen.add(k)
        e = units[k]
        if scale is None and "scale" in e:
            scale = float(e["scale"])
        if e.get("sprite"):
            return e["sprite"], (scale if scale is not None else 1.0)
        k = e.get("alias", "")
    return None, (scale if scale is not None else 1.0)


def load_idle(art_dir: str, sprite: str) -> Image.Image | None:
    for sub in ("", "placeholder"):
        p = os.path.join(art_dir, sub, "units", "unit_%s_idle.png" % sprite) if sub else \
            os.path.join(art_dir, "units", "unit_%s_idle.png" % sprite)
        if os.path.isfile(p):
            return Image.open(p).convert("RGBA")
    return None


def scaled(img: Image.Image, scale: float) -> Image.Image:
    f = PX_PER_UNIT / CANVAS_H * scale
    return img.resize((max(1, round(img.width * f)), max(1, round(img.height * f))), Image.LANCZOS)


def dim(img: Image.Image) -> Image.Image:
    r, g, b, a = img.split()
    gray = Image.merge("RGB", (r, g, b)).convert("L").point(lambda v: int(v * REF_TINT + 60))
    out = Image.merge("RGBA", (gray, gray, gray, a.point(lambda v: int(v * 0.8))))
    return out


def build(ids: list[str], art: dict, art_dir: str) -> list[Image.Image]:
    units = art.get("units", {})
    ref_sprite, _ = sprite_of(units, "player_m")
    ref_img = load_idle(art_dir, ref_sprite or "player_m")
    ref = dim(scaled(ref_img, 1.0)) if ref_img is not None else None
    font, small = load_font(20), load_font(16)
    pages = []
    per = COLS * ROWS
    for p0 in range(0, len(ids), per):
        chunk = ids[p0:p0 + per]
        rows = (len(chunk) + COLS - 1) // COLS
        sheet = Image.new("RGBA", (COLS * CELL_W, rows * CELL_H), BG + (255,))
        d = ImageDraw.Draw(sheet)
        for i, key in enumerate(chunk):
            cx, cy = (i % COLS) * CELL_W, (i // COLS) * CELL_H
            ground = cy + CELL_H - 70
            d.rectangle([cx, cy, cx + CELL_W - 1, cy + CELL_H - 1], outline=(70, 64, 58))
            d.line([cx + 10, ground, cx + CELL_W - 10, ground], fill=GROUND, width=2)
            # 1.0 刻度線
            d.line([cx + 10, ground - PX_PER_UNIT, cx + 40, ground - PX_PER_UNIT], fill=(150, 130, 100), width=1)
            if ref is not None:
                sheet.alpha_composite(ref, (cx + 90 - ref.width // 2, ground - ref.height))
            sprite, scale = sprite_of(units, key)
            img = load_idle(art_dir, sprite) if sprite else None
            if img is not None:
                s = scaled(img, scale)
                sheet.alpha_composite(s, (cx + 240 - s.width // 2, ground - s.height))
            else:
                d.text((cx + 190, ground - 40), "(no art)", fill=(220, 80, 60), font=small)
            own = sprite == key
            d.text((cx + 10, ground + 8), key, fill=(240, 226, 200), font=font)
            d.text((cx + 10, ground + 36), "scale %.2f%s" % (scale, "" if own else "  → %s" % sprite),
                   fill=(200, 180, 140) if own else (220, 120, 90), font=small)
        pages.append(sheet)
    return pages


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=DEF_OUT)
    ap.add_argument("--all", action="store_true", help="every units entry that has its own sprite")
    ap.add_argument("--ids", default="", help="comma separated ids instead of the default list")
    ap.add_argument("--art-json", default=DEF_ART_JSON)
    ap.add_argument("--art-dir", default=DEF_ART_DIR)
    args = ap.parse_args(argv)
    with open(args.art_json, encoding="utf-8") as f:
        art = json.load(f)
    if args.ids:
        ids = [x.strip() for x in args.ids.split(",") if x.strip()]
    elif args.all:
        ids = [k for k, e in art.get("units", {}).items() if isinstance(e, dict) and e.get("sprite")]
    else:
        ids = BATCH4 + LOOKS
    pages = build(ids, art, args.art_dir)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    stem, ext = os.path.splitext(args.out)
    for i, page in enumerate(pages):
        path = args.out if i == 0 else "%s_%d%s" % (stem, i + 1, ext or ".png")
        page.convert("RGB").save(path)
        print("wrote", path)
    print("entries:", len(ids), "pages:", len(pages))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
