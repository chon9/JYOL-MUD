class_name WorldMapView
extends Control
## 江湖全圖（AUTHENTIC_UI_SPEC §8.10）：羊皮紙底、墨線道路、朱紅印章城市、毛筆黑字地名，照原作座標（regions.json 的 world_pos）擺。
## - 城：朱紅印章方塊＋黑色毛筆大字；門派：墨色山形；洞窟：黑菱形；野外：小墨點＋小字。
## - 還沒開放的門派與關口（WORLD_2001 §1.1：恆山、武當、終南山、峨嵋、衡山、星宿海、血刀門、雁門關）用灰色山形＋「未開」，
##   讓原作的地理看得出來，也對得上路上「封閉岔路」的文字。
## - 實線＝步行相連（從記號邊緣畫到記號邊緣，不從字底下穿過）；虛線＝驛站路線（伺服器開了馬車選項才有）。
## - 目前所在地區：朱紅圈＋「你在這裡」。建議實戰在滑鼠提示裡。
## 審查（第 1 輪）：以前是彩色方框的流程圖，線從方框底下穿過、看不出誰接誰，也沒有未開放的山門。
## M3c（M3C_PLAN §4.1、§4.6）：
## - 點地區（記號或地名）→ region_clicked(region_id)（地圖面板做跨區趕路）；
## - 有全圖底圖（MapArt.has_world_art，ART_REQUEST §10 map_world_base.png 2400×1800）時畫面鎖 4:3、底圖畫滿，
##   站點座標＝tools/make_map_layout_guide.py 的轉換（MapArt.world_point），記號不再推開；compass、frame_title 有圖就用。
##   沒有底圖 → 原本的羊皮紙程式繪圖完全不變。

signal region_clicked(region_id: String)

const PAD := Vector2(70, 46)
const BG := Color("eadcb8")
const BG_EDGE := Color("c9b07a")
const WALK := Color("5a4630")   # 路：墨線
const TRAVEL := Color("2e6db4")
const CUR := Color("b03a2e")
const SEAL := Color("b8352a")
const GREY := Color("8c8274")
const HERE_BELOW := "▲ 你在這裡"
const HERE_ABOVE := "▼ 你在這裡"
const HERE_PLAIN := "你在這裡"
const HERE_FAR := 40.0           # 離記號超過這麼遠：不畫箭頭（只有引線）
const LABEL_GAP := 4.0
const MARK_SPACING := Vector2(30, 24)   # 兩個記號中心至少隔這麼遠（原作座標西夏一帶很擠）
const MAX_STRETCH := 1.5                # 視窗比地圖寬：各軸最多多拉長 1.5 倍

## 1.0A 沒開放、但原作地圖上有的門派與關口（座標 ÷24，WORLD_2001 §1.1；17173 gaoshou/17、gaoshou/23）
const CLOSED_SITES := [
	{ "id": "closed_hengshan", "region": "hengshan", "name": "恆山", "pos": Vector2(635, 252) },
	{ "id": "closed_wudang", "region": "wudang", "name": "武當", "pos": Vector2(837, 392) },
	{ "id": "closed_zhongnan", "region": "quanzhen", "name": "終南山", "pos": Vector2(725, 458) },
	{ "id": "closed_emei", "region": "emei", "name": "峨嵋", "pos": Vector2(579, 574) },
	{ "id": "closed_hengshan_s", "name": "衡山", "pos": Vector2(943, 678) },
	{ "id": "closed_xingxiu", "region": "xingxiu", "name": "星宿海", "pos": Vector2(142, 192) },
	{ "id": "closed_xuedao", "region": "xuedao", "name": "血刀門", "pos": Vector2(20, 520) },
	{ "id": "closed_yanmen", "name": "雁門關", "pos": Vector2(837, 96) },
]
const CLOSED_TAG := "（未開）"

var model: Dictionary = {}      # MapData.world_model
var current_region := ""
var token_tex: Texture2D = null   # 「你」（MapToken）：站在目前地點的記號上
var _centers: Dictionary = {}   # region_id -> Vector2（記號中心）
var _marks: Dictionary = {}     # id -> Rect2（記號）
var _labels: Dictionary = {}    # id -> Rect2（地名）
var _rects: Dictionary = {}     # region_id -> Rect2（記號＋地名；點擊、驛站路線避讓都用這個）
var _closed_rects: Dictionary = {}   # 未開放地點 -> Rect2
var _routes: Dictionary = {}    # "a|b" -> PackedVector2Array（驛站路線折線）
var art_mode := false           # 有全圖底圖
var art_rect := Rect2()         # 底圖畫的位置（4:3）
const TITLE_TEXT := "江湖全圖"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(760, 340)
	resized.connect(_relayout)

func setup(p_model: Dictionary, p_current_region: String) -> void:
	model = p_model
	current_region = p_current_region
	_relayout()

## 全部地點（地區＋未開放的山門）：[{ id, name, type, pos, closed }]
func sites() -> Array:
	var out: Array = []
	for r in model.get("regions", []):
		out.append({ "id": r["id"], "name": r["name"], "type": r["type"], "pos": r["pos"], "closed": false })
	var taken := {}
	for r in model.get("regions", []):
		taken[str(r["name"])] = true
		taken[str(r["id"])] = true
	for c in CLOSED_SITES:
		# M3a：門派開放後（地區已在 regions 裡）就不再畫「未開」
		if not taken.has(c["name"]) and not taken.has(str(c.get("region", ""))):
			out.append({ "id": c["id"], "name": c["name"], "type": "SECT", "pos": c["pos"], "closed": true })
	return out

func _relayout() -> void:
	_centers.clear()
	_marks.clear()
	_labels.clear()
	_rects.clear()
	_closed_rects.clear()
	_routes.clear()
	var all := sites()
	if model.get("regions", []).is_empty():
		queue_redraw()
		return
	art_mode = MapArt.has_world_art()
	if art_mode:
		art_rect = MapArt.world_rect(size)
		for r in all:
			_centers[r["id"]] = MapArt.world_point(art_rect, Vector2(r["pos"]))
		queue_redraw()
		return
	var mn: Vector2 = all[0]["pos"]
	var mx: Vector2 = all[0]["pos"]
	for r in all:
		mn = mn.min(r["pos"])
		mx = mx.max(r["pos"])
	var span := (mx - mn).max(Vector2.ONE)
	var area := (size - PAD * 2.0 - Vector2(0, 22)).max(Vector2(100, 100))
	var s0 := minf(area.x / span.x, area.y / span.y)
	var sc := Vector2(minf(area.x / span.x, s0 * MAX_STRETCH), minf(area.y / span.y, s0 * MAX_STRETCH))
	var used := span * sc
	var off := PAD + (area - used) / 2.0
	for r in all:
		_centers[r["id"]] = off + (Vector2(r["pos"]) - mn) * sc
	queue_redraw()

