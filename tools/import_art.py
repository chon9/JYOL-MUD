#!/usr/bin/env python3
"""美術匯入工具（docs/ART_REQUEST.md）。只需要 Python 3 + Pillow 10。

用法（在專案根目錄）：
    python -I tools/import_art.py                 # 處理 assets/art_in/ → assets/art/，更新 data/art.json 的 placeholder 旗標
    python -I tools/import_art.py --placeholders  # 重新產生暫代圖到 assets/art/placeholder/
    python -I tools/import_art.py --inbox DIR --out DIR --art-json FILE --no-json-update   # 測試用
    python -I tools/import_art.py --snapshot      # 「空手重畫前」快照（玩家／造型／門派服裝的圖）後結束
    python -I tools/import_art.py --only "fx_weapon_*" --only "icon_weapon_*"   # 只處理符合的檔名

覆寫備份（M3C_PLAN §2.5）：寫任何輸出檔之前，若目的檔存在且內容不同，先複製到
<--backup-root>/<YYYY-MM-DD>/<子目錄>/<檔名>（同名已存在且內容不同時加 -HHMMSS）；備份失敗＝該檔不覆寫。

做的事：
  * 依檔名分類：bg_<region>.png、unit_<id>_<pose>.png、fx_<name>.png、tile_escape.png；
    M3c：map_*.png（地圖美術）、fx_weapon_*.png／fx_skill_*.png（武器特效）、icon_weapon_*.png（武器小圖示）；
    其餘檔名警告後略過。
  * 檢查尺寸；角色／特效要有透明背景。沒有透明但背景是接近單色 → 從四個角 flood-fill 去背並警告；
    背景不是單色 → 錯誤並略過。
  * 角色：裁掉透明邊、art.json 標 "flip": true 的左右翻轉、等比縮放到固定高度的畫布（腳在底部中央）。
  * 背景：cover 縮放＋置中裁切成 1920x1080。
  * 特效：裁邊後等比放進 512x512（tile_escape 512x256）。
  * 地圖：map_world_base cover 2400x1800（偏離 4:3 超過 1% 警告）；map_region_bg cover 1024x1024；
    房間框 384x192、標題框 1024x256 不裁邊；你在這裡／圖示 256x256、羅盤 512x512 裁邊後置中。
    武器特效 1024x512 裁邊後靠左、垂直置中（起點＝手＝左緣中點）；武器圖示 256x256 裁邊後置中。
  * 輸出到 <out>/units/、<out>/bg/、<out>/fx/、<out>/map/、<out>/icons/；內容相同就不重寫（可重複執行）。
  * 依 art.json 列出需求清單的狀態（已有正式圖／本次匯入／暫代圖／缺）。
"""
from __future__ import annotations

import argparse
import datetime
import fnmatch
import io
import json
import math
import os
import random
import shutil
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEF_INBOX = os.path.join(ROOT, "assets", "art_in")
DEF_OUT = os.path.join(ROOT, "assets", "art")
DEF_ART_JSON = os.path.join(ROOT, "data", "art.json")
DEF_BACKUP_ROOT = "K:/Project/JY-Mini-OL-Work/art_backup"

UNIT_H = 256            # 角色正規化畫布高度（px）；腳貼底、水平置中
UNIT_TOP_PAD = 4
UNIT_SIDE_PAD = 4
UNIT_SRC_SIZE = 1024    # 需求規格
BG_W, BG_H = 1920, 1080
FX_SIZE = {"tile_escape": (512, 256)}
FX_DEFAULT = (512, 512)
POSES = ("idle", "attack", "hurt")
ALPHA_TRIM = 10         # 透明度低於此值視為透明（裁邊用）
BG_TOL = 34             # 去背：與背景色的容許差
UNIFORM_MIN = 0.90      # 去背：邊框像素有多少比例接近背景色才算「單色背景」

# ---- M3c（M3C_PLAN §2.3、§2.5）：地圖美術、武器特效、武器小圖示
MAP_KEYS = ("world_base", "region_bg", "node_room", "node_current", "node_fog", "marker_here", "compass", "frame_title")
MAP_ICON_KEYS = ("city", "sect", "cave", "wild", "station", "inn", "shop", "master", "record", "field", "wood",
                 "water", "stove", "danger", "quest", "exit")
WEAPON_FX_KEYS = ("sword", "blade", "staff", "whip", "fist", "claw", "stab", "hidden")
SKILL_FX_KEYS = ("inner", "poison", "medic", "formation")
WEAPON_ICON_KEYS = ("sword", "blade", "staff", "whip", "claw", "fist")
# 檔名 → (處理方式, 尺寸)。cover＝cover 縮放置中裁切（可不透明）；frame＝要透明、不裁邊、contain 置中；
# trim＝要透明、裁邊後 contain 置中；trim_left＝要透明、裁邊後靠左、垂直置中
MAP_SPEC = {"map_world_base": ("cover", (2400, 1800)), "map_region_bg": ("cover", (1024, 1024)),
            "map_node_room": ("frame", (384, 192)), "map_node_current": ("frame", (384, 192)),
            "map_node_fog": ("frame", (384, 192)), "map_marker_here": ("trim", (256, 256)),
            "map_compass": ("trim", (512, 512)), "map_frame_title": ("frame", (1024, 256))}
MAP_SPEC.update({"map_icon_" + k: ("trim", (256, 256)) for k in MAP_ICON_KEYS})
WEAPON_FX_SPEC = {"fx_weapon_" + k: ("trim_left", (1024, 512)) for k in WEAPON_FX_KEYS}
WEAPON_FX_SPEC.update({"fx_skill_" + k: ("trim_left", (1024, 512)) for k in SKILL_FX_KEYS})
WEAPON_ICON_SPEC = {"icon_weapon_" + k: ("trim", (256, 256)) for k in WEAPON_ICON_KEYS}
# art.json 區塊 → 輸出子資料夾
FILE_SECTIONS = {"map": "map", "map_icons": "map", "weapon_fx": "fx", "weapon_icons": "icons"}
WORLD_ASPECT_TOL = 0.01
# 「空手重畫前」快照涵蓋的檔名前綴（unit_<前綴>_*）
SNAPSHOT_PREFIXES = ("player", "look", "shaolin", "huashan", "wudang", "quanzhen", "xuedao", "xingxiu", "emei",
                     "hengshan", "gumu", "lingjiu", "gaibang")


class Report:
    def __init__(self) -> None:
        self.warnings: list[str] = []
        self.errors: list[str] = []
        self.written: list[str] = []
        self.unchanged: list[str] = []
        self.imported: set[str] = set()   # 本次成功處理的輸出檔名
        self.backups: list[str] = []      # 覆寫前備份出去的檔
        self.backup_root: str | None = None   # None = 不備份（--no-backup，只給單元測試）
        self.out_root: str | None = None
        self.today = datetime.date.today().strftime("%Y-%m-%d")

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def error(self, msg: str) -> None:
        self.errors.append(msg)


# ---------------------------------------------------------------- 共用影像處理

def has_real_alpha(img: Image.Image) -> bool:
    if img.mode not in ("RGBA", "LA", "PA") and not (img.mode == "P" and "transparency" in img.info):
        return False
    a = img.convert("RGBA").getchannel("A")
    lo, _hi = a.getextrema()
    return lo < 250


