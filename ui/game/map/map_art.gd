class_name MapArt
extends RefCounted
## 地圖美術（ART_REQUEST §10；M3C_PLAN §4.6）：有圖用圖，沒圖回 null（呼叫端保持現行程式繪圖）。
## 查圖一律經 ArtRegistry（art.json 的 map／map_icons 區塊；WP-ART 擁有）。ArtRegistry 的新 API 以動態呼叫取用：
## WP-ART 的空殼還沒落地時也能編譯、回 null。測試可用 use_textures() 直接注入假圖（不碰 art.json）。

const REGISTRY := "res://ui/common/art_registry.gd"

## 全圖底圖的站點轉換（tools/make_map_layout_guide.py：1600×1200 畫布留 60px 邊）
const GUIDE_W := 1600.0
const GUIDE_H := 1200.0
const GUIDE_MARGIN := 60.0
const WORLD_ASPECT := 4.0 / 3.0

## 房間框 9 宮格邊距：原圖寬的 1/6、高的 1/4【設計提案】
const NINE_X := 1.0 / 6.0
const NINE_Y := 1.0 / 4.0

## 區域圖小字 → map_icon 鍵
const BADGE_ICONS := {
	"田": "field", "林": "wood", "水": "water", "灶": "stove", "驛站": "station", "客棧": "inn", "商店": "shop",
	"師父": "master", "查小鏞": "record", "會遇敵": "danger", "任務": "quest", "出口": "exit",
}
## 全圖地點類型 → map_icon 鍵
const SITE_ICONS := { "CITY": "city", "SECT": "sect", "DUNGEON": "cave", "WILD": "wild" }

static var _override: Variant = null     # null＝走 ArtRegistry；Dictionary＝測試注入 { "map:<key>" / "icon:<key>": Texture2D }
static var _has_fn: Dictionary = {}

## 測試：注入 { "world_base": tex, "icon:city": tex, … }（不帶前綴的當 map 區塊）；傳 null 還原
static func use_textures(d: Variant) -> void:
	if d == null:
		_override = null
		return
	var out := {}
	for k in d:
		var key := str(k)
		out[key if key.begins_with("icon:") or key.begins_with("map:") else "map:" + key] = d[k]
	_override = out

static func texture(key: String) -> Texture2D:
	if _override is Dictionary:
		return _override.get("map:" + key, null)
	return _registry("map_texture", key)

static func icon(key: String) -> Texture2D:
	if _override is Dictionary:
		return _override.get("icon:" + key, null)
	return _registry("map_icon", key)

static func has_world_art() -> bool:
	if _override is Dictionary:
		return _override.get("map:world_base", null) != null
	var s: Script = load(REGISTRY)
	if s != null and _has(s, "has_map_art"):
		return bool(s.call("has_map_art"))
	return false

static func _registry(fn: String, key: String) -> Texture2D:
	var s: Script = load(REGISTRY)
	if s == null or not _has(s, fn):
		return null
	var t: Variant = s.call(fn, key)
	return t as Texture2D if t is Texture2D else null

static func _has(s: Script, fn: String) -> bool:
	if not _has_fn.has(fn):
		var found := false
		for m in s.get_script_method_list():
			if str(m.get("name", "")) == fn:
				found = true
				break
		_has_fn[fn] = found
	return _has_fn[fn]

## 江湖全圖：控制項 size 裡最大的 4:3 置中矩形（有底圖時畫面鎖 4:3）
static func world_rect(size: Vector2) -> Rect2:
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	var w := minf(size.x, size.y * WORLD_ASPECT)
	var h := w / WORLD_ASPECT
	return Rect2((size - Vector2(w, h)) / 2.0, Vector2(w, h))

## world_pos（0..1000）→ 底圖矩形內的像素（同 tools/make_map_layout_guide.py）
static func world_point(rect: Rect2, wp: Vector2) -> Vector2:
	var fx := GUIDE_MARGIN / GUIDE_W + wp.x / 1000.0 * (GUIDE_W - 2.0 * GUIDE_MARGIN) / GUIDE_W
	var fy := GUIDE_MARGIN / GUIDE_H + wp.y / 1000.0 * (GUIDE_H - 2.0 * GUIDE_MARGIN) / GUIDE_H
	return rect.position + Vector2(fx * rect.size.x, fy * rect.size.y)

## 9 宮格：把 tex 伸縮到 r（四角不變形；邊距＝原圖 1/6 寬、1/4 高，且不超過目標的一半）
static func draw_nine(ci: CanvasItem, tex: Texture2D, r: Rect2, modulate: Color = Color.WHITE) -> void:
	if tex == null or r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var ts := tex.get_size()
	var mx := ts.x * NINE_X
	var my := ts.y * NINE_Y
	# 目標比原圖小時，邊距等比縮小（框的邊線粗細與四角形狀不變）
	var k := minf(1.0, minf(r.size.x / maxf(1.0, ts.x), r.size.y / maxf(1.0, ts.y)))
	var dx := minf(mx * k, r.size.x / 2.0)
	var dy := minf(my * k, r.size.y / 2.0)
	var xs_src := [0.0, mx, ts.x - mx, ts.x]
	var ys_src := [0.0, my, ts.y - my, ts.y]
	var xs_dst := [r.position.x, r.position.x + dx, r.end.x - dx, r.end.x]
	var ys_dst := [r.position.y, r.position.y + dy, r.end.y - dy, r.end.y]
	for j in 3:
		for i in 3:
			var src := Rect2(xs_src[i], ys_src[j], xs_src[i + 1] - xs_src[i], ys_src[j + 1] - ys_src[j])
			var dst := Rect2(xs_dst[i], ys_dst[j], xs_dst[i + 1] - xs_dst[i], ys_dst[j + 1] - ys_dst[j])
			if src.size.x > 0.0 and src.size.y > 0.0 and dst.size.x > 0.0 and dst.size.y > 0.0:
				ci.draw_texture_rect_region(tex, dst, src, modulate)

## 平鋪：tex 以原尺寸 × scale 鋪滿 r
static func draw_tiled(ci: CanvasItem, tex: Texture2D, r: Rect2, scale: float = 0.5) -> void:
	if tex == null:
		return
	var ts := tex.get_size() * scale
	if ts.x < 4.0 or ts.y < 4.0:
		return
	var y := r.position.y
	while y < r.end.y:
		var x := r.position.x
		var h := minf(ts.y, r.end.y - y)
		while x < r.end.x:
			var w := minf(ts.x, r.end.x - x)
			ci.draw_texture_rect_region(tex, Rect2(x, y, w, h), Rect2(Vector2.ZERO, Vector2(w, h) / scale))
			x += ts.x
		y += ts.y