func center_of(region_id: String) -> Vector2:
	if _rects.is_empty() and not _centers.is_empty():
		_compute_geometry()
	return _centers.get(region_id, Vector2.ZERO)

func _font() -> Font:
	return get_theme_font("font", "Label")

func _site_font(st: Dictionary) -> Font:
	if bool(st["closed"]) or st["type"] == "WILD":
		return _font()
	return UiTheme.brush_font(0.3 if st["type"] == "CITY" else 0.15)

func _site_fs(st: Dictionary) -> int:
	if bool(st["closed"]):
		return 13
	match str(st["type"]):
		"CITY":
			return 22
		"SECT":
			return 17
		"DUNGEON":
			return 15
	return 14

## 門派地名一律帶「派／寺／宮／教／門」：地區名「華山」在地圖上寫成「華山派」，跟其他門派一致（M3a 審查）
const SECT_SUFFIXES := ["派", "寺", "宮", "教", "門"]
func _site_text(st: Dictionary) -> String:
	var nm := str(st["name"])
	if str(st.get("type", "")) == "SECT" and not bool(st["closed"]) and not SECT_SUFFIXES.has(nm.right(1)):
		nm += "派"
	return nm + (CLOSED_TAG if bool(st["closed"]) else "")

static func mark_size(st: Dictionary) -> float:
	if bool(st["closed"]):
		return 16.0
	match str(st["type"]):
		"CITY":
			return 26.0
		"SECT":
			return 20.0
		"DUNGEON":
			return 16.0
	return 10.0

## 版面：先把太擠的記號推開，再替每個地名挑一個不壓到別的記號、地名、道路的位置
func _compute_geometry() -> void:
	_marks.clear()
	_labels.clear()
	_rects.clear()
	_closed_rects.clear()
	var all := sites()
	var bounds := _bounds()
	# 1. 記號推開（用 MARK_SPACING 的框）
	var boxes := {}
	for st in all:
		if _centers.has(st["id"]):
			boxes[st["id"]] = Rect2(_centers[st["id"]] - MARK_SPACING / 2.0, MARK_SPACING)
	if not art_mode:   # 底圖模式：站點對齊底圖，不推開
		_separate(boxes, bounds.grow(-4.0))
		for id in boxes:
			_centers[id] = (boxes[id] as Rect2).get_center()
		_clear_roads(all, bounds)
	for st in all:
		if _centers.has(st["id"]):
			var m := mark_size(st)
			_marks[st["id"]] = Rect2(_centers[st["id"]] - Vector2(m, m) / 2.0, Vector2(m, m))
	# 2. 地名：城、門派、洞、野外、未開放的順序先挑
	var segs := walk_segments_raw()
	var order := all.duplicate()
	var rank := { "CITY": 0, "SECT": 1, "DUNGEON": 2, "WILD": 3 }
	order.sort_custom(func(a, b):
		var ra := 9 if bool(a["closed"]) else int(rank.get(a["type"], 5))
		var rb := 9 if bool(b["closed"]) else int(rank.get(b["type"], 5))
		if ra != rb:
			return ra < rb
		return str(a["id"]) < str(b["id"]))
	for st in order:
		if not _marks.has(st["id"]):
			continue
		_labels[st["id"]] = _place_label(st, segs, bounds)
	# 3. 記號＋地名的外框；還有重疊就整組推開（記號跟著走）
	var units := {}
	for st in all:
		if _marks.has(st["id"]):
			units[st["id"]] = (_marks[st["id"]] as Rect2).merge(_labels[st["id"]])
	var before := units.duplicate()
	if not art_mode:
		_separate(units, bounds)
	for id in units:
		var d: Vector2 = (units[id] as Rect2).position - (before[id] as Rect2).position
		if d != Vector2.ZERO:
			_marks[id] = Rect2((_marks[id] as Rect2).position + d, (_marks[id] as Rect2).size)
			_labels[id] = Rect2((_labels[id] as Rect2).position + d, (_labels[id] as Rect2).size)
			_centers[id] = (_marks[id] as Rect2).get_center()
	# 4. 整組推開後，記號可能又被推回道路旁（M3a 新地區讓西夏一帶更擠）：再清一次，地名跟著記號走
	var moved_from := _centers.duplicate()
	if not art_mode:
		_clear_roads(all, bounds)
	for id in units:
		var d2: Vector2 = _centers[id] - moved_from[id]
		if d2 == Vector2.ZERO:
			continue
		var nu := Rect2((units[id] as Rect2).position + d2, (units[id] as Rect2).size)
		var ok := bounds.encloses(nu)
		for o in units:
			if o != id and (units[o] as Rect2).intersects(nu):
				ok = false
				break
		if not ok:   # 推開會壓到別人：維持原位
			_centers[id] = moved_from[id]
			continue
		_marks[id] = Rect2((_marks[id] as Rect2).position + d2, (_marks[id] as Rect2).size)
		_labels[id] = Rect2((_labels[id] as Rect2).position + d2, (_labels[id] as Rect2).size)
		units[id] = nu
	for st in all:
		if not units.has(st["id"]):
			continue
		if bool(st["closed"]):
			_closed_rects[st["id"]] = units[st["id"]]
		else:
			_rects[st["id"]] = units[st["id"]]
	_routes.clear()
	for pair in model.get("travel", []):
		if _centers.has(pair[0]) and _centers.has(pair[1]):
			_routes["%s|%s" % [pair[0], pair[1]]] = travel_route(pair[0], pair[1])

## 記號離「不經過它的」道路太近時，沿垂直方向推開到 ROAD_CLEAR 以外。
## 審查 round 4：血刀洞迷宮的菱形貼在西夏北郊—西夏東郊那條路旁，自己通往西夏東郊的短路看起來像同一條，像是沒有路
const ROAD_CLEAR := 16.0