def _border_pixels(img: Image.Image) -> list[tuple]:
    w, h = img.size
    px = img.load()
    step = max(1, min(w, h) // 128)
    out = []
    for x in range(0, w, step):
        out.append(px[x, 0])
        out.append(px[x, h - 1])
    for y in range(0, h, step):
        out.append(px[0, y])
        out.append(px[w - 1, y])
    return out


def _median_color(pixels: list[tuple]) -> tuple:
    chans = list(zip(*pixels))
    return tuple(sorted(c)[len(c) // 2] for c in chans[:3])


def _close(c: tuple, ref: tuple, tol: int) -> bool:
    return max(abs(c[0] - ref[0]), abs(c[1] - ref[1]), abs(c[2] - ref[2])) <= tol


def remove_uniform_background(img: Image.Image, name: str, rep: Report) -> Image.Image | None:
    """不透明且背景接近單色：從四角 flood-fill 去背。背景不單色時回 None。"""
    rgb = img.convert("RGB")
    border = _border_pixels(rgb)
    bg = _median_color(border)
    near = sum(1 for p in border if _close(p, bg, BG_TOL))
    if near / max(1, len(border)) < UNIFORM_MIN:
        rep.error("%s: no transparency and the background is not a flat color; regenerate with a transparent background" % name)
        return None
    # 與背景色相近的像素 → 255，其餘 0；再從四角把「相連的」相近像素填成 128
    diff = ImageChops.difference(rgb, Image.new("RGB", rgb.size, bg))
    r, g, b = diff.split()
    dmax = ImageChops.lighter(ImageChops.lighter(r, g), b)
    similar = dmax.point(lambda v: 255 if v <= BG_TOL else 0)
    w, h = similar.size
    for xy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if similar.getpixel(xy) == 255:
            ImageDraw.floodfill(similar, xy, 128, thresh=0)
    bgmask = similar.point(lambda v: 255 if v == 128 else 0)
    alpha = ImageChops.invert(bgmask).filter(ImageFilter.GaussianBlur(0.8))
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    rep.warn("%s: opaque flat background %s removed by flood-fill from the corners; please check the edges" % (name, "#%02x%02x%02x" % bg))
    return out


def ensure_alpha(img: Image.Image, name: str, rep: Report) -> Image.Image | None:
    if has_real_alpha(img):
        return img.convert("RGBA")
    return remove_uniform_background(img, name, rep)


def trim(img: Image.Image) -> Image.Image | None:
    a = img.getchannel("A").point(lambda v: 255 if v >= ALPHA_TRIM else 0)
    box = a.getbbox()
    if box is None:
        return None
    return img.crop(box)


def resize_rgba(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    # 預乘 alpha 再縮放，避免透明邊出現黑邊
    return img.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


def normalize_unit(img: Image.Image, flip: bool = False) -> Image.Image | None:
    t = trim(img)
    if t is None:
        return None
    if flip:
        t = t.transpose(Image.FLIP_LEFT_RIGHT)
    tw, th = t.size
    target_h = UNIT_H - UNIT_TOP_PAD
    s = target_h / th
    nw = max(1, round(tw * s))
    t = resize_rgba(t, (nw, target_h))
    cw = nw + 2 * UNIT_SIDE_PAD
    cw += cw % 2
    canvas = Image.new("RGBA", (cw, UNIT_H), (0, 0, 0, 0))
    canvas.alpha_composite(t, ((cw - nw) // 2, UNIT_H - target_h))
    return canvas


def cover(img: Image.Image, w: int, h: int) -> Image.Image:
    img = img.convert("RGB")
    sw, sh = img.size
    s = max(w / sw, h / sh)
    nw, nh = max(w, round(sw * s)), max(h, round(sh * s))
    img = img.resize((nw, nh), Image.LANCZOS)
    x0, y0 = (nw - w) // 2, (nh - h) // 2
    return img.crop((x0, y0, x0 + w, y0 + h))


def contain_rgba(img: Image.Image, w: int, h: int, align_left: bool = False) -> Image.Image:
    sw, sh = img.size
    s = min(w / sw, h / sh)
    nw, nh = max(1, round(sw * s)), max(1, round(sh * s))
    r = resize_rgba(img, (nw, nh))
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    canvas.alpha_composite(r, (0 if align_left else (w - nw) // 2, (h - nh) // 2))
    return canvas


def backup_subdir(path: str, rep: Report) -> str:
    """備份用子目錄：輸出根目錄下的相對資料夾（units、bg、fx、map、icons、placeholder/units…）"""
    d = os.path.dirname(os.path.abspath(path))
    if rep.out_root:
        rel = os.path.relpath(d, os.path.abspath(rep.out_root))
        if not rel.startswith(".."):
            return "root" if rel == "." else rel.replace(os.sep, "/")
    return os.path.basename(d)


def backup_existing(path: str, rep: Report) -> bool:
    """覆寫前把舊檔複製到 <backup_root>/<日期>/<子目錄>/<檔名>。成功（或不需要備份）回 True。"""
    if rep.backup_root is None:
        return True
    try:
        with open(path, "rb") as f:
            old = f.read()
        dest_dir = os.path.join(rep.backup_root, rep.today, backup_subdir(path, rep))
        os.makedirs(dest_dir, exist_ok=True)
        name = os.path.basename(path)
        dest = os.path.join(dest_dir, name)
        if os.path.exists(dest):
            with open(dest, "rb") as f:
                if f.read() == old:
                    return True   # 同一份舊圖今天已經備份過
            stem, ext = os.path.splitext(name)
            stamp = datetime.datetime.now().strftime("%H%M%S")
            dest = os.path.join(dest_dir, "%s-%s%s" % (stem, stamp, ext))
            n = 1
            while os.path.exists(dest):
                dest = os.path.join(dest_dir, "%s-%s-%d%s" % (stem, stamp, n, ext))
                n += 1
        with open(dest, "wb") as f:
            f.write(old)
        with open(dest, "rb") as f:
            if f.read() != old:
                raise OSError("backup verify failed")
        rep.backups.append(dest)
        return True
    except OSError as ex:
        rep.error("%s: backup before overwrite failed (%s); file NOT overwritten" % (path, ex))
        return False


def save_png(img: Image.Image, path: str, rep: Report | None) -> None:
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    data = buf.getvalue()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        with open(path, "rb") as f:
            if f.read() == data:
                if rep is not None:
                    rep.unchanged.append(path)
                return
        if rep is not None and not backup_existing(path, rep):
            return
    with open(path, "wb") as f:
        f.write(data)
    if rep is not None:
        rep.written.append(path)


# ---------------------------------------------------------------- art.json

def load_art_json(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def dump_art_json(art: dict) -> str:
    return json.dumps(art, ensure_ascii=False, indent=2) + "\n"


def unit_sprites(art: dict) -> dict:
    """sprite 基底名 → 條目（只算有自己 sprite 的條目，alias 不算）"""
    out = {}
    for key, e in art.get("units", {}).items():
        if isinstance(e, dict) and e.get("sprite"):
            out[e["sprite"]] = (key, e)
    return out


def bg_files(art: dict) -> dict:
    out = {}
    for key, e in art.get("backgrounds", {}).items():
        if isinstance(e, dict) and e.get("bg"):
            out[e["bg"]] = (key, e)
    return out


def fx_files(art: dict) -> dict:
    out = {}
    for key, e in art.get("fx", {}).items():
        if isinstance(e, dict) and e.get("file"):
            out[e["file"]] = (key, e)
    return out


def section_files(art: dict, section: str) -> dict:
    """M3c 檔名區塊（map、map_icons、weapon_fx、weapon_icons）：file → (鍵, 條目)"""
    out = {}
    sec = art.get(section, {})
    if isinstance(sec, dict):
        for key, e in sec.items():
            if isinstance(e, dict) and e.get("file"):
                out[e["file"]] = (key, e)
    return out


def request_list(art: dict) -> list[tuple[str, str, bool]]:
    """(子資料夾, 檔名, 必要) — 依 art.json 產生需求清單"""
    req = []
    for sprite, (_k, e) in sorted(unit_sprites(art).items()):
        for pose in POSES:
            req.append(("units", "unit_%s_%s.png" % (sprite, pose), bool(e.get("required", False)) and pose == "idle"))
    for bg, (_k, e) in sorted(bg_files(art).items()):
        req.append(("bg", "bg_%s.png" % bg, bool(e.get("required", True))))
    for f, (_k, e) in sorted(fx_files(art).items()):
        req.append(("fx", "%s.png" % f, bool(e.get("required", False))))
    for section, sub in FILE_SECTIONS.items():
        for f, (_k, e) in sorted(section_files(art, section).items()):
            req.append((sub, "%s.png" % f, bool(e.get("required", False))))
    return req


# ---------------------------------------------------------------- 匯入

def classify(fname: str, art: dict) -> tuple[str, dict] | None:
    base = fname[:-4]
    if base.startswith("map_"):
        if base in MAP_SPEC:
            return "map", {"name": base}
        return "bad", {"why": "unknown map art name (see ART_REQUEST §10 / M3C_PLAN §2.3)"}
    if base.startswith("fx_weapon_") or base.startswith("fx_skill_"):
        if base in WEAPON_FX_SPEC:
            return "weapon_fx", {"name": base}
        return "bad", {"why": "unknown weapon effect name (see ART_REQUEST §11.2)"}
    if base.startswith("icon_weapon_"):
        if base in WEAPON_ICON_SPEC:
            return "weapon_icon", {"name": base}
        return "bad", {"why": "unknown weapon icon name (see ART_REQUEST §11.3)"}
    if base.startswith("bg_"):
        return "bg", {"name": base[3:]}
    if base.startswith("unit_"):
        rest = base[5:]
        for pose in POSES:
            if rest.endswith("_" + pose):
                return "unit", {"id": rest[: -len(pose) - 1], "pose": pose}
        return "bad", {"why": "unit file must end with _idle/_attack/_hurt"}
    if base.startswith("fx_") or base == "tile_escape":
        return "fx", {"name": base}
    return None


def import_inbox(inbox: str, out: str, art: dict, rep: Report, only: list[str] | None = None) -> None:
    if not os.path.isdir(inbox):
        rep.warn("inbox %s does not exist" % inbox)
        return
    units = art.get("units", {})
    known_bg = set(bg_files(art).keys()) | set(art.get("backgrounds", {}).keys())
    known_fx = set(fx_files(art).keys())
    for fname in sorted(os.listdir(inbox)):
        path = os.path.join(inbox, fname)
        if not os.path.isfile(path):
            continue
        low = fname.lower()
        if low in ("readme.txt", ".gdignore") or low.endswith(".import"):
            continue
        if only and not any(fnmatch.fnmatch(low, pat.lower()) for pat in only):
            continue
        if not low.endswith(".png"):
            rep.warn("%s: not a .png, skipped" % fname)
            continue
        if fname != low:
            rep.warn("%s: file names should be lower-case; treating as %s" % (fname, low))
        kind = classify(low, art)
        if kind is None:
            rep.warn("%s: unknown name (expected bg_*, unit_*_<pose>, fx_*, tile_escape, map_*, fx_weapon_*, "
                     "fx_skill_*, icon_weapon_*), skipped" % fname)
            continue
        if kind[0] == "bad":
            rep.warn("%s: %s, skipped" % (fname, kind[1]["why"]))
            continue
        try:
            img = Image.open(path)
            img.load()
        except Exception as ex:  # noqa: BLE001 - 壞檔要報告而不是整個中斷
            rep.error("%s: cannot read image (%s)" % (fname, ex))
            continue
        if kind[0] == "bg":
            _import_bg(img, low, kind[1]["name"], known_bg, out, rep)
        elif kind[0] == "unit":
            _import_unit(img, low, kind[1]["id"], kind[1]["pose"], units, out, rep)
        elif kind[0] == "map":
            _import_spec(img, low, MAP_SPEC[kind[1]["name"]], os.path.join(out, "map"), rep)
        elif kind[0] == "weapon_fx":
            _import_spec(img, low, WEAPON_FX_SPEC[kind[1]["name"]], os.path.join(out, "fx"), rep)
        elif kind[0] == "weapon_icon":
            _import_spec(img, low, WEAPON_ICON_SPEC[kind[1]["name"]], os.path.join(out, "icons"), rep)
        else:
            _import_fx(img, low, kind[1]["name"], known_fx, out, rep)


def _import_bg(img, fname, name, known, out, rep):
    if name not in known:
        rep.warn("%s: region/background '%s' is not in art.json backgrounds (imported anyway)" % (fname, name))
    w, h = img.size
    if (w, h) != (BG_W, BG_H):
        rep.warn("%s: %dx%d, expected %dx%d; resized to cover" % (fname, w, h, BG_W, BG_H))
    if w < BG_W // 2 or h < BG_H // 2:
        rep.warn("%s: very small background, will look blurry" % fname)
    save_png(cover(img, BG_W, BG_H), os.path.join(out, "bg", fname), rep)
    rep.imported.add(fname)


def _import_unit(img, fname, uid, pose, units, out, rep):
    entry = units.get(uid)
    if entry is None:
        rep.warn("%s: unit id '%s' is not in art.json units (imported anyway; add an entry to use it)" % (fname, uid))
        entry = {}
    elif not entry.get("sprite") and entry.get("alias"):
        rep.warn("%s: '%s' is an alias of '%s'; add \"sprite\": \"%s\" to its art.json entry to use this file" % (
            fname, uid, entry["alias"], uid))
    w, h = img.size
    if (w, h) != (UNIT_SRC_SIZE, UNIT_SRC_SIZE):
        rep.warn("%s: %dx%d, expected %dx%d (still usable)" % (fname, w, h, UNIT_SRC_SIZE, UNIT_SRC_SIZE))
    rgba = ensure_alpha(img, fname, rep)
    if rgba is None:
        return
    norm = normalize_unit(rgba, bool(entry.get("flip", False)))
    if norm is None:
        rep.error("%s: image is fully transparent" % fname)
        return
    save_png(norm, os.path.join(out, "units", fname), rep)
    rep.imported.add(fname)


def _import_fx(img, fname, name, known, out, rep):
    if name not in known:
        rep.warn("%s: '%s' is not in art.json fx (imported anyway)" % (fname, name))
    tw, th = FX_SIZE.get(name, FX_DEFAULT)
    if img.size != (tw, th):
        rep.warn("%s: %dx%d, expected %dx%d; fitted" % (fname, img.size[0], img.size[1], tw, th))
    rgba = ensure_alpha(img, fname, rep)
    if rgba is None:
        return
    t = trim(rgba)
    if t is None:
        rep.error("%s: image is fully transparent" % fname)
        return
    save_png(contain_rgba(t, tw, th), os.path.join(out, "fx", fname), rep)
    rep.imported.add(fname)


def _import_spec(img, fname, spec, out_dir, rep):
    """M3c 地圖美術／武器特效／武器圖示（M3C_PLAN §2.5 處理規格表）"""
    mode, (tw, th) = spec
    w, h = img.size
    if mode == "cover":
        if fname == "map_world_base.png":
            ratio = (w / h) / (tw / th) if h else 0.0
            if abs(ratio - 1.0) > WORLD_ASPECT_TOL:
                rep.warn("%s: %dx%d is not 4:3 (off by %.1f%%); cropped to cover, map stations may not line up" % (
                    fname, w, h, abs(ratio - 1.0) * 100))
        elif (w, h) != (tw, th):
            rep.warn("%s: %dx%d, expected %dx%d; resized to cover" % (fname, w, h, tw, th))
        if w < tw // 2 or h < th // 2:
            rep.warn("%s: very small image, will look blurry" % fname)
        save_png(cover(img, tw, th), os.path.join(out_dir, fname), rep)
        rep.imported.add(fname)
        return
    # 只差解析度（同比例）照縮放，不警告；比例不同才警告
    if h and abs((w / h) / (tw / th) - 1.0) > 0.02:
        rep.warn("%s: %dx%d, expected %dx%d (aspect differs); fitted" % (fname, w, h, tw, th))
    rgba = ensure_alpha(img, fname, rep)
    if rgba is None:
        return
    t = trim(rgba)
    if t is None:
        rep.error("%s: image is fully transparent" % fname)
        return
    if mode == "frame":   # 框的邊距是 9 宮格的一部分：不裁邊
        out_img = contain_rgba(rgba, tw, th)
    else:
        out_img = contain_rgba(t, tw, th, align_left=(mode == "trim_left"))
    save_png(out_img, os.path.join(out_dir, fname), rep)
    rep.imported.add(fname)


def update_placeholder_flags(art: dict, out: str) -> bool:
    """有正式圖（idle／背景／特效）的條目 placeholder=false，否則 true。回傳是否有改。"""
    changed = False

    def setp(e, val):
        nonlocal changed
        if e.get("placeholder") != val:
            e["placeholder"] = val
            changed = True

    for sprite, (_k, e) in unit_sprites(art).items():
        setp(e, not os.path.isfile(os.path.join(out, "units", "unit_%s_idle.png" % sprite)))
    for bg, (_k, e) in bg_files(art).items():
        setp(e, not os.path.isfile(os.path.join(out, "bg", "bg_%s.png" % bg)))
    for f, (_k, e) in fx_files(art).items():
        setp(e, not os.path.isfile(os.path.join(out, "fx", "%s.png" % f)))
    for section, sub in FILE_SECTIONS.items():
        for f, (_k, e) in section_files(art, section).items():
            setp(e, not os.path.isfile(os.path.join(out, sub, "%s.png" % f)))
    return changed


def print_report(art: dict, out: str, rep: Report) -> None:
    ph = os.path.join(out, "placeholder")
    print("== art import report ==")
    counts = {"NEW": 0, "art": 0, "placeholder": 0, "missing": 0}
    missing_required = []
    # 「NEW」只算這次真的寫出（或內容有變）的檔；內容相同的重跑算「art」（已匯入）
    written = {os.path.basename(p) for p in rep.written}
    for sub, fname, required in request_list(art):
        real = os.path.isfile(os.path.join(out, sub, fname))
        if fname in rep.imported and fname in written:
            st = "NEW"
        elif real:
            st = "art"
        elif os.path.isfile(os.path.join(ph, sub, fname)):
            st = "placeholder"
        else:
            st = "missing"
        counts[st] += 1
        if not real and required:
            missing_required.append(fname)
        # 選做且沒有暫代圖的姿勢（attack/hurt）不逐條列出，免得清單太長
        if st == "missing" and not required:
            continue
        print("  %-12s %-9s %s" % (st, "required" if required else "optional", fname))
    extra = sorted(rep.imported - {f for _s, f, _r in request_list(art)})
    for f in extra:
        print("  %-12s %-9s %s" % ("NEW" if f in written else "art", "extra", f))
    print("summary: %d new, %d already imported, %d using placeholder, %d optional not provided" % (
        counts["NEW"], counts["art"], counts["placeholder"], counts["missing"]))
    print("required still missing (%d): %s" % (len(missing_required), ", ".join(missing_required) or "none"))
    print("files written: %d, unchanged: %d, backed up before overwrite: %d" % (
        len(rep.written), len(rep.unchanged), len(rep.backups)))
    for b in rep.backups:
        print("BACKUP " + b)
    for w in rep.warnings:
        print("WARN  " + w)
    for e in rep.errors:
        print("ERROR " + e)


# ---------------------------------------------------------------- 暫代圖（程式產生）

def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def _noise(size, cell, rng):
    w, h = size
    sw, sh = max(2, w // cell + 2), max(2, h // cell + 2)
    small = Image.new("L", (sw, sh))
    small.putdata([rng.randrange(256) for _ in range(sw * sh)])
    return small.resize((sw * cell, sh * cell), Image.BICUBIC).crop((cell // 2, cell // 2, cell // 2 + w, cell // 2 + h))


def _fbm(size, rng, cells=(320, 120, 40, 10), weights=(0.45, 0.3, 0.17, 0.08)):
    acc = None
    total = 0.0
    for c, wt in zip(cells, weights):
        n = _noise(size, c, rng)
        if acc is None:
            acc = n
            total = wt
        else:
            total += wt
            acc = Image.blend(acc, n, wt / total)
    # 拉開對比
    lo, hi = acc.getextrema()
    span = max(1, hi - lo)
    return acc.point(lambda v: int((v - lo) * 255 / span))


def _colorize(mask, c0, c1):
    return Image.composite(Image.new("RGB", mask.size, c1), Image.new("RGB", mask.size, c0), mask)


def _radial(size, cx, cy, rx, ry, inner=0.0, invert=False):
    """橢圓漸層：中心 255 → 邊緣 0（invert 相反）。用小圖算再放大，很快。"""
    w, h = size
    sw, sh = 192, max(2, round(192 * h / w))
    m = Image.new("L", (sw, sh))
    px = []
    for y in range(sh):
        for x in range(sw):
            dx = (x + 0.5) / sw * w - cx
            dy = (y + 0.5) / sh * h - cy
            d = math.sqrt((dx / rx) ** 2 + (dy / ry) ** 2)
            t = 1.0 if d <= inner else max(0.0, 1.0 - (d - inner) / max(1e-6, 1.0 - inner))
            t = t * t * (3 - 2 * t)
            px.append(int(255 * (1 - t if invert else t)))
    m.putdata(px)
    return m.resize(size, Image.BICUBIC)


def _vgrad(size, y0, y1, invert=False):
    w, h = size
    col = Image.new("L", (1, h))
    vals = []
    for y in range(h):
        t = min(1.0, max(0.0, (y - y0) / max(1, (y1 - y0))))
        vals.append(int(255 * (1 - t if invert else t)))
    col.putdata(vals)
    return col.resize(size)


def _edge_mask(size):
    """中央 ~70% 為 0（保持空曠）、邊緣 255：裝飾只畫在這裡"""
    w, h = size
    return _radial(size, w / 2, h * 0.54, w * 0.56, h * 0.58, inner=0.62, invert=True)


def _layer(size):
    return Image.new("RGBA", size, (0, 0, 0, 0))


def _paste_deco(base, deco, edge):
    a = ImageChops.multiply(deco.getchannel("A"), edge)
    deco = deco.copy()
    deco.putalpha(a)
    base.alpha_composite(deco)


def _tufts(draw, rng, size, n, colors, edge, length=(10, 26)):
    w, h = size
    ep = edge.load()
    placed = 0
    tries = 0
    while placed < n and tries < n * 20:
        tries += 1
        x, y = rng.randrange(w), rng.randrange(int(h * 0.14), h)
        if ep[x, y] < rng.randrange(40, 256):
            continue
        placed += 1
        c = rng.choice(colors)
        for _ in range(rng.randrange(3, 7)):
            ln = rng.uniform(*length) * (0.6 + 0.6 * y / h)
            ang = math.radians(rng.uniform(-125, -55))
            draw.line([(x, y), (x + math.cos(ang) * ln, y + math.sin(ang) * ln)], fill=c + (230,), width=2)


def _rock(draw, x, y, r, base, rng):
    pts = []
    k = rng.randrange(7, 11)
    for i in range(k):
        a = 2 * math.pi * i / k
        rr = r * rng.uniform(0.75, 1.1)
        pts.append((x + math.cos(a) * rr * 1.3, y + math.sin(a) * rr * 0.7))
    draw.polygon(pts, fill=_lerp(base, (0, 0, 0), 0.25) + (255,))
    pts2 = [(px - r * 0.12, py - r * 0.12) for px, py in pts]
    draw.polygon(pts2, fill=base + (255,))
    draw.ellipse([x - r * 0.9, y - r * 0.55, x - r * 0.1, y - r * 0.15], fill=_lerp(base, (255, 255, 255), 0.25) + (255,))


def _finish_bg(img, rng, vignette=0.35, grain=10):
    size = img.size
    v = _radial(size, size[0] / 2, size[1] * 0.52, size[0] * 0.75, size[1] * 0.8, inner=0.35)
    dark = Image.blend(img, Image.new("RGB", size, (0, 0, 0)), vignette)
    img = Image.composite(img, dark, v)
    g = _noise(size, 3, rng).point(lambda q: 128 + (q - 128) * grain // 128)
    img = ImageChops.add(img, Image.merge("RGB", (g, g, g)), 1.0, -128)
    return img


def _ground(size, rng, c0, c1, patch=None):
    img = _colorize(_fbm(size, rng), c0, c1)
    if patch:
        pm = _fbm(size, rng, cells=(260, 90, 30), weights=(0.6, 0.3, 0.1)).point(lambda v: max(0, min(255, (v - 150) * 4)))
        pm = pm.filter(ImageFilter.GaussianBlur(6))
        img = Image.composite(Image.new("RGB", size, patch), img, pm.point(lambda v: v * 3 // 4))
    return img


def bg_xixia_wild(rng):
    size = (BG_W, BG_H)
    img = _ground(size, rng, (176, 156, 92), (206, 182, 118), patch=(222, 200, 150))
    # 遠景：天空與沙丘
    sky = Image.new("RGB", size, (226, 222, 200))
    img = Image.composite(img, sky, _vgrad(size, 120, 200))
    deco = _layer(size)
    d = ImageDraw.Draw(deco)
    for k, col in enumerate(((214, 184, 128), (200, 168, 112))):
        pts = [(0, BG_H)]
        for x in range(0, BG_W + 40, 40):
            pts.append((x, 150 + k * 22 + 26 * math.sin(x / (230 - k * 60) + k * 2)))
        pts.append((BG_W, BG_H))
        d.polygon(pts, fill=col + (255,))
    deco = deco.filter(ImageFilter.GaussianBlur(3))
    top = _vgrad(size, 140, 260, invert=True)
    img = Image.composite(Image.composite(deco.convert("RGB"), img, deco.getchannel("A")), img, top)
    base = img.convert("RGBA")
    edge = _edge_mask(size)
    lay = _layer(size)
    d = ImageDraw.Draw(lay)
    for x in (70, 150, 1760, 1850):   # 白楊
        h = rng.randrange(150, 210)
        d.ellipse([x - 22, 210 - h, x + 22, 220], fill=(104, 116, 64, 255))
        d.ellipse([x - 14, 200 - h, x + 8, 200], fill=(132, 142, 78, 255))
        d.line([(x, 215), (x, 250)], fill=(92, 72, 50, 255), width=6)
    for _ in range(16):
        x, y = rng.randrange(BG_W), rng.randrange(260, BG_H)
        _rock(d, x, y, rng.randrange(10, 26), (150, 138, 118), rng)
    _tufts(d, rng, size, 520, [(150, 152, 70), (178, 168, 84), (120, 128, 60)], edge)
    lay = lay.filter(ImageFilter.GaussianBlur(0.7))
    _paste_deco(base, lay, edge.point(lambda v: min(255, v * 2)))
    return _finish_bg(base.convert("RGB"), rng, 0.30)


def bg_jingcheng_wild(rng):
    size = (BG_W, BG_H)
    img = _ground(size, rng, (98, 138, 64), (136, 168, 86), patch=(150, 170, 92))
    # 石板路：沿等角方向斜穿畫面
    road = _layer(size)
    d = ImageDraw.Draw(road)
    cx, cy = BG_W * 0.5, BG_H * 0.58
    ux, uy = 1.0, -0.5
    nx, ny = 0.45, 0.9
    half = 85
    L = 1400
    poly = [(cx - ux * L + nx * half, cy - uy * L + ny * half), (cx + ux * L + nx * half, cy + uy * L + ny * half),
            (cx + ux * L - nx * half, cy + uy * L - ny * half), (cx - ux * L - nx * half, cy - uy * L - ny * half)]
    d.polygon(poly, fill=(170, 160, 136, 255))
    for i in range(-40, 41):
        for j in (-1, 0, 1):
            px = cx + ux * i * 34 + nx * j * 52 + rng.uniform(-4, 4)
            py = cy + uy * i * 34 + ny * j * 52 + rng.uniform(-3, 3)
            c = _lerp((150, 142, 122), (190, 180, 156), rng.random())
            d.polygon([(px - 15, py), (px, py - 9), (px + 15, py), (px, py + 9)], fill=c + (255,))
    road = road.filter(ImageFilter.GaussianBlur(1.2))
    ra = road.getchannel("A").filter(ImageFilter.GaussianBlur(5))
    wear = _fbm(size, rng, cells=(120, 40, 12), weights=(0.5, 0.3, 0.2)).point(lambda v: min(255, max(0, (v - 40) * 2)))
    img = Image.composite(road.convert("RGB"), img, ImageChops.multiply(ra, wear))
    base = img.convert("RGBA")
    edge = _edge_mask(size)
    lay = _layer(size)
    d = ImageDraw.Draw(lay)
    d.rectangle([0, 40, BG_W, 130], fill=(168, 136, 96, 255))       # 低矮土牆
    d.rectangle([0, 40, BG_W, 58], fill=(190, 160, 118, 255))
    for x in range(-40, BG_W + 80, rng.randrange(220, 300)):        # 柳樹
        x += rng.randrange(-40, 40)
        d.rectangle([x - 8, 120, x + 8, 230], fill=(86, 66, 44, 255))
        for _ in range(26):
            ox, oy = rng.uniform(-90, 90), rng.uniform(-40, 50)
            ln = rng.uniform(60, 130)
            d.line([(x + ox, 90 + oy), (x + ox * 1.1, 90 + oy + ln)], fill=(84 + rng.randrange(30), 128 + rng.randrange(30), 62, 255), width=5)
        d.ellipse([x - 90, 40, x + 90, 140], fill=(96, 136, 66, 255))
    _tufts(d, rng, size, 380, [(80, 118, 50), (118, 152, 70), (150, 176, 92)], edge)
    for _ in range(8):
        _rock(d, rng.randrange(BG_W), rng.randrange(300, BG_H), rng.randrange(10, 20), (140, 136, 126), rng)
    lay = lay.filter(ImageFilter.GaussianBlur(0.8))
    _paste_deco(base, lay, edge.point(lambda v: min(255, v * 2)))
    return _finish_bg(base.convert("RGB"), rng, 0.28)


def bg_dali_wild(rng):
    size = (BG_W, BG_H)
    img = _ground(size, rng, (104, 152, 82), (140, 182, 102), patch=(164, 192, 112))
    # 遠山與霧
    mist = Image.new("RGB", size, (206, 220, 222))
    img = Image.composite(img, mist, _vgrad(size, 150, 240))
    lay = _layer(size)
    d = ImageDraw.Draw(lay)
    for k, col in enumerate(((150, 170, 182), (128, 152, 162))):
        pts = [(0, 260)]
        x = 0
        while x <= BG_W + 120:
            pts.append((x, 120 + k * 30 + rng.randrange(-50, 30)))
            x += rng.randrange(110, 220)
        pts += [(BG_W, 260)]
        d.polygon(pts, fill=col + (255,))
    lay = lay.filter(ImageFilter.GaussianBlur(4))
    hill = Image.composite(lay.convert("RGB"), img, lay.getchannel("A"))
    img = Image.composite(hill, img, _vgrad(size, 170, 250, invert=True))
    img = Image.composite(Image.new("RGB", size, (214, 226, 228)), img, _vgrad(size, 200, 260).point(lambda v: (255 - v) * 2 // 5))
    # 右下角湖岸
    lake = Image.new("L", size, 0)
    ld = ImageDraw.Draw(lake)
    pts = [(BG_W, BG_H * 0.48)]
    for i in range(0, 24):
        t = i / 23
        x = BG_W - t * BG_W * 0.42 + 10 * math.sin(i * 0.9)
        y = BG_H * 0.48 + t * BG_H * 0.52 + 8 * math.cos(i * 1.1)
        pts.append((x, y))
    pts += [(BG_W, BG_H)]
    ld.polygon(pts, fill=255)
    lake = lake.filter(ImageFilter.GaussianBlur(5))
    shore = lake.filter(ImageFilter.MaxFilter(31)).filter(ImageFilter.GaussianBlur(8))
    img = Image.composite(Image.new("RGB", size, (196, 186, 146)), img, shore)
    water = _colorize(_fbm(size, rng, cells=(200, 60, 16), weights=(0.6, 0.3, 0.1)), (78, 128, 150), (118, 166, 178))
    img = Image.composite(water, img, lake)
    base = img.convert("RGBA")
    edge = _edge_mask(size)
    lay = _layer(size)
    d = ImageDraw.Draw(lay)
    for x, y in ((90, 320), (60, 620), (130, 900), (420, 1010), (1660, 300), (300, 260), (1500, 250)):  # 茶花叢
        for _ in range(7):
            ox, oy = rng.uniform(-60, 60), rng.uniform(-30, 30)
            d.ellipse([x + ox - 50, y + oy - 34, x + ox + 50, y + oy + 34], fill=(56 + rng.randrange(20), 102 + rng.randrange(20), 58, 255))
        for _ in range(9):
            ox, oy = rng.uniform(-70, 70), rng.uniform(-40, 30)
            c = rng.choice([(206, 64, 80), (232, 120, 140), (240, 220, 226)])
            d.ellipse([x + ox - 8, y + oy - 7, x + ox + 8, y + oy + 7], fill=c + (255,))
    _tufts(d, rng, size, 300, [(88, 136, 66), (128, 170, 86)], edge)
    lay = lay.filter(ImageFilter.GaussianBlur(0.8))
    _paste_deco(base, lay, ImageChops.multiply(edge.point(lambda v: min(255, v * 2)), ImageChops.invert(shore)))
    return _finish_bg(base.convert("RGB"), rng, 0.25)


def bg_guiwang(rng):
    size = (BG_W, BG_H)
    img = _ground(size, rng, (30, 32, 38), (62, 60, 66), patch=(44, 50, 52))
    glow = _radial(size, BG_W * 0.5, BG_H * 0.55, BG_W * 0.42, BG_H * 0.45)
    img = ImageChops.add(img, Image.merge("RGB", (glow.point(lambda v: v * 10 // 255), glow.point(lambda v: v * 46 // 255),
                                                  glow.point(lambda v: v * 44 // 255))))
    base = img.convert("RGBA")
    edge = _edge_mask(size)
    lay = _layer(size)
    d = ImageDraw.Draw(lay)
    d.rectangle([0, 0, BG_W, 120], fill=(18, 18, 24, 255))
    for x in range(0, BG_W, 46):   # 鐘乳石（上）
        ln = rng.randrange(40, 150)
        d.polygon([(x - 26, 100), (x + 26, 100), (x + rng.randrange(-6, 6), 100 + ln)], fill=(40, 40, 48, 255))
    for _ in range(40):            # 石筍（邊緣）
        x, y = rng.randrange(BG_W), rng.randrange(150, BG_H)
        ht = rng.randrange(40, 120)
        wd = ht * rng.uniform(0.25, 0.4)
        d.polygon([(x - wd, y), (x + wd, y), (x + rng.uniform(-5, 5), y - ht)], fill=(52, 52, 60, 255))
        d.polygon([(x - wd, y), (x - wd * 0.2, y), (x, y - ht)], fill=(70, 72, 80, 255))
    for _ in range(26):            # 骨頭
        x, y = rng.randrange(BG_W), rng.randrange(200, BG_H)
        a = rng.uniform(0, math.pi)
        dx, dy = math.cos(a) * 18, math.sin(a) * 9
        d.line([(x - dx, y - dy), (x + dx, y + dy)], fill=(196, 190, 170, 255), width=5)
        for sx in (-1, 1):
            d.ellipse([x + sx * dx - 6, y + sx * dy - 5, x + sx * dx + 6, y + sx * dy + 5], fill=(206, 200, 182, 255))
    for _ in range(7):             # 蠟燭
        x, y = rng.randrange(BG_W), rng.randrange(220, BG_H)
        _rock(d, x, y + 10, 18, (58, 56, 64), rng)
        d.rectangle([x - 4, y - 18, x + 4, y + 4], fill=(222, 214, 190, 255))
        d.ellipse([x - 4, y - 30, x + 4, y - 18], fill=(255, 220, 120, 255))
    lay = lay.filter(ImageFilter.GaussianBlur(0.8))
    _paste_deco(base, lay, edge.point(lambda v: min(255, v * 2)))
    img = base.convert("RGB")
    # 燭光與鬼火
    lights = Image.new("L", size, 0)
    ld = ImageDraw.Draw(lights)
    for _ in range(9):
        x, y = rng.randrange(BG_W), rng.randrange(150, BG_H)
        if edge.getpixel((x, y)) > 120:
            ld.ellipse([x - 60, y - 60, x + 60, y + 60], fill=90)
    lights = lights.filter(ImageFilter.GaussianBlur(40))
    img = ImageChops.add(img, Image.merge("RGB", (lights.point(lambda v: v // 6), lights.point(lambda v: v // 2), lights.point(lambda v: v // 2))))
    return _finish_bg(img, rng, 0.55)


def bg_huashan(rng):
    size = (BG_W, BG_H)
    clouds = _colorize(_fbm(size, rng, cells=(260, 90, 30), weights=(0.6, 0.3, 0.1)), (176, 190, 206), (238, 242, 246))
    stone = _ground(size, rng, (122, 120, 114), (160, 156, 146), patch=(140, 136, 128))
    plat = Image.new("L", size, 0)
    pd = ImageDraw.Draw(plat)
    pts = []
    for i in range(40):
        a = 2 * math.pi * i / 40
        r = 1 + 0.05 * math.sin(i * 1.9) + rng.uniform(-0.03, 0.03)
        pts.append((BG_W / 2 + math.cos(a) * BG_W * 0.47 * r, BG_H * 0.56 + math.sin(a) * BG_H * 0.5 * r))
    pd.polygon(pts, fill=255)
    pd.rectangle([0, 0, BG_W, BG_H * 0.3], fill=255)
    plat = plat.filter(ImageFilter.GaussianBlur(4))
    # 平台邊緣的崖面陰影
    rim = plat.filter(ImageFilter.MinFilter(25)).filter(ImageFilter.GaussianBlur(6))
    stone = Image.composite(stone, Image.blend(stone, Image.new("RGB", size, (40, 40, 44)), 0.55), rim)
    img = Image.composite(stone, clouds, plat)
    lay = _layer(size)
    d = ImageDraw.Draw(lay)
    for _ in range(30):   # 石縫
        x, y = rng.randrange(BG_W), rng.randrange(260, BG_H)
        pts = [(x, y)]
        for _k in range(rng.randrange(3, 6)):
            x += rng.uniform(-40, 40)
            y += rng.uniform(-14, 14)
            pts.append((x, y))
        d.line(pts, fill=(96, 94, 90, 200), width=2)
    base = img.convert("RGBA")
    edge = _edge_mask(size)
    _paste_deco(base, lay.filter(ImageFilter.GaussianBlur(0.6)), edge.point(lambda v: min(255, 60 + v)))
    lay = _layer(size)
    d = ImageDraw.Draw(lay)
    d.polygon([(0, 0), (BG_W, 0), (BG_W, 170), (1500, 210), (1200, 160), (800, 230), (420, 170), (0, 240)], fill=(88, 86, 86, 255))
    d.polygon([(0, 0), (BG_W, 0), (BG_W, 110), (1300, 140), (700, 100), (0, 160)], fill=(70, 70, 72, 255))
    for x, y, s in ((120, 230, 1.0), (1780, 200, 1.1), (360, 180, 0.7), (1560, 190, 0.8)):  # 松
        d.line([(x, y + 70 * s), (x + 20 * s, y - 90 * s)], fill=(70, 54, 40, 255), width=int(10 * s))
        for k in range(4):
            yy = y - 90 * s + k * 34 * s
            ww = (60 + k * 24) * s
            d.ellipse([x - ww, yy - 16 * s, x + ww * 0.8, yy + 16 * s], fill=(40 + k * 6, 78 + k * 6, 56, 255))
    _paste_deco(base, lay.filter(ImageFilter.GaussianBlur(1)), edge.point(lambda v: min(255, v * 3)))
    return _finish_bg(base.convert("RGB"), rng, 0.25)


def bg_shaolin(rng):
    size = (BG_W, BG_H)
    img = _ground(size, rng, (138, 136, 130), (168, 164, 156))
    lay = _layer(size)
    d = ImageDraw.Draw(lay)
    # 等角石板：每塊菱形各自略微不同的灰
    tw, th = 220, 110
    for j in range(-2, BG_H // (th // 2) + 3):
        for i in range(-2, BG_W // tw + 3):
            cx = i * tw + (tw // 2 if j % 2 else 0)
            cy = j * th // 2
            c = _lerp((128, 126, 120), (176, 172, 162), rng.random())
            d.polygon([(cx - tw / 2 + 3, cy), (cx, cy - th / 2 + 2), (cx + tw / 2 - 3, cy), (cx, cy + th / 2 - 2)], fill=c + (110,))
    lay = lay.filter(ImageFilter.GaussianBlur(1.0))
    base = img.convert("RGBA")
    base.alpha_composite(lay)
    edge = _edge_mask(size)
    top = _layer(size)
    d = ImageDraw.Draw(top)
    d.rectangle([0, 0, BG_W, 190], fill=(150, 52, 40, 255))                 # 紅牆
    d.rectangle([0, 178, BG_W, 196], fill=(120, 110, 100, 255))
    d.polygon([(-40, 70), (BG_W + 40, 70), (BG_W + 40, 0), (-40, 0)], fill=(54, 60, 58, 255))  # 屋簷
    for x in range(0, BG_W, 28):
        d.line([(x, 0), (x, 70)], fill=(70, 78, 74, 255), width=10)
    d.polygon([(-40, 70), (BG_W + 40, 70), (BG_W + 40, 86), (-40, 86)], fill=(40, 44, 42, 255))
    for x in (-10, BG_W + 10):
        d.polygon([(x - 60, 86), (x + 60, 86), (x + (80 if x < 0 else -80), 30)], fill=(54, 60, 58, 255))
    for x in (320, 960, 1600):
        d.rectangle([x - 14, 86, x + 14, 190], fill=(118, 36, 30, 255))
    lay = _layer(size)
    d = ImageDraw.Draw(lay)
    for x, y in ((150, 420), (130, 760), (1770, 440), (1790, 780)):        # 木人樁
        d.ellipse([x - 40, y + 140, x + 40, y + 160], fill=(80, 74, 66, 255))
        d.rounded_rectangle([x - 22, y, x + 22, y + 150], 12, fill=(122, 82, 48, 255))
        d.rounded_rectangle([x - 22, y, x - 6, y + 150], 8, fill=(146, 102, 62, 255))
        for k, oy in enumerate((30, 62, 96)):
            sx = -1 if k % 2 == 0 else 1
            d.line([(x, y + oy), (x + sx * 58, y + oy - 10)], fill=(104, 70, 40, 255), width=10)
    _paste_deco(base, lay.filter(ImageFilter.GaussianBlur(0.8)), edge.point(lambda v: min(255, v * 3)))
    d = ImageDraw.Draw(top)
    x, y = BG_W // 2, 238                                                  # 香爐
    d.ellipse([x - 70, y + 40, x + 70, y + 64], fill=(60, 56, 50, 255))
    d.rounded_rectangle([x - 54, y - 10, x + 54, y + 50], 18, fill=(110, 96, 64, 255))
    d.rectangle([x - 62, y - 18, x + 62, y - 6], fill=(132, 116, 78, 255))
    for k in range(3):
        d.line([(x - 16 + k * 16, y - 18), (x - 16 + k * 16, y - 46)], fill=(170, 60, 40, 255), width=3)
    base.alpha_composite(top.filter(ImageFilter.GaussianBlur(0.8)))
    smoke = Image.new("L", size, 0)
    sd = ImageDraw.Draw(smoke)
    for k in range(6):
        sd.ellipse([x - 30 + k * 6, y - 70 - k * 26, x + 30 + k * 10, y - 40 - k * 26], fill=60)
    smoke = smoke.filter(ImageFilter.GaussianBlur(14))
    img = Image.composite(Image.new("RGB", size, (230, 228, 222)), base.convert("RGB"), smoke)
    return _finish_bg(img, rng, 0.28)


BG_GENERATORS = {
    "xixia_wild": bg_xixia_wild, "jingcheng_wild": bg_jingcheng_wild, "dali_wild": bg_dali_wild,
    "guiwang": bg_guiwang, "huashan": bg_huashan, "shaolin": bg_shaolin,
}

# ---- 角色（在 1024 畫布上畫，再經 normalize_unit 縮成 256 高 → 自然反鋸齒）

SKIN = (234, 200, 164)
HAIR = (40, 32, 30)


def _shade(fig: Image.Image, outline=(36, 28, 24), outline_px=7, light=0.18, dark=0.30) -> Image.Image:
    """左上受光、右下陰影、邊緣略暗，再加一圈描邊 → 有體積的剪影。"""
    size = fig.size
    a = fig.getchannel("A")
    rgb = fig.convert("RGB")
    grad = Image.linear_gradient("L").rotate(45, expand=False).resize(size)
    darker = Image.blend(rgb, Image.new("RGB", size, (20, 16, 30)), dark)
    lighter = Image.blend(rgb, Image.new("RGB", size, (255, 248, 230)), light)
    mid = Image.composite(darker, rgb, grad.point(lambda v: max(0, (v - 128) * 2)))
    mid = Image.composite(lighter, mid, grad.point(lambda v: max(0, (127 - v) * 2)))
    inner = a.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.GaussianBlur(7))
    rim = ImageChops.subtract(a, inner)
    mid = Image.composite(Image.blend(mid, Image.new("RGB", size, (0, 0, 0)), 0.35), mid, rim)
    out = Image.new("RGBA", size, outline + (0,))
    ol = a.point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MaxFilter(outline_px * 2 + 1)).filter(ImageFilter.GaussianBlur(1.2))
    out.putalpha(ol.point(lambda v: v * 235 // 255))
    body = mid.convert("RGBA")
    body.putalpha(a)
    out.alpha_composite(body)
    return out


def _ell(d, cx, cy, rx, ry, fill):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill + (255,) if len(fill) == 3 else fill)


def _rot_ellipse(img, cx, cy, rx, ry, ang, fill):
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(lay).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill + (255,))
    lay = lay.rotate(ang, center=(cx, cy), resample=Image.BICUBIC)
    img.alpha_composite(lay)


def _blade(d, hx, hy, ang_deg, length, width, color, curved=False, guard=None, notch=False):
    a = math.radians(ang_deg)
    ux, uy = math.cos(a), math.sin(a)
    nx, ny = -uy, ux
    pts = []
    n = 12
    for i in range(n + 1):
        t = i / n
        bend = (math.sin(t * math.pi) * 0.12 * length) if curved else 0
        w = width * (1 - 0.65 * t ** 3)
        px = hx + ux * t * length + nx * bend
        py = hy + uy * t * length + ny * bend
        pts.append((px + nx * w / 2, py + ny * w / 2))
    for i in range(n, -1, -1):
        t = i / n
        bend = (math.sin(t * math.pi) * 0.12 * length) if curved else 0
        w = width * (1 - 0.65 * t ** 3)
        if notch and 0.45 < t < 0.55:
            w *= 0.4
        px = hx + ux * t * length + nx * bend
        py = hy + uy * t * length + ny * bend
        pts.append((px - nx * w / 2, py - ny * w / 2))
    d.polygon(pts, fill=color + (255,))
    if guard:
        d.line([(hx + nx * 26, hy + ny * 26), (hx - nx * 26, hy - ny * 26)], fill=guard + (255,), width=12)
        d.line([(hx, hy), (hx - ux * 60, hy - uy * 60)], fill=(70, 46, 30, 255), width=14)


def _human(look: dict) -> Image.Image:
    W = 1024
    fig = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(fig)
    robe = look["robe"]
    robe_dk = _lerp(robe, (0, 0, 0), 0.25)
    sash = look.get("sash", (90, 70, 50))
    female = look.get("female", False)
    tall = look.get("tall", 1.0)
    top = 1000 - int(760 * tall)
    sh_y = top + int(250 * tall)          # 肩
    hem_y = 960
    sw = 112 if not female else 96
    hw = 170 if not female else 150
    # 腳
    _ell(d, 440, 975, 48, 22, look.get("boots", (54, 44, 40)))
    _ell(d, 560, 965, 48, 22, look.get("boots", (54, 44, 40)))
    # 後手（右）
    d.polygon([(500 + sw - 10, sh_y + 10), (500 + sw + 40, sh_y + 30), (500 + sw + 70, sh_y + 250), (500 + sw + 10, sh_y + 260)], fill=robe_dk + (255,))
    _ell(d, 500 + sw + 42, sh_y + 270, 26, 26, look.get("skin", SKIN))
    # 長袍：梯形下擺
    hem = []
    for i in range(9):
        t = i / 8
        hem.append((500 - hw + 2 * hw * t, hem_y - 14 * math.sin(t * math.pi) + (8 if i % 2 else 0) * look.get("ragged", 0)))
    d.polygon([(500 - sw, sh_y), (500 + sw, sh_y)] + list(reversed(hem)), fill=robe + (255,))
    # 前襟、衣褶
    d.line([(486, sh_y + 10), (440, hem_y - 8)], fill=robe_dk + (255,), width=8)
    for x0 in (400, 560):
        d.line([(x0 + 20, sh_y + 200), (x0, hem_y - 20)], fill=_lerp(robe, (0, 0, 0), 0.12) + (255,), width=6)
    if look.get("collar"):
        d.polygon([(450, sh_y - 6), (500, sh_y + 70), (550, sh_y - 6), (530, sh_y - 6), (500, sh_y + 40), (470, sh_y - 6)], fill=look["collar"] + (255,))
    # 腰帶
    by = sh_y + int(200 * tall)
    d.polygon([(500 - sw - 8, by), (500 + sw + 8, by), (500 + sw + 12, by + 34), (500 - sw - 12, by + 34)], fill=sash + (255,))
    d.polygon([(470, by + 30), (500, by + 30), (490, by + 150), (458, by + 140)], fill=sash + (255,))
    # 前手（左，伸向左下）與武器
    weapon = look.get("weapon")
    hand = (330, sh_y + 210)
    if weapon == "sword":
        _blade(d, hand[0], hand[1], 128, 330, 20, (214, 220, 226), guard=(180, 150, 70))
    elif weapon == "sabre":
        _blade(d, hand[0], hand[1], 118, 290, 34, look.get("blade", (150, 104, 60)), curved=True, guard=(90, 70, 50), notch=look.get("notch", False))
    d.polygon([(500 - sw + 10, sh_y + 6), (500 - sw - 40, sh_y + 20), (hand[0] - 20, hand[1] - 20), (hand[0] + 34, hand[1] + 20)], fill=robe + (255,))
    _ell(d, hand[0], hand[1], 30, 30, look.get("skin", SKIN))
    if weapon == "fist":
        _ell(d, hand[0] - 6, hand[1] - 4, 34, 32, look.get("skin", SKIN))
    # 頭
    hx, hy = 492, top + 150
    hr = 82 if not female else 76
    skin = look.get("skin", SKIN)
    hair = look.get("hair", HAIR)
    if look.get("wild_hair"):
        pts = []
        for i in range(28):
            a = math.pi * (0.7 + 1.6 * i / 27)
            r = hr * (1.35 if i % 2 else 1.9)
            pts.append((hx + 20 + math.cos(a) * r, hy + 10 + math.sin(a) * r * 1.1))
        pts += [(hx + 150, hy + 260), (hx + 70, hy + 300), (hx - 30, hy + 120)]
        d.polygon(pts, fill=hair + (255,))
    _ell(d, hx + 10, hy, hr, hr * 1.05, hair if not look.get("bald") else skin)
    d.ellipse([hx - hr - 6, hy - hr * 0.75, hx + hr * 0.75, hy + hr * 1.05], fill=skin + (255,))
    if not look.get("bald"):
        d.chord([hx - hr * 0.95, hy - hr * 1.05, hx + hr * 1.1, hy + hr * 0.4], 180, 360, fill=hair + (255,))
    else:
        for i in range(3):
            for j in range(3 - (i == 2)):
                _ell(d, hx - 22 + j * 22 + i * 4, hy - 58 + i * 16, 4, 4, (150, 90, 70))
    if look.get("topknot"):
        _ell(d, hx + 16, hy - hr - 14, 30, 26, hair)
        d.rectangle([hx + 2, hy - hr - 4, hx + 30, hy - hr + 6], fill=look.get("band", (120, 40, 40)) + (255,))
    if look.get("bun"):
        _ell(d, hx + 40, hy - hr * 0.6, 38, 34, hair)
        d.polygon([(hx + 70, hy - hr * 0.5), (hx + 120, hy - hr * 0.2), (hx + 104, hy - hr * 0.62)], fill=look.get("ribbon", (200, 80, 100)) + (255,))
    # 臉（朝左下：眼睛偏左）
    eye = look.get("eye", (30, 24, 24))
    _ell(d, hx - 44, hy + 6, 7, 9, eye)
    _ell(d, hx - 6, hy + 8, 7, 9, eye)
    if look.get("mask"):
        d.chord([hx - hr - 8, hy - 4, hx + hr * 0.8, hy + hr * 1.1], 0, 180, fill=look["mask"] + (255,))
        d.rectangle([hx - hr - 8, hy + 18, hx + hr * 0.8, hy + 34], fill=look["mask"] + (255,))
    else:
        d.line([(hx - 34, hy + 50), (hx - 14, hy + 52)], fill=_lerp(skin, (0, 0, 0), 0.4) + (255,), width=4)
    return fig


def _aura(fig, pts, color, radius):
    glow = Image.new("L", fig.size, 0)
    gd = ImageDraw.Draw(glow)
    for x, y in pts:
        gd.ellipse([x - radius, y - radius, x + radius, y + radius], fill=200)
    glow = glow.filter(ImageFilter.GaussianBlur(radius * 0.45))
    lay = Image.new("RGBA", fig.size, color + (0,))
    lay.putalpha(glow)
    out = lay
    out.alpha_composite(fig)
    out2 = Image.new("RGBA", fig.size, color + (0,))
    out2.putalpha(glow.point(lambda v: v // 3))
    out.alpha_composite(out2)
    return out


def unit_human(look):
    return _shade(_human(look))


def unit_ghost():
    look = {"robe": (130, 134, 140), "sash": (90, 92, 98), "skin": (206, 222, 236), "hair": (24, 24, 30),
            "weapon": None, "ragged": 3, "tall": 0.82, "eye": (20, 60, 70)}
    fig = _human(look)
    # 去掉腳、下擺做成破爛飄動
    d = ImageDraw.Draw(fig)
    d.rectangle([0, 930, 1024, 1024], fill=(0, 0, 0, 0))
    for i in range(10):
        x = 330 + i * 36
        d.polygon([(x, 930), (x + 36, 930), (x + 18, 930 - (40 if i % 2 else 70))], fill=(0, 0, 0, 0))
    # 長指甲
    for k in range(4):
        d.line([(312 + k * 9, 600), (282 + k * 12, 680)], fill=(20, 20, 26, 255), width=5)
    fig = _shade(fig, outline=(60, 74, 90), outline_px=5, light=0.25, dark=0.2)
    a = fig.getchannel("A").point(lambda v: v * 200 // 255)
    fig.putalpha(a)
    return _aura(fig, [(500, 520)], (170, 210, 240), 200)


def unit_guiwang():
    look = {"robe": (50, 30, 70), "sash": (120, 70, 160), "skin": (222, 222, 228), "hair": (238, 238, 244),
            "weapon": "fist", "wild_hair": True, "collar": (110, 60, 150), "tall": 1.0, "eye": (150, 40, 60),
            "boots": (30, 24, 34)}
    fig = _shade(_human(look), outline=(24, 14, 34))
    return _aura(fig, [(330, 470), (654, 530)], (170, 90, 230), 90)


def _animal(kind: str) -> Image.Image:
    W = 1024
    fig = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(fig)
    if kind in ("rabbit", "bigrabbit"):
        fur = (150, 124, 94) if kind == "rabbit" else (100, 80, 62)
        belly = _lerp(fur, (240, 230, 214), 0.5)
        _ell(d, 690, 880, 120, 110, fur)                  # 後腿
        _ell(d, 760, 960, 110, 30, _lerp(fur, (0, 0, 0), 0.2))
        _ell(d, 590, 820, 190, 140, fur)                  # 身體
        _ell(d, 560, 880, 110, 70, belly)
        _ell(d, 790, 760, 44, 40, (236, 232, 222))       # 尾巴
        _rot_ellipse(fig, 450, 560, 34, 150, 18, _lerp(fur, (0, 0, 0), 0.1))   # 耳
        _rot_ellipse(fig, 400, 570, 34, 150, -8, fur)
        _rot_ellipse(fig, 400, 570, 16, 120, -8, (220, 170, 160))
        d = ImageDraw.Draw(fig)
        _ell(d, 400, 720, 96, 86, fur)                    # 頭
        _ell(d, 330, 760, 40, 34, belly)
        _ell(d, 300, 742, 10, 8, (60, 40, 40))
        _ell(d, 372, 700, 13, 15, (120, 20, 20) if kind == "bigrabbit" else (24, 18, 18))
        _ell(d, 440, 950, 30, 22, fur)                    # 前腳
        _ell(d, 500, 960, 30, 22, fur)
        if kind == "bigrabbit":
            d.line([(372, 680), (404, 690)], fill=(30, 20, 18, 255), width=8)   # 怒眉
    elif kind == "wolf":
        fur = (122, 122, 128)
        dk = _lerp(fur, (0, 0, 0), 0.3)
        belly = (190, 188, 184)
        for x, y in ((340, 880), (420, 900), (650, 890), (730, 900)):           # 腿
            d.polygon([(x - 22, 760), (x + 22, 760), (x + 16, y + 60), (x - 16, y + 60)], fill=(fur if x in (420, 730) else dk) + (255,))
            _ell(d, x - 6, y + 60, 26, 14, dk)
        d.polygon([(780, 700), (900, 640), (960, 700), (880, 760), (790, 760)], fill=fur + (255,))          # 尾
        _ell(d, 560, 740, 250, 110, fur)                                          # 身
        _ell(d, 520, 800, 180, 50, belly)
        d.polygon([(380, 650), (480, 640), (520, 700)], fill=dk + (255,))        # 頸毛
        _ell(d, 300, 760, 90, 76, fur)                                            # 頭（壓低）
        d.polygon([(250, 740), (130, 790), (140, 830), (260, 820)], fill=fur + (255,))   # 吻部
        _ell(d, 140, 806, 16, 14, (20, 20, 20))
        d.polygon([(150, 828), (250, 826), (170, 850)], fill=(150, 40, 40, 255))  # 嘴
        for x in (170, 200, 228):
            d.polygon([(x, 826), (x + 8, 826), (x + 4, 842)], fill=(240, 240, 230, 255))
        d.polygon([(290, 700), (310, 610), (350, 700)], fill=dk + (255,))          # 耳
        d.polygon([(340, 700), (380, 620), (390, 710)], fill=fur + (255,))
        _ell(d, 262, 744, 14, 10, (120, 255, 120))                                # 綠眼
    elif kind == "boar":
        fur = (76, 60, 50)
        dk = (52, 40, 34)
        for x in (360, 440, 660, 740):
            d.rectangle([x - 26, 820, x + 26, 950], fill=(dk if x in (360, 660) else fur) + (255,))
            _ell(d, x, 952, 30, 16, (40, 32, 28))
        _ell(d, 580, 760, 260, 160, fur)                                          # 身
        pts = [(380, 640)]
        for i in range(16):                                                       # 背鬃
            x = 400 + i * 26
            pts.append((x, 618 - (26 if i % 2 else 0) - 14 * math.sin(i / 15 * math.pi)))
        pts += [(800, 650)]
        d.polygon(pts, fill=dk + (255,))
        _ell(d, 320, 790, 130, 110, fur)                                          # 頭
        d.polygon([(260, 740), (150, 800), (170, 880), (290, 860)], fill=fur + (255,))
        _ell(d, 158, 842, 30, 40, (150, 110, 100))                                # 鼻盤
        _ell(d, 150, 830, 7, 9, (40, 30, 30))
        _ell(d, 150, 856, 7, 9, (40, 30, 30))
        for ox in (0, 40):
            d.arc([190 + ox, 820, 260 + ox, 900], 160, 300, fill=(242, 236, 220, 255), width=14)   # 獠牙
        d.polygon([(320, 690), (360, 630), (380, 710)], fill=dk + (255,))         # 耳
        _ell(d, 270, 770, 10, 9, (200, 60, 30))
    return _shade(fig)


def fx_hit():
    W = 512
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    glow = Image.new("L", (W, W), 0)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([140, 140, 372, 372], fill=200)
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    lay = Image.new("RGBA", (W, W), (255, 220, 120, 0))
    lay.putalpha(glow)
    img.alpha_composite(lay)
    d = ImageDraw.Draw(img)
    rng = random.Random(7)
    pts = []
    for i in range(24):
        a = 2 * math.pi * i / 24
        r = (220 if i % 2 == 0 else 60) * rng.uniform(0.75, 1.0)
        pts.append((256 + math.cos(a) * r, 256 + math.sin(a) * r))
    d.polygon(pts, fill=(255, 236, 160, 255))
    d.ellipse([200, 200, 312, 312], fill=(255, 255, 240, 255))
    return img.filter(ImageFilter.GaussianBlur(1.2))


def fx_slash():
    W = 512
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(60):
        t = i / 59
        a = math.radians(200 + t * 120)
        r = 190
        w = 6 + 30 * math.sin(t * math.pi)
        x, y = 256 + math.cos(a) * r, 300 + math.sin(a) * r
        al = int(255 * math.sin(t * math.pi) ** 0.6)
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=(236, 246, 255, al))
    glow = img.filter(ImageFilter.GaussianBlur(10))
    glow.alpha_composite(img)
    return glow


def fx_palm():
    W = 512
    ring = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(ring)
    d.ellipse([60, 60, 452, 452], outline=255, width=26)
    d.ellipse([140, 140, 372, 372], fill=90)
    ring = ring.filter(ImageFilter.GaussianBlur(12))
    img = Image.new("RGBA", (W, W), (255, 200, 80, 0))
    img.putalpha(ring)
    core = Image.new("L", (W, W), 0)
    ImageDraw.Draw(core).ellipse([60, 60, 452, 452], outline=255, width=8)
    c = Image.new("RGBA", (W, W), (255, 244, 200, 0))
    c.putalpha(core.filter(ImageFilter.GaussianBlur(2)))
    img.alpha_composite(c)
    return img


def fx_tile_escape():
    W, H = 512, 256
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    dia = [(16, 128), (256, 8), (496, 128), (256, 248)]
    d.polygon(dia, fill=70)
    d.line(dia + [dia[0]], fill=255, width=12)
    m = m.filter(ImageFilter.GaussianBlur(5))
    img = Image.new("RGBA", (W, H), (255, 214, 90, 0))
    img.putalpha(m)
    edge = Image.new("L", (W, H), 0)
    ImageDraw.Draw(edge).line(dia + [dia[0]], fill=255, width=4)
    e = Image.new("RGBA", (W, H), (255, 246, 200, 0))
    e.putalpha(edge.filter(ImageFilter.GaussianBlur(1)))
    img.alpha_composite(e)
    return img


UNIT_GENERATORS = {
    "player_m": lambda: unit_human({"robe": (128, 112, 92), "sash": (84, 66, 50), "weapon": "sabre", "topknot": True,
                                    "band": (90, 70, 56)}),
    "player_f": lambda: unit_human({"robe": (150, 182, 206), "sash": (96, 120, 150), "weapon": "sabre", "female": True,
                                    "bun": True, "ribbon": (210, 90, 110), "tall": 0.94}),
    "shaolin_m": lambda: unit_human({"robe": (222, 150, 52), "sash": (120, 78, 40), "weapon": "fist", "bald": True,
                                     "collar": (196, 120, 40)}),
    "huashan_m": lambda: unit_human({"robe": (52, 104, 104), "sash": (34, 70, 72), "weapon": "sword", "topknot": True,
                                     "collar": (236, 236, 228), "band": (40, 60, 60)}),
    "huashan_f": lambda: unit_human({"robe": (60, 116, 112), "sash": (36, 74, 76), "weapon": "sword", "female": True,
                                     "bun": True, "ribbon": (230, 230, 220), "collar": (236, 236, 228), "tall": 0.94}),
    "m_rabbit": lambda: _animal("rabbit"),
    "m_bigrabbit": lambda: _animal("bigrabbit"),
    "m_wolf": lambda: _animal("wolf"),
    "m_boar": lambda: _animal("boar"),
    "m_bandit": lambda: unit_human({"robe": (62, 60, 66), "sash": (110, 40, 36), "weapon": "sabre", "topknot": True,
                                    "band": (30, 30, 30), "mask": (28, 28, 30), "blade": (160, 164, 170), "notch": True,
                                    "ragged": 2, "skin": (206, 168, 132)}),
    "m_ghost": unit_ghost,
    "m_guiwang": unit_guiwang,
}

FX_GENERATORS = {"fx_hit": fx_hit, "fx_slash": fx_slash, "fx_palm": fx_palm, "tile_escape": fx_tile_escape}


def make_placeholders(out: str, art: dict, rep: Report) -> None:
    ph = os.path.join(out, "placeholder")
    for sprite in sorted(unit_sprites(art)):
        gen = UNIT_GENERATORS.get(sprite)
        if gen is None:
            rep.warn("no placeholder generator for unit sprite '%s'" % sprite)
            continue
        norm = normalize_unit(gen())
        save_png(norm, os.path.join(ph, "units", "unit_%s_idle.png" % sprite), rep)
    for bg in sorted(bg_files(art)):
        gen = BG_GENERATORS.get(bg)
        if gen is None:
            rep.warn("no placeholder generator for background '%s'" % bg)
            continue
        rng = random.Random("bg_" + bg)
        save_png(gen(rng), os.path.join(ph, "bg", "bg_%s.png" % bg), rep)
    for f in sorted(fx_files(art)):
        gen = FX_GENERATORS.get(f)
        if gen is None:
            rep.warn("no placeholder generator for fx '%s'" % f)
            continue
        save_png(gen(), os.path.join(ph, "fx", "%s.png" % f), rep)


# ---------------------------------------------------------------- 「空手重畫前」快照（M3C_PLAN §2.5 第 4 點）

def _snapshot_match(fname: str) -> bool:
    low = fname.lower()
    if not low.endswith(".png") or not low.startswith("unit_"):
        return False
    return any(low.startswith("unit_%s_" % p) for p in SNAPSHOT_PREFIXES)


def snapshot_units(out: str, inbox: str, backup_root: str, rep: Report) -> tuple[str, int]:
    """把 <out>/units/ 與 <inbox>/（以及 inbox 旁邊 art_in_backup*/ 裡的原圖）中玩家、造型、門派服裝的圖
    複製到 <backup_root>/<日期>/snapshot_units/{units,art_in,<備份資料夾名>/…}/。回傳 (快照資料夾, 檔數)。"""
    dest_root = os.path.join(backup_root, rep.today, "snapshot_units")
    sources = [(os.path.join(out, "units"), "units"), (inbox, "art_in")]
    parent = os.path.dirname(os.path.abspath(inbox))
    if os.path.isdir(parent):
        for d in sorted(os.listdir(parent)):
            full = os.path.join(parent, d)
            if d.lower().startswith("art_in_backup") and os.path.isdir(full):
                sources.append((full, d))
    count = 0
    for src, label in sources:
        if not os.path.isdir(src):
            continue
        for dirpath, _dirs, files in os.walk(src):
            rel = os.path.relpath(dirpath, src)
            dd = os.path.join(dest_root, label) if rel == "." else os.path.join(dest_root, label, rel)
            for f in sorted(files):
                if not _snapshot_match(f):
                    continue
                srcf = os.path.join(dirpath, f)
                dest = os.path.join(dd, f)
                try:
                    os.makedirs(dd, exist_ok=True)
                    if os.path.exists(dest):
                        with open(dest, "rb") as a, open(srcf, "rb") as b:
                            if a.read() == b.read():
                                count += 1
                                continue
                        stem, ext = os.path.splitext(f)
                        dest = os.path.join(dd, "%s-%s%s" % (stem, datetime.datetime.now().strftime("%H%M%S"), ext))
                    shutil.copy2(srcf, dest)
                    count += 1
                except OSError as ex:
                    rep.error("snapshot %s: %s" % (srcf, ex))
    print("snapshot: %d files in %s" % (count, dest_root))
    return dest_root, count


# ---------------------------------------------------------------- main

def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--inbox", default=DEF_INBOX)
    ap.add_argument("--out", default=DEF_OUT)
    ap.add_argument("--art-json", default=DEF_ART_JSON)
    ap.add_argument("--no-json-update", action="store_true", help="do not rewrite placeholder flags in art.json")
    ap.add_argument("--placeholders", action="store_true", help="(re)generate placeholder art and exit")
    ap.add_argument("--backup-root", default=DEF_BACKUP_ROOT,
                    help="before overwriting a different file, copy the old one to <root>/<YYYY-MM-DD>/<subdir>/")
    ap.add_argument("--no-backup", action="store_true", help="do not back up overwritten files (unit tests only)")
    ap.add_argument("--snapshot", action="store_true",
                    help="copy player/look/sect unit art (processed + inbox originals) to "
                         "<backup-root>/<date>/snapshot_units/ and exit")
    ap.add_argument("--only", action="append", default=None, metavar="GLOB",
                    help="only process inbox files whose name matches this pattern (repeatable)")
    args = ap.parse_args(argv)

    try:
        art = load_art_json(args.art_json)
    except (OSError, ValueError) as ex:
        print("ERROR cannot read %s: %s" % (args.art_json, ex))
        return 2
    rep = Report()
    rep.out_root = args.out
    rep.backup_root = None if args.no_backup else args.backup_root
    if args.snapshot:
        snapshot_units(args.out, args.inbox, args.backup_root, rep)
        for e in rep.errors:
            print("ERROR " + e)
        return 1 if rep.errors else 0
    if args.placeholders:
        make_placeholders(args.out, art, rep)
        print("placeholders: %d written, %d unchanged" % (len(rep.written), len(rep.unchanged)))
        for w in rep.warnings:
            print("WARN  " + w)
        return 0

    import_inbox(args.inbox, args.out, art, rep, args.only)
    if not args.no_json_update and update_placeholder_flags(art, args.out):
        with open(args.art_json, "w", encoding="utf-8", newline="\n") as f:
            f.write(dump_art_json(art))
        print("art.json: placeholder flags updated")
    print_report(art, args.out, rep)
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
