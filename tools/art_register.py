"""把 assets/art_in 裡新的圖登記到 data/art.json（取代 alias／placeholder）。
用法：python -I art_register.py <project_root> [--dry] [--only GLOB ...]

  * unit_<id>_idle.png → units.<id> 改成自己的 sprite（保留原本的 scale、y_offset）。
  * bg_<region>.png    → backgrounds.<region> 改成自己的 bg。
  * M3c（M3C_PLAN §2.5 第 6 點）：map_*.png、fx_weapon_*.png、fx_skill_*.png、icon_weapon_*.png
    → art.json 的 map／map_icons／weapon_fx／weapon_icons 對應條目 placeholder 改 false（條目不存在時建立）。
  * --only 可重複：只登記檔名符合的圖（例 --only "look_*" 不會順手登記其他批次）。
"""
import fnmatch, json, os, re, sys

# M3C_PLAN §2.3：檔名 → (art.json 區塊, 鍵)
MAP_KEYS = ["world_base", "region_bg", "node_room", "node_current", "node_fog", "marker_here", "compass", "frame_title"]
MAP_ICON_KEYS = ["city", "sect", "cave", "wild", "station", "inn", "shop", "master", "record", "field", "wood",
                 "water", "stove", "danger", "quest", "exit"]
WEAPON_FX_KEYS = ["sword", "blade", "staff", "whip", "fist", "claw", "stab", "hidden"]
SKILL_FX_KEYS = ["inner", "poison", "medic", "formation"]
WEAPON_ICON_KEYS = ["sword", "blade", "staff", "whip", "claw", "fist"]
FILE_ENTRIES = {}
for k in MAP_KEYS:
    FILE_ENTRIES["map_" + k] = ("map", k)
for k in MAP_ICON_KEYS:
    FILE_ENTRIES["map_icon_" + k] = ("map_icons", k)
for k in WEAPON_FX_KEYS:
    FILE_ENTRIES["fx_weapon_" + k] = ("weapon_fx", k)
for k in SKILL_FX_KEYS:
    FILE_ENTRIES["fx_skill_" + k] = ("weapon_fx", k)
for k in WEAPON_ICON_KEYS:
    FILE_ENTRIES["icon_weapon_" + k] = ("weapon_icons", k)


def parse_args(argv):
    root, dry, only = None, False, []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--dry":
            dry = True
        elif a == "--only" and i + 1 < len(argv):
            only.append(argv[i + 1].lower())
            i += 1
        elif a.startswith("--only="):
            only.append(a.split("=", 1)[1].lower())
        elif root is None:
            root = a
        i += 1
    return root, dry, only


def main(argv):
    root, dry, only = parse_args(argv)
    if root is None:
        print(__doc__)
        return 2
    p = os.path.join(root, "data", "art.json")
    with open(p, encoding="utf-8") as f:
        art = json.load(f)
    units, bgs = art["units"], art["backgrounds"]
    regions = {r["id"] for r in json.load(open(os.path.join(root, "data", "regions.json"), encoding="utf-8"))["rows"]}
    monsters = {r["id"] for r in json.load(open(os.path.join(root, "data", "monsters.json"), encoding="utf-8"))["rows"]}
    npcs = {r["id"] for r in json.load(open(os.path.join(root, "data", "npcs.json"), encoding="utf-8"))["rows"]}
    inbox = sorted(os.listdir(os.path.join(root, "assets", "art_in")))
    done, unknown = [], []

    for f in inbox:
        low = f.lower()
        if not low.endswith(".png"):
            continue
        if only and not any(fnmatch.fnmatch(low, pat) for pat in only):
            continue
        base = low[:-4]
        if base in FILE_ENTRIES:
            section, key = FILE_ENTRIES[base]
            sec = art.setdefault(section, {})
            e = sec.get(key)
            if not isinstance(e, dict) or e.get("placeholder", True) or e.get("file") != base:
                keep_req = bool(e.get("required", False)) if isinstance(e, dict) else False
                sec[key] = {"file": base, "required": keep_req, "placeholder": False}
                done.append(f)
            continue
        if base.startswith(("map_", "fx_weapon_", "fx_skill_", "icon_weapon_")):
            unknown.append(f + "（不是 M3C_PLAN §2.3 的檔名）")
            continue
        m = re.match(r"^bg_(.+)$", base)
        if m:
            rid = m.group(1)
            if rid not in regions:
                unknown.append(f + "（沒有這個地區 id）")
                continue
            e = bgs.get(rid, {})
            if e.get("alias") or e.get("placeholder", True) or e.get("bg") != rid:
                bgs[rid] = {"bg": rid, "required": False, "placeholder": False}
                done.append(f)
            continue
        m = re.match(r"^unit_(.+)_(idle|attack|hurt)$", base)
        if not m:
            continue
        ref, pose = m.group(1), m.group(2)
        if pose != "idle":
            continue  # attack/hurt 跟著 idle 的 sprite 走，不用另外登記
        known = ref in units or ref in monsters or ref in npcs or re.match(r"^[a-z]+_[mf]$", ref) \
            or re.match(r"^look_[mf]\d\d$", ref)
        if not known:
            unknown.append(f + "（沒有這個角色 id）")
            continue
        e = units.get(ref, {})
        if e.get("alias") or e.get("placeholder", True) or e.get("sprite") != ref:
            keep = {k: e[k] for k in ("scale", "y_offset") if k in e}
            units[ref] = {"sprite": ref, "scale": keep.get("scale", 1), "y_offset": keep.get("y_offset", 0),
                          "required": False, "placeholder": False}
            if e.get("body"):
                units[ref]["body"] = e["body"]   # M3c R2: humanoid/beast flag (weapon icon & fx) survives re-registration
            done.append(f)

    if not dry and done:
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(art, ensure_ascii=False, indent=2) + "\n")
    print("registered:", len(done), "(dry run, art.json not written)" if dry else "")
    for x in done:
        print("  +", x)
    print("unknown:", len(unknown))
    for x in unknown:
        print("  ?", x)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