func _clear_roads(all: Array, bounds: Rect2) -> void:
	var pairs: Array = model.get("walk", [])
	for st in all:
		var id: String = st["id"]
		if not _centers.has(id):
			continue
		var need := mark_size(st) / 2.0 + ROAD_CLEAR
		for pr in pairs:
			if id == pr[0] or id == pr[1] or not (_centers.has(pr[0]) and _centers.has(pr[1])):
				continue
			var a: Vector2 = _centers[pr[0]]
			var b: Vector2 = _centers[pr[1]]
			var c: Vector2 = _centers[id]
			var q := Geometry2D.get_closest_point_to_segment(c, a, b)
			var d := c - q
			if d.length() >= need:
				continue
			var n := d.normalized() if d.length() > 0.01 else (b - a).orthogonal().normalized()
			var half := Vector2(mark_size(st), mark_size(st)) / 2.0
			_centers[id] = (q + n * need).clamp(bounds.position + half, bounds.end - half)

func _bounds() -> Rect2:
	if art_mode and art_rect.has_area():
		return Rect2(art_rect.position + Vector2(4, 4), art_rect.size - Vector2(8, 30))
	return Rect2(Vector2(8, 8), size - Vector2(16, 36))

func _place_label(st: Dictionary, segs: Array, bounds: Rect2) -> Rect2:
	var fs := _site_fs(st)
	var font := _site_font(st)
	var w := (font.get_string_size(_site_text(st), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else fs * 3.0) + 6.0
	var h := fs * 1.3
	var m: Rect2 = _marks[st["id"]]
	var c := m.get_center()
	var g := LABEL_GAP
	var cands := [
		Rect2(Vector2(m.end.x + g, c.y - h / 2.0), Vector2(w, h)),               # 右
		Rect2(Vector2(m.position.x - g - w, c.y - h / 2.0), Vector2(w, h)),      # 左
		Rect2(Vector2(c.x - w / 2.0, m.end.y + g * 0.5), Vector2(w, h)),         # 下
		Rect2(Vector2(c.x - w / 2.0, m.position.y - g * 0.5 - h), Vector2(w, h)),  # 上
		Rect2(Vector2(m.end.x + g, m.position.y - h), Vector2(w, h)),            # 右上
		Rect2(Vector2(m.end.x + g, m.end.y), Vector2(w, h)),                     # 右下
		Rect2(Vector2(m.position.x - g - w, m.position.y - h), Vector2(w, h)),   # 左上
		Rect2(Vector2(m.position.x - g - w, m.end.y), Vector2(w, h)),            # 左下
	]
	var best: Rect2 = cands[0]
	var best_cost := INF
	for r in cands:
		var cost := 0.0
		if not bounds.encloses(r):
			cost += 1000.0
		for id in _marks:
			if id != st["id"] and (_marks[id] as Rect2).grow(2.0).intersects(r):
				cost += 100.0
		for id in _labels:
			if (_labels[id] as Rect2).grow(2.0).intersects(r):
				cost += 100.0
		# 路線穿過地名（華陰道—終南山下穿過「古墓派」）：有別的位置就換（M3a UI 審查 #7；以前 3 分幾乎不影響選擇）
		for sg in segs:
			if MapLayout.segment_hits_rect(sg[0], sg[1], r):
				cost += LABEL_ROAD_COST
		# 地名離別的記號比離自己的記號還近：一眼看不出是誰的名字（審查：「華山」夾在恆山派與華山的山形之間）
		var own_d := rect_dist(r, c)
		for id in _marks:
			if id != st["id"] and rect_dist(r, (_marks[id] as Rect2).get_center()) + 2.0 < own_d:
				cost += 60.0
		if cost < best_cost:
			best_cost = cost
			best = r
			if cost == 0.0:
				break
	return best

const LABEL_ROAD_COST := 40.0

## 點到框的最短距離（地名歸屬判斷用）
static func rect_dist(r: Rect2, p: Vector2) -> float:
	var q := p.clamp(r.position, r.end)
	return q.distance_to(p)

## 依固定順序把重疊的框沿穿透較淺的軸推開（可重現），再夾回 bounds 內
const BOX_GAP := 6.0
static func _separate(rects: Dictionary, bounds: Rect2) -> void:
	var ids: Array = rects.keys()
	ids.sort()
	for _iter in 300:
		var moved := false
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var a: Rect2 = rects[ids[i]]
				var b: Rect2 = rects[ids[j]]
				var ag := a.grow(BOX_GAP / 2.0)
				var bg := b.grow(BOX_GAP / 2.0)
				if not ag.intersects(bg):
					continue
				var d := b.get_center() - a.get_center()
				var px := (ag.size.x + bg.size.x) / 2.0 - absf(d.x)
				var py := (ag.size.y + bg.size.y) / 2.0 - absf(d.y)
				var sx := 1.0 if d.x > 0.0 or (d.x == 0.0 and i % 2 == 0) else -1.0
				var sy := 1.0 if d.y > 0.0 or (d.y == 0.0 and i % 2 == 0) else -1.0
				var push_x := Vector2((px / 2.0 + 0.5) * sx, 0.0)
				var push_y := Vector2(0.0, (py / 2.0 + 0.5) * sy)
				var push := push_x if px < py else push_y
				if not (bounds.encloses(Rect2(a.position - push, a.size)) and bounds.encloses(Rect2(b.position + push, b.size))):
					push = push_y if px < py else push_x
				rects[ids[i]] = _clamp_rect(Rect2(a.position - push, a.size), bounds)
				rects[ids[j]] = _clamp_rect(Rect2(b.position + push, b.size), bounds)
				moved = true
		if not moved:
			break
	for id in ids:
		rects[id] = _clamp_rect(rects[id], bounds)

static func _clamp_rect(r: Rect2, bounds: Rect2) -> Rect2:
	if not bounds.has_area():
		return r
	var p := r.position.clamp(bounds.position, (bounds.end - r.size).max(bounds.position))
	return Rect2(p, r.size)

func routes() -> Dictionary:
	if _rects.is_empty() and not _centers.is_empty():
		_compute_geometry()
	return _routes

## 步行線：記號中心到記號中心（排版時用）
func walk_segments_raw() -> Array:
	var out: Array = []
	for pair in model.get("walk", []):
		if _centers.has(pair[0]) and _centers.has(pair[1]):
			out.append([_centers[pair[0]], _centers[pair[1]]])
	return out

## 步行線（畫出來的樣子）：從記號邊緣到記號邊緣
func walk_segments() -> Array:
	if _rects.is_empty() and not _centers.is_empty():
		_compute_geometry()
	var out: Array = []
	for pair in model.get("walk", []):
		if not (_marks.has(pair[0]) and _marks.has(pair[1])):
			continue
		var a: Rect2 = _marks[pair[0]]
		var b: Rect2 = _marks[pair[1]]
		var d := b.get_center() - a.get_center()
		if d.length_squared() < 1.0:
			continue
		var n := d.normalized()
		out.append([MapLayout.box_edge_point(a.get_center(), a.size / 2.0 + Vector2(2, 2), n),
			MapLayout.box_edge_point(b.get_center(), b.size / 2.0 + Vector2(2, 2), -n)])
	return out

## 驛站路線：繞開其他地點（記號＋地名）的折線。
## M3b 整合：多了 8 個地區（高昌在最西邊，全圖被壓扁），760×440 時地點之間的縫比 6px 留白＋格子間距窄，
## 先用寬留白找，找不到再逐步縮小留白（線可以貼著方框走，但不穿過）。
const ROUTE_MARGINS := [[6.0, 4.0], [3.0, 2.0], [1.0, 0.5]]
func travel_route(a: String, b: String) -> PackedVector2Array:
	var raw: Array = []
	for id in _rects:
		if id != a and id != b:
			raw.append(_rects[id])
	for id in _closed_rects:
		raw.append(_closed_rects[id])
	var best := PackedVector2Array([_centers[a], _centers[b]])
	var best_hits := 1 << 30
	for mg in ROUTE_MARGINS:
		var obstacles: Array = []
		for r in raw:
			obstacles.append((r as Rect2).grow(float(mg[0])))
		var pts := MapLayout.route_around(_centers[a], _centers[b], obstacles, _bounds(), float(mg[1]))
		var hits := MapLayout.count_hits(pts, raw)
		if hits == 0:
			return pts
		if hits < best_hits:
			best_hits = hits
			best = pts
	return best

## 「你在這裡」標籤的位置：挑第一個不壓到線、地點的
func here_label() -> Dictionary:
	if _rects.is_empty() and not _centers.is_empty():
		_compute_geometry()
	if not _rects.has(current_region):
		return {}
	var r: Rect2 = _rects[current_region]
	var w := Vector2(maxf(_text_w(HERE_BELOW, 12), 70.0) + 6.0, 16.0)
	var c := r.get_center()
	var cands := [
		[Rect2(Vector2(c.x - w.x / 2.0, r.end.y + 3.0), w), HERE_BELOW],
		[Rect2(Vector2(c.x - w.x / 2.0, r.position.y - 3.0 - w.y), w), HERE_ABOVE],
		[Rect2(Vector2(c.x - w.x - 6.0, r.end.y + 3.0), w), HERE_BELOW],
		[Rect2(Vector2(c.x + 6.0, r.end.y + 3.0), w), HERE_BELOW],
		[Rect2(Vector2(c.x - w.x - 6.0, r.position.y - 3.0 - w.y), w), HERE_ABOVE],
		[Rect2(Vector2(c.x + 6.0, r.position.y - 3.0 - w.y), w), HERE_ABOVE],
		[Rect2(Vector2(r.end.x + 4.0, c.y - w.y / 2.0), w), "◀ 你在這裡"],
		[Rect2(Vector2(r.position.x - 4.0 - w.x, c.y - w.y / 2.0), w), "你在這裡 ▶"],
		[Rect2(Vector2(r.end.x + 4.0, r.position.y), w), "◀ 你在這裡"],
		[Rect2(Vector2(r.position.x - 4.0 - w.x, r.position.y), w), "你在這裡 ▶"],
		[Rect2(Vector2(r.end.x + 4.0, r.end.y - w.y), w), "◀ 你在這裡"],
		[Rect2(Vector2(r.position.x - 4.0 - w.x, r.end.y - w.y), w), "你在這裡 ▶"],
		[Rect2(Vector2(c.x - w.x / 2.0, r.end.y + 3.0 + w.y), w), HERE_BELOW],
		[Rect2(Vector2(c.x - w.x / 2.0, r.position.y - 3.0 - w.y * 2.0), w), HERE_ABOVE],
		# 再遠一格的備選（門派地名改成貼著自己的記號之後，終南山一帶更擠）
		[Rect2(Vector2(c.x - w.x - 6.0, r.end.y + 3.0 + w.y), w), HERE_BELOW],
		[Rect2(Vector2(c.x + 6.0, r.end.y + 3.0 + w.y), w), HERE_BELOW],
		[Rect2(Vector2(c.x - w.x - 6.0, r.position.y - 3.0 - w.y * 2.0), w), HERE_ABOVE],
		[Rect2(Vector2(c.x + 6.0, r.position.y - 3.0 - w.y * 2.0), w), HERE_ABOVE],
		[Rect2(Vector2(r.end.x + 4.0, c.y + w.y), w), "◀ 你在這裡"],
		[Rect2(Vector2(r.position.x - 4.0 - w.x, c.y + w.y), w), "你在這裡 ▶"],
		[Rect2(Vector2(r.end.x + 4.0, c.y - w.y * 2.0), w), "◀ 你在這裡"],
		[Rect2(Vector2(r.position.x - 4.0 - w.x, c.y - w.y * 2.0), w), "你在這裡 ▶"],
	]
	# 還找不到空位：在記號四周一圈一圈往外找（上下各 4 列、左中右三欄），箭頭指向記號那一側
	for ring in range(2, 5):
		for side in [-1, 1]:
			var y := r.end.y + 3.0 + w.y * (ring - 1) if side > 0 else r.position.y - 3.0 - w.y * ring
			var txt: String = HERE_BELOW if side > 0 else HERE_ABOVE
			for x in [c.x - w.x / 2.0, c.x - w.x - 6.0, c.x + 6.0, c.x - w.x * 1.5 - 12.0, c.x + w.x * 0.5 + 12.0]:
				cands.append([Rect2(Vector2(x, y), w), txt])
	# M3b 整合：地區變多（760×440 時靈鷲一帶全是路），再往外找一圈格點（每 8px，半徑 ≤ 150px），箭頭仍指向記號那一側
	for dy in range(-150, 151, 8):
		for dx in range(-150, 151, 8):
			var p := c + Vector2(dx, dy) - w / 2.0
			var rr := Rect2(p, w)
			if rr.intersects(r.grow(2.0)):
				continue
			var txt2: String = HERE_BELOW if dy > 0 else HERE_ABOVE
			if absf(dx) > absf(dy):
				txt2 = "◀ 你在這裡" if dx > 0 else "你在這裡 ▶"
			cands.append([rr, txt2])
	var segs := walk_segments()
	for pts in routes().values():
		for i in (pts as PackedVector2Array).size() - 1:
			segs.append([pts[i], pts[i + 1]])
	var others: Array = []
	for id in _rects:
		if id != current_region:
			others.append(_rects[id])
	for id in _closed_rects:
		others.append(_closed_rects[id])
	var rects: Array = []
	for cd in cands:
		rects.append(cd[0])
	var bounds := Rect2(Vector2.ZERO, size - Vector2(0, 28))
	# M3c 審查（「你在這裡 ▶」貼在高昌旁邊、看起來像在高昌）：同樣不壓線的位置裡，優先挑離自己的記號比離別的地點近的；
	# 都不行時照舊，但一定畫引線接到自己的朱紅圈（leader_for）。
	# 第二輪審查（引線劃過「西夏」兩個字）：引線劃過任何地名也算一個缺點。依序比：壓到的線與地點（×10，
	# 一定優先：「不壓線」是既有的保證）、引線劃過地名（×3）、離別的地點較近（×1）；同分取前面的候選
	var mark: Rect2 = _marks.get(current_region, r)
	var i := 0
	var best := INF
	for k in rects.size():
		var h := _hits(rects[k], segs, others, bounds)
		if float(h) * 10.0 >= best:
			continue
		var score := float(h) * 10.0
		if _leader_blocked(rects[k], mark):
			score += 3.0
		if _nearer_other(rects[k], mark):
			score += 1.0
		score += here_style_penalty(rects[k], str(cands[k][1]), mark)
		if score < best:
			best = score
			i = k
			if score == 0.0:
				break
	var hr: Rect2 = rects[i]
	var txt_out: String = cands[i][1]
	# M3c 第三輪審查：擠到離記號遠的空位時，▲／▶ 會指著別的地方（「星宿派 ▲你在這裡」）→ 不畫箭頭，只靠引線接到朱紅圈
	if rect_dist(hr, mark.get_center()) > HERE_FAR:
		txt_out = HERE_PLAIN
	return { "rect": hr, "text": txt_out, "leader": leader_for(hr, mark) }

## M3c 第三輪審查（103／104：在城裡時「高昌 你在這裡▶ 西夏」——標籤擠在別的地名同一行，▶ 指著「西夏」兩個字而不是朱紅圈；
## 在野外時是圈上方的「▼ 你在這裡」，兩種擺法不一致）。不壓線的位置裡再加三個小缺點：
## - 箭頭（◀／▶）指著自己的地名（地名夾在標籤與記號中間）：+3
## - 離別的地名或記號太近（左右 14px、上下 6px 內）：各 +2；箭頭前方 28px 內是別的地點：+3
## - 放在記號左右兩側（◀／▶）而不是上下（▼／▲，與野外一致）：+0.5
## - 離自己的記號超過 40px：每多 40px +1
func here_style_penalty(hr: Rect2, txt: String, mark: Rect2) -> float:
	var p := 0.0
	var own: Rect2 = _labels.get(current_region, Rect2())
	var side_right := txt.ends_with("▶")
	var side_left := txt.begins_with("◀")
	if own.has_area() and (side_right or side_left):
		var v_overlap := own.position.y < hr.end.y and own.end.y > hr.position.y
		if v_overlap and side_right and own.position.x >= hr.end.x - 1.0 and own.end.x <= mark.position.x + 1.0:
			p += 3.0
		elif v_overlap and side_left and own.position.x >= mark.end.x - 1.0 and own.end.x <= hr.position.x + 1.0:
			p += 3.0
	var near := hr.grow_individual(14.0, 6.0, 14.0, 6.0)
	for id in _labels:
		if id != current_region and near.intersects(_labels[id]):
			p += 2.0
			break
	for id in _marks:
		if id != current_region and near.intersects(_marks[id]):
			p += 2.0
			break
	# 箭頭前方 28px 內是別的地點（地名或記號）：箭頭看起來指著別處（「星宿派 ▲你在這裡」）
	var ahead := hr
	if txt.begins_with("▲"):
		ahead = hr.grow_individual(0.0, 28.0, 0.0, -hr.size.y)
	elif txt.begins_with("▼"):
		ahead = hr.grow_individual(0.0, -hr.size.y, 0.0, 28.0)
	elif side_left:
		ahead = hr.grow_individual(28.0, 0.0, -hr.size.x, 0.0)
	elif side_right:
		ahead = hr.grow_individual(-hr.size.x, 0.0, 28.0, 0.0)
	if ahead != hr:
		var hit := false
		for id in _labels:
			if id != current_region and ahead.intersects(_labels[id]):
				hit = true
		for id in _marks:
			if id != current_region and ahead.intersects(_marks[id]):
				hit = true
		if hit:
			p += 3.0
	if side_right or side_left:
		p += 0.5
	# 離自己的記號越遠越差（40px 內不扣；以前會挑到 140px 外、貼著星宿派的空位）
	p += maxf(0.0, rect_dist(hr, mark.get_center()) - 40.0) / 40.0
	return p

## 與 MapLayout.pick_free_rect 同一套計分（出界 100、每條線或每個障礙 1）
func _hits(c: Rect2, segs: Array, others: Array, bounds: Rect2) -> int:
	var n := 0
	if bounds.has_area() and not bounds.encloses(c):
		n += 100
	for sg in segs:
		if MapLayout.segment_hits_rect(sg[0], sg[1], c):
			n += 1
	for o in others:
		if (o as Rect2).intersects(c):
			n += 1
	return n

## 引線實際畫的幾段：經過地名框（外擴 2px）的部分拿掉。[[a, b], …]
func leader_pieces(lead: Array) -> Array:
	var out: Array = []
	if lead.size() != 2:
		return out
	var a: Vector2 = lead[0]
	var b: Vector2 = lead[1]
	var n := maxi(8, int(a.distance_to(b) / 2.0))
	var start := -1
	for i in n + 1:
		var t := float(i) / float(n)
		var p := a.lerp(b, t)
		var inside := false
		for id in _labels:
			if (_labels[id] as Rect2).grow(2.0).has_point(p):
				inside = true
				break
		if not inside and start < 0:
			start = i
		elif inside and start >= 0:
			if i - 1 > start:
				out.append([a.lerp(b, float(start) / n), a.lerp(b, float(i - 1) / n)])
			start = -1
	if start >= 0 and start < n:
		out.append([a.lerp(b, float(start) / n), b])
	return out

## M3c 第二輪審查：這個位置要畫的引線會劃過地名（自己的「西夏」或別人的）→ 不選它
func _leader_blocked(hr: Rect2, mark: Rect2) -> bool:
	var lead := leader_for(hr, mark)
	if lead.size() != 2:
		return false
	for id in _labels:
		if MapLayout.segment_hits_rect(lead[0], lead[1], (_labels[id] as Rect2).grow(1.0)):
			return true
	return false

## 這個框離別的地點記號比離自己的記號還近
func _nearer_other(hr: Rect2, mark: Rect2) -> bool:
	var d_own := rect_dist(hr, mark.get_center())
	for id in _marks:
		if id != current_region and rect_dist(hr, (_marks[id] as Rect2).get_center()) + 2.0 < d_own:
			return true
	return false

## 「你在這裡」到朱紅圈的引線 [標籤邊上的點, 圈上的點]；標籤貼著記號（< 6px）而且離自己最近時不畫（[]）
func leader_for(hr: Rect2, mark: Rect2) -> Array:
	var mc := mark.get_center()
	var edge := mc + (hr.get_center() - mc).normalized() * (maxf(mark.size.x, mark.size.y) * 0.75 + 5.0)
	var tip := Vector2(clampf(edge.x, hr.position.x, hr.end.x), clampf(edge.y, hr.position.y, hr.end.y))
	if tip.distance_to(edge) > 6.0 or _nearer_other(hr, mark):
		return [tip, edge]
	return []

# ---------------------------------------------------------------- 繪製

func _draw() -> void:
	if art_mode:
		_draw_base_art()
	else:
		_draw_parchment()
	if _centers.is_empty():
		_text(size / 2.0, "（沒有區域位置資料）", 16, WALK)
		return
	var rs := routes()
	for k in rs:
		_dashed_polyline(rs[k], TRAVEL, 2.0, 9.0)
	for seg in walk_segments():
		draw_line(seg[0], seg[1], Color(WALK, 0.25), 5.0, true)   # 墨暈
		draw_line(seg[0], seg[1], WALK, 2.0, true)
	# M3c 第二輪審查：趕路路線先畫（地點的印記、地名蓋在線上面；線頭停在記號的圈外，不壓「大」「西」的印）
	_draw_walk_route_lines()
	for st in sites():
		var id: String = st["id"]
		if not _marks.has(id):
			continue
		_draw_mark(st, _marks[id])
		_draw_label(st, _labels[id])
	_draw_walk_route()
	if _marks.has(current_region):
		var m: Rect2 = _marks[current_region]
		var rad := maxf(m.size.x, m.size.y) * 0.75 + 5.0
		draw_arc(m.get_center(), rad, 0.0, TAU, 40, Color(CUR, 0.9), 2.5, true)
		MapToken.draw(self, token_tex, Vector2(m.get_center().x, m.get_center().y - rad * 0.2), clampf(rad * 2.2, 26.0, 48.0), get_theme_default_font())
	var here := here_label()
	if not here.is_empty():
		var hr: Rect2 = here["rect"]
		# M3c 審查：標籤離記號遠一點、或離別的地點比較近時，畫一條細引線接到朱紅圈，不會讓人以為指的是隔壁的地點
		var lead: Array = here.get("leader", [])
		if lead.size() == 2:
			# M3c 第二輪審查：引線經過地名（例：「你在這裡 ▶」在「西夏」左邊）時，字的部分留白，不畫刪除線
			for pc in leader_pieces(lead):
				draw_line(pc[0], pc[1], Color(CUR, 0.85), 1.5, true)
		_text(hr.get_center(), str(here["text"]), 12, CUR, true)
	_draw_compass()
	_draw_title()
	_draw_legend()

## 底圖模式：4:3 以外的區域用暗木色；底圖畫滿 art_rect
func _draw_base_art() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.JY_WOOD_DARK)
	var tex := MapArt.texture("world_base")
	if tex != null:
		draw_texture_rect(tex, art_rect, false)
	else:
		draw_rect(art_rect, BG)
	draw_rect(art_rect.grow(-1.0), Color(WALK, 0.55), false, 1.5)

