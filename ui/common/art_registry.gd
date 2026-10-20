class_name ArtRegistry
extends RefCounted
## 戰鬥美術查表（純表現層；不影響規則與協定）。資料：res://data/art.json。
## 圖檔：tools/import_art.py 處理過的正式圖在 res://assets/art/{units,bg,fx,map,icons}/，
## 沒有正式圖時用 res://assets/art/placeholder/ 的暫代圖（有一張換一張）。
##
## unit_ref：玩家用快照的 "look"（例 "shaolin_m"，見 ref_for_unit），怪物／NPC 用 monster id 或 npc id。

const ART_JSON := "res://data/art.json"
const ART_DIR := "res://assets/art"
const PLACEHOLDER_DIR := "res://assets/art/placeholder"
const MAX_ALIAS_DEPTH := 8

static var _data: Dictionary = {}
static var _loaded := false
static var _tex_cache: Dictionary = {}    # path -> Texture2D 或 null
static var _art_dir := ART_DIR
static var _placeholder_dir := PLACEHOLDER_DIR

## ---------------------------------------------------------------- 公開 API

## 單位圖。pose："idle" / "attack" / "hurt"。沒有這個姿勢的圖 → null（呼叫端用 idle 加程式動畫）。
## attack／hurt 只看「實際顯示的那張 idle」所屬的角色：第一個有 idle 圖的角色沒有這個姿勢就回 null，
## 不再往退回鏈後面找。否則全真弟子（只有 idle）出招時會借到布衣 player_m 的出招圖，變成另一個人（擁有者回報）。
static func unit_texture(unit_ref: String, kind: String, pose: String) -> Texture2D:
	for key in _unit_chain(unit_ref, kind):
		var e: Dictionary = _units().get(key, {})
		var sprite := str(e.get("sprite", key))
		var tex := _find_texture("units", "unit_%s_%s.png" % [sprite, pose])
		if tex != null:
			return tex
		if pose != "idle" and _find_texture("units", "unit_%s_idle.png" % sprite) != null:
			return null
	return null

## 顯示比例（1.0 = 一般人）與垂直位移（以 1 倍大小的精靈像素計，負數往上）。
static func unit_display(unit_ref: String) -> Dictionary:
	var out := { "scale": 1.0, "y_offset": 0.0 }
	var got_scale := false
	var got_y := false
	for key in _unit_chain(unit_ref, ""):
		var e: Dictionary = _units().get(key, {})
		if not got_scale and e.has("scale"):
			out["scale"] = float(e["scale"])
			got_scale = true
		if not got_y and e.has("y_offset"):
			out["y_offset"] = float(e["y_offset"])
			got_y = true
	return out

## M3c 第二輪審查：人形與否（art.json units 的 body："human"／"beast"）。沿 alias 鏈找：第一個有 body 的條目就是答案；
## 先碰到一個自己有 sprite、沒寫 body 的條目（實際顯示的就是它）→ ""（呼叫端依圖的長寬比猜）。
## 名牌武器圖示、出招特效用（以前只看長寬比：野兔 272×256 算人形、勞德諾 288×256 不算）
static func unit_body(unit_ref: String, kind: String = "") -> String:
	for key in _unit_chain(unit_ref, kind):
		var e: Dictionary = _units().get(key, {})
		if e.has("body"):
			return str(e["body"])
		if e.has("sprite"):
			return ""
	return ""

## 戰鬥背景；未列出的地區用 bg_default。
static func battle_background(region_id: String) -> Texture2D:
	var bgs: Dictionary = _cfg().get("backgrounds", {})
	var start := region_id if bgs.has(region_id) else str(_cfg().get("bg_default", ""))
	var key := start
	for _i in MAX_ALIAS_DEPTH:
		if key == "" or not bgs.has(key):
			break
		var e: Dictionary = bgs[key]
		if e.has("bg"):
			var tex := _find_texture("bg", "bg_%s.png" % str(e["bg"]))
			if tex != null:
				return tex
		key = str(e.get("alias", ""))
	if start != str(_cfg().get("bg_default", "")):
		return battle_background("")
	return null

## 特效圖："hit" / "slash" / "palm" / "tile_escape"（也接受檔名 "fx_hit"）。
static func fx_texture(name: String) -> Texture2D:
	var fx: Dictionary = _cfg().get("fx", {})
	var file := name
	if fx.has(name):
		file = str(fx[name].get("file", name))
	return _find_texture("fx", file + ".png")

## 從戰鬥快照的單位取出 unit_ref：玩家 → "look"（舊主機沒有此欄位 → "player_m"），其他 → "ref"。
static func ref_for_unit(u: Dictionary) -> String:
	if str(u.get("kind", "")) == "PLAYER":
		var look := str(u.get("look", ""))
		return look if look != "" else "player_m"
	return str(u.get("ref", ""))

## ---------------------------------------------------------------- M3c：地圖美術、武器特效、武器小圖示（M3C_PLAN §2.3–2.4）
## 這四類沒有暫代圖：條目 placeholder 為 true、條目不存在或檔案不存在 → null，呼叫端畫程式備援。