## 標題框（map_frame_title）：有圖才畫（程式繪圖版本沒有標題，維持原樣）
func _draw_title() -> void:
	var tex := MapArt.texture("frame_title")
	if tex == null:
		return
	var area := art_rect if art_mode and art_rect.has_area() else Rect2(Vector2.ZERO, size)
	var w := minf(220.0, area.size.x * 0.3)
	var h := w / 4.0
	# 下緣正中（原作座標南邊 y > 800 幾乎沒有地點；上緣是靈鷲、西夏、雁門一帶，會被蓋住）
	var r := Rect2(Vector2(area.get_center().x - w / 2.0, area.end.y - h - 30.0), Vector2(w, h))
	draw_texture_rect(tex, r, false)
	var f := UiTheme.brush_font(0.3)
	var fs := int(h * 0.48)
	var tw := f.get_string_size(TITLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(r.get_center().x - tw / 2.0, r.get_center().y + fs * 0.36), TITLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.INK)

func _draw_parchment() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, BG)
	# 邊緣暗一點（舊紙），用幾層半透明框做暈
	for i in 6:
		var a := 0.07 * (6 - i) / 6.0
		draw_rect(r.grow(-i * 3.0), Color(BG_EDGE, a), false, 3.0)
	draw_rect(r.grow(-2.0), Color(WALK, 0.55), false, 1.5)

func _draw_mark(st: Dictionary, m: Rect2) -> void:
	var c := m.get_center()
	var s := m.size.x
	if bool(st["closed"]):
		_mountain(c, s, Color(GREY, 0.9), Color(GREY, 0.35))
		return
	var icon := MapArt.icon(str(MapArt.SITE_ICONS.get(str(st["type"]), "")))
	if icon != null:
		var isz := maxf(s, 18.0)
		draw_texture_rect(icon, Rect2(c - Vector2(isz, isz) / 2.0, Vector2(isz, isz)), false)
		return
	match str(st["type"]):
		"CITY":
			# 朱紅印章：方塊、內框白線、中間一個白字
			draw_rect(m, SEAL)
			draw_rect(m.grow(-3.0), Color(1, 0.95, 0.85, 0.85), false, 1.2)
			var f := UiTheme.brush_font(0.3)
			var ch := str(st["name"]).left(1)
			var fs := int(s * 0.62)
			var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, c + Vector2(-w / 2.0, fs * 0.36), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("fff4e0"))
		"SECT":
			_mountain(c, s, UiTheme.INK, Color(UiTheme.INK, 0.25))
		"DUNGEON":
			var pts := PackedVector2Array([c + Vector2(0, -s / 2.0), c + Vector2(s / 2.0, 0), c + Vector2(0, s / 2.0), c + Vector2(-s / 2.0, 0)])
			draw_colored_polygon(pts, Color("3a2e26"))
			pts.append(pts[0])
			draw_polyline(pts, Color("f0e2c0", 0.8), 1.0, true)
		_:
			draw_circle(c, s / 2.0, WALK)
			draw_circle(c, s / 2.0 - 2.5, BG)