const MAP_KEYS := ["world_base", "region_bg", "node_room", "node_current", "node_fog", "marker_here", "compass", "frame_title"]
const MAP_ICON_KEYS := ["city", "sect", "cave", "wild", "station", "inn", "shop", "master", "record", "field", "wood", "water", "stove", "danger", "quest", "exit"]
const WEAPON_FX_KEYS := ["sword", "blade", "staff", "whip", "fist", "claw", "stab", "hidden", "inner", "poison", "medic", "formation"]
const WEAPON_ICON_KEYS := ["sword", "blade", "staff", "whip", "claw", "fist"]

## 地圖美術（MAP_KEYS）：assets/art/map/<file>.png
static func map_texture(key: String) -> Texture2D:
	return _section_texture("map", "map", key)

## 地圖圖示（MAP_ICON_KEYS）：assets/art/map/<file>.png
static func map_icon(key: String) -> Texture2D:
	return _section_texture("map_icons", "map", key)

## 江湖全圖底圖有正式圖（呼叫端據此鎖 4:3 並用 make_map_layout_guide.py 的同一轉換對位）。
static func has_map_art() -> bool:
	return map_texture("world_base") != null

## 武器／武功類別特效（WEAPON_FX_KEYS）：assets/art/fx/<file>.png（1024x512，起點＝圖的左緣中點）
static func weapon_fx_texture(key: String) -> Texture2D:
	return _section_texture("weapon_fx", "fx", key)

## 名牌旁的武器小圖示（WEAPON_ICON_KEYS）：assets/art/icons/<file>.png
static func weapon_icon(key: String) -> Texture2D:
	return _section_texture("weapon_icons", "icons", key)

## 這個單位目前是否只有暫代圖（idle 沒有正式圖）。
static func is_placeholder(unit_ref: String, kind: String = "") -> bool:
	for key in _unit_chain(unit_ref, kind):
		var e: Dictionary = _units().get(key, {})
		var sprite := str(e.get("sprite", key))
		if _texture_at(_art_dir.path_join("units/unit_%s_idle.png" % sprite)) != null:
			return false
	return true

## ---------------------------------------------------------------- 測試／工具用

static func reload(path: String = ART_JSON) -> void:
	_tex_cache.clear()
	_data = {}
	_loaded = true
	if not FileAccess.file_exists(path):
		push_warning("ArtRegistry: %s missing" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_data = parsed
	else:
		push_warning("ArtRegistry: %s is not a JSON object" % path)

## 測試用：直接指定設定與圖檔資料夾
static func use_config(data: Dictionary, art_dir: String = ART_DIR, placeholder_dir: String = PLACEHOLDER_DIR) -> void:
	_data = data.duplicate(true)
	_loaded = true
	_art_dir = art_dir
	_placeholder_dir = placeholder_dir
	_tex_cache.clear()

static func reset() -> void:
	_art_dir = ART_DIR
	_placeholder_dir = PLACEHOLDER_DIR
	_loaded = false
	_data = {}
	_tex_cache.clear()

## ---------------------------------------------------------------- 內部

static func _cfg() -> Dictionary:
	if not _loaded:
		reload()
	return _data

static func _units() -> Dictionary:
	return _cfg().get("units", {})

## 查表順序：自己 → alias → alias…；玩家（或 *_m / *_f 的未知 look）最後退到 player_fallback。
## 每一層若有自己的圖就優先用（例 m_hs_trainee 有專屬圖時蓋過 huashan_m）。
static func _unit_chain(unit_ref: String, kind: String) -> Array:
	var units := _units()
	var chain: Array = []
	var key := unit_ref
	if key == "" and kind == "PLAYER":
		key = "player_m"
	for _i in MAX_ALIAS_DEPTH:
		if key == "" or key in chain:
			break
		chain.append(key)
		if not units.has(key):
			break
		key = str(units[key].get("alias", ""))
	var is_player_look := kind == "PLAYER" or (not units.has(unit_ref) and (unit_ref.ends_with("_m") or unit_ref.ends_with("_f")))
	if is_player_look:
		var fb: Dictionary = _cfg().get("player_fallback", {})
		var g := "f" if unit_ref.ends_with("_f") else "m"
		var fk := str(fb.get(g, "player_" + g))
		if not (fk in chain):
			chain.append(fk)
	return chain

## M3c 新區塊共用：只看正式圖資料夾（不退回 placeholder/），placeholder 旗標為 true 視同沒圖。
static func _section_texture(section: String, sub: String, key: String) -> Texture2D:
	var sec: Variant = _cfg().get(section, {})
	if not (sec is Dictionary) or not (sec as Dictionary).has(key):
		return null
	var e: Variant = sec[key]
	if not (e is Dictionary) or bool(e.get("placeholder", false)):
		return null
	var file := str(e.get("file", ""))
	if file == "":
		return null
	return _texture_at(_art_dir.path_join(sub).path_join(file + ".png"))

static func _find_texture(sub: String, file: String) -> Texture2D:
	var tex := _texture_at(_art_dir.path_join(sub).path_join(file))
	if tex == null:
		tex = _texture_at(_placeholder_dir.path_join(sub).path_join(file))
	return tex

static func _texture_at(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		# 剛由 import_art.py 放進來、編輯器還沒匯入的 PNG：直接讀檔
		var img := Image.load_from_file(path if not path.begins_with("res://") else ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_tex_cache[path] = tex
	return tex