## 墨色山形（三座峰）
func _mountain(c: Vector2, s: float, ink: Color, fill: Color) -> void:
	var h := s * 0.5
	var pts := PackedVector2Array([c + Vector2(-s * 0.6, h * 0.7), c + Vector2(-s * 0.2, -h * 0.4), c + Vector2(0, h * 0.0),
		c + Vector2(s * 0.12, -h * 0.95), c + Vector2(s * 0.6, h * 0.7)])
	draw_colored_polygon(pts, fill)
	draw_polyline(pts, ink, 2.0, true)

func _draw_label(st: Dictionary, r: Rect2) -> void:
	var fs := _site_fs(st)
	var font := _site_font(st)
	if font == null:
		return
	var col := UiTheme.INK
	if bool(st["closed"]):
		col = GREY
	elif st["type"] == "WILD":
		col = Color("4a3a28")
	var t := _site_text(st)
	var p := Vector2(r.position.x + 3.0, r.position.y + r.size.y / 2.0 + fs * 0.36)
	# 羊皮紙色底：真的避不開路線時，線從字底下過、不會穿過字（M3a UI 審查 #7）
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(BG, 0.86)
	bg.set_corner_radius_all(3)
	draw_style_box(bg, r)
	# 羊皮紙色描邊：路線從字旁邊經過時字仍然清楚
	draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(BG, 0.9))
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw_compass() -> void:
	var ctex := MapArt.texture("compass")
	if ctex != null:
		# 有羅盤圖：畫在右下（取代程式羅盤）
		var area := art_rect if art_mode and art_rect.has_area() else Rect2(Vector2.ZERO, size)
		var cs := clampf(area.size.y * 0.16, 56.0, 110.0)
		draw_texture_rect(ctex, Rect2(area.end - Vector2(cs + 10.0, cs + 34.0), Vector2(cs, cs)), false)
		return
	var c := Vector2(size.x - 34.0, 34.0)
	draw_line(c + Vector2(0, 14), c + Vector2(0, -14), WALK, 1.5, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -18), c + Vector2(-5, -8), c + Vector2(5, -8)]), SEAL)
	_text(c + Vector2(0, -28), "北", 13, WALK)

func _draw_legend() -> void:
	var ly := size.y - 16.0
	var x := 16.0
	if art_mode and art_rect.has_area():
		# 底圖模式：圖例放在底圖左下角，底下墊一條半透明紙色
		ly = art_rect.end.y - 16.0
		x = art_rect.position.x + 12.0
		draw_rect(Rect2(Vector2(art_rect.position.x + 4.0, ly - 12.0), Vector2(minf(art_rect.size.x - 8.0, 520.0), 24.0)), Color(BG, 0.8))
	draw_line(Vector2(x, ly), Vector2(x + 28, ly), WALK, 2.0)
	_text_left(Vector2(x + 34, ly), "步行相連", 12, WALK)
	x += 96.0
	if not (model.get("travel", []) as Array).is_empty():
		# 驛站馬車【設計提案・非原作】只有伺服器開了 stagecoach_enabled 才有路線
		draw_dashed_line(Vector2(x, ly), Vector2(x + 28, ly), TRAVEL, 2.0, 6.0)
		_text_left(Vector2(x + 34, ly), "驛站路線", 12, TRAVEL)
		x += 96.0
	var items := [["CITY", "城"], ["SECT", "門派"], ["DUNGEON", "洞窟"], ["WILD", "野外"], ["CLOSED", "未開放"]]
	for it in items:
		var st := { "type": it[0] if it[0] != "CLOSED" else "SECT", "closed": it[0] == "CLOSED", "name": "城" }
		var m := 14.0 if it[0] != "WILD" else 9.0
		_draw_mark(st, Rect2(Vector2(x, ly - m / 2.0), Vector2(m, m)))
		_text_left(Vector2(x + m + 5.0, ly), it[1], 12, WALK)
		x += m + 10.0 + _text_w(it[1], 12) + 14.0

## 沿折線畫虛線（相位跨線段延續，曲線上的虛線才均勻）
func _dashed_polyline(pts: PackedVector2Array, color: Color, width: float, dash: float) -> void:
	var on := true
	var left := dash
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg_len := a.distance_to(b)
		var pos := 0.0
		while pos < seg_len:
			var step := minf(left, seg_len - pos)
			if on:
				draw_line(a.lerp(b, pos / seg_len), a.lerp(b, (pos + step) / seg_len), color, width, true)
			pos += step
			left -= step
			if left <= 0.0:
				on = not on
				left = dash

func _text_w(text: String, fsize: int) -> float:
	var font := _font()
	return 0.0 if font == null or text == "" else font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x

func _text(at: Vector2, text: String, fsize: int, color: Color, backdrop := false) -> void:
	var font := _font()
	if font == null:
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var tl := at - w / 2.0
	if backdrop:
		draw_rect(Rect2(tl - Vector2(3, 1), w + Vector2(6, 2)), Color(BG, 0.85))
	draw_string(font, tl + Vector2(0, font.get_ascent(fsize)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)

func _text_left(at: Vector2, text: String, fsize: int, color: Color) -> void:
	var font := _font()
	if font == null:
		return
	var h := font.get_height(fsize)
	draw_string(font, Vector2(at.x, at.y - h / 2.0 + font.get_ascent(fsize)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := region_at(event.position)
		if id != "":
			region_clicked.emit(id)
			accept_event()

func region_at(p: Vector2) -> String:
	if _rects.is_empty() and not _centers.is_empty():
		_compute_geometry()
	for id in _rects:
		if (_rects[id] as Rect2).has_point(p):
			return id
	return ""

func closed_at(p: Vector2) -> String:
	for id in _closed_rects:
		if (_closed_rects[id] as Rect2).has_point(p):
			return id
	return ""

func _get_tooltip(at_position: Vector2) -> String:
	var cid := closed_at(at_position)
	if cid != "":
		for c in CLOSED_SITES:
			if c["id"] == cid:
				return "%s\n尚未開放（1.0 開服時山門封閉，只有岔路）" % c["name"]
	var id := region_at(at_position)
	if id == "":
		return ""
	for r in model.get("regions", []):
		if r["id"] == id:
			var lines: PackedStringArray = [str(r["name"])]
			var xp := MapData.xp_text(r["xp"])
			if xp != "":
				lines.append(xp)
			var links: PackedStringArray = []
			for pair in model.get("travel", []):
				if pair.has(id):
					links.append(_name(pair[1] if pair[0] == id else pair[0]))
			if not links.is_empty():
				lines.append("驛站可達：%s" % "、".join(links))
			if id == current_region:
				lines.append("你在這裡")
			else:
				lines.append("點擊趕路前往（只走去過的地方）")
			return "\n".join(lines)
	return ""

# ---------------------------------------------------------------- 趕路路線（M3c 審查：全圖上看不出要去哪）
## walk_route = 經過的地區 [目前, …, 目的地]（MapPanel.route_regions）；畫藍色粗線連起來、目的地加圈與「目的地」字
var walk_route: Array = []
const ROUTE_COLOR := Color("1f5fa8")
const DEST_TEXT := "目的地"

func set_walk_route(regions: Array) -> void:
	if regions == walk_route:
		return
	walk_route = regions.duplicate()
	queue_redraw()

## 路線的線段（兩端各退到記號的圈外）：[[a 點, b 點], …]
func walk_route_segments() -> Array:
	var out: Array = []
	for i in walk_route.size() - 1:
		var a := str(walk_route[i])
		var b := str(walk_route[i + 1])
		if not (_centers.has(a) and _centers.has(b)):
			continue
		var pa: Vector2 = _centers[a]
		var pb: Vector2 = _centers[b]
		var dir := (pb - pa).normalized()
		var ra := _mark_radius(a)
		var rb := _mark_radius(b)
		if pa.distance_to(pb) <= ra + rb + 2.0:
			continue
		out.append([pa + dir * ra, pb - dir * rb])
	return out

func _mark_radius(id: String) -> float:
	if not _marks.has(id):
		return 0.0
	var m: Rect2 = _marks[id]
	return maxf(m.size.x, m.size.y) * 0.75 + 5.0

func _draw_walk_route_lines() -> void:
	if walk_route.size() < 2:
		return
	for sg in walk_route_segments():
		draw_line(sg[0], sg[1], Color(ROUTE_COLOR, 0.25), 9.0, true)
		draw_line(sg[0], sg[1], ROUTE_COLOR, 3.5, true)

## 「目的地」字框：圈的上、下、左、右、斜角裡第一個不壓到地名、記號、路線的（M3c 第二輪審查：以前固定在圈上方，
## 蓋住「大理郊外」的「外」和它的站點）
func dest_label_rect() -> Rect2:
	if walk_route.size() < 2:
		return Rect2()
	var dest := str(walk_route[walk_route.size() - 1])
	if not _marks.has(dest):
		return Rect2()
	var c: Vector2 = (_marks[dest] as Rect2).get_center()
	var rad := _mark_radius(dest)
	var w := Vector2(_text_w(DEST_TEXT, 12) + 6.0, 16.0)
	var cands: Array = []
	for off in [Vector2(0, -rad - w.y / 2.0 - 2.0), Vector2(0, rad + w.y / 2.0 + 2.0),
			Vector2(-rad - w.x / 2.0 - 2.0, 0), Vector2(rad + w.x / 2.0 + 2.0, 0),
			Vector2(-rad * 0.8 - w.x / 2.0, -rad * 0.8 - w.y / 2.0), Vector2(rad * 0.8 + w.x / 2.0, -rad * 0.8 - w.y / 2.0),
			Vector2(-rad * 0.8 - w.x / 2.0, rad * 0.8 + w.y / 2.0), Vector2(rad * 0.8 + w.x / 2.0, rad * 0.8 + w.y / 2.0)]:
		cands.append(Rect2(c + (off as Vector2) - w / 2.0, w))
	var others: Array = []
	for id in _labels:
		others.append(_labels[id])
	for id in _marks:
		if id != dest:
			others.append(_marks[id])
	var segs: Array = walk_route_segments()
	var i := MapLayout.pick_free_rect(cands, segs, others, Rect2(Vector2.ZERO, size - Vector2(0, 28)))
	return cands[i]

func _draw_walk_route() -> void:
	if walk_route.size() < 2:
		return
	var dest := str(walk_route[walk_route.size() - 1])
	if _marks.has(dest):
		var m: Rect2 = _marks[dest]
		draw_arc(m.get_center(), _mark_radius(dest), 0.0, TAU, 40, ROUTE_COLOR, 3.0, true)
		var dr := dest_label_rect()
		if dr.has_area():
			_text(dr.get_center(), DEST_TEXT, 12, ROUTE_COLOR, true)

func _name(id: String) -> String:
	for r in model.get("regions", []):
		if r["id"] == id:
			return str(r["name"])
	return id
