class_name RegionMapView
extends Control
## 區域圖：依 MapLayout 的格子座標畫房間方框與連線；只畫到過的房間，相鄰沒去過的畫「？」。
## 標出玩家所在、NPC／地形小字、離開本區的出口箭頭（標目標區域名）、遇敵房間（滑鼠停留顯示怪物）。
## 任何左鍵點擊 → room_clicked(room_id)；點在空白處 room_id 為 ""（趕路中用來取消）。
## M3c（M3C_PLAN §4.5）：點「往XXX」出區箭頭或它的字 → region_clicked(region_id)（地圖面板把畫面切到那個鄰區）；
## 右鍵 → context_requested（小地圖的快捷目的地選單）。瀏覽別區時（目前房間不在本區）以 focus_room 當畫面中心。
## M3c（§4.6）：有地圖美術（MapArt）時 region_bg 平鋪當底、房間框用 node_room／node_current／node_fog 9 宮格、
## 小字改畫 map_icon_*、「你在這裡」畫 marker_here；沒有圖時完全是原本的程式繪圖。

signal room_clicked(room_id: String)
signal region_clicked(region_id: String)
signal context_requested(at: Vector2)

const CELL := Vector2(150, 92)
const BOX := Vector2(118, 54)
const PAD := Vector2(110, 70)
const ARROW_LEN := 46.0
const NAME_SIZE := 15
const BADGE_SIZE := 12

const BG := Color("efe4cc")
const LINE := Color("8c7a5b")
const BOX_FILL := Color("f8f1e2")
const BOX_EDGE := Color("5b4a36")
const CUR_FILL := Color("f6d9cf")
const UNKNOWN_FILL := Color(0.55, 0.5, 0.42, 0.18)
const UNKNOWN_EDGE := Color("a69a86")
const OUT_COLOR := Color("2e6db4")
const DANGER := Color("b03a2e")
const BADGE := Color("6b4f2a")
const TARGET := Color("2e6db4")
const HERE_ABOVE := "▼ 你在這裡"
const BG_TILE_SCALE := 0.5      # map_region_bg（1024×1024）平鋪時的縮放
const HERE_BELOW := "▲ 你在這裡"

var tables: Dictionary = {}
var model: Dictionary = {}       # MapData.region_model
var visited: Dictionary = {}
var current := ""
var walk_target := ""
## 任務提示地點（任務窗「在地圖上標出」；STORY_PLAN §6.2 hint_room）：方框外加金色虛框與「任務」小字
var quest_mark := ""
const QUEST_MARK := Color("d08a10")
const QUEST_MARK_TEXT := "★任務"
var _vis: Dictionary = {}
var _unk: Dictionary = {}
var _rects: Dictionary = {}      # room_id -> Rect2
var _offset := Vector2.ZERO      # 內容比可視範圍小時置中；follow_current 時讓目前房間置中
var content_size := Vector2.ZERO  # 整張區域圖需要的大小
var _origin := Vector2i.ZERO     # 畫得出來的房間範圍左上角（格子座標）
var follow_current := false      # 主畫面小地圖：不撐大自己，畫面跟著玩家走
## 縮放（主畫面小地圖 ~190×140：原尺寸只看得到目前這一間，鄰房都在框外點不到）。
## _rects 等都是未縮放的內容座標；畫面座標 = 內容座標 × zoom（screen_rect()、room_at() 已換算）。
## 縮小時房名用大一點的字（name_size()），縮完仍看得清楚。
var zoom := 1.0
## 小地圖（follow_current）：最大縮放＝這個值；目前房間、相鄰的房間與它們的出區箭頭放不下時再縮小（最小 MIN_FOLLOW_ZOOM），
## 並讓這一圈置中，而不是死板地讓目前房間置中（審查 round 4：上下排房間、往大理郊外的箭頭被框切掉）
var follow_zoom_max := 0.55
const MIN_FOLLOW_ZOOM := 0.46
const FOLLOW_MARGIN := 5.0         # 畫面 px
## 瀏覽別區（目前房間不在本區）時畫面跟著這一間（小地圖）；空字串＝沒有
var focus_room := ""
## 本區一間都沒去過時畫在中間的字（瀏覽沒去過的鄰區）
var empty_text := "那裡還沒去過"
var _segments: Array = []        # 這次畫出的連線／出口箭頭 [p, q]（標籤避開用）
var _label_rects: Array = []     # 出口箭頭的文字框

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(_relayout)

func setup(p_tables: Dictionary, p_model: Dictionary, p_visited: Dictionary, p_current: String) -> void:
	_oe_cache_key = ""
	tables = p_tables
	model = p_model
	visited = p_visited
	current = p_current
	var f := MapData.fog(model, visited)
	_vis = f["visible"]
	_unk = f["unknown"]
	if current != "" and (model.get("by_id", {}) as Dictionary).has(current):
		_vis[current] = true
		_unk.erase(current)
	# 只用畫得出來的房間（到過的＋相鄰的「？」）算範圍：沒去過的那幾排不留一大塊空白、
	# 也不會把下面那排擠出視窗（審查 round 3：區域圖上方一大片空白、下排房間被切掉）
	var all_pos: Dictionary = model.get("pos", {})
	var shown := {}
	for id in all_pos:
		if is_shown(id):
			shown[id] = all_pos[id]
	var b := MapLayout.bounds(shown if not shown.is_empty() else all_pos)
	_origin = b.position
	content_size = PAD * 2.0 + Vector2(b.size.x * CELL.x, b.size.y * CELL.y)
	if not follow_current:
		custom_minimum_size = content_size * zoom
	_relayout()

## 大地圖：整張區域圖放不進視窗時縮小（最小 MIN_FIT_ZOOM），不必捲動就看得到上下排（審查 round 3）
const MIN_FIT_ZOOM := 0.72

func fit_into(avail: Vector2) -> void:
	if follow_current or content_size == Vector2.ZERO or avail.x <= 0.0 or avail.y <= 0.0:
		return
	var z := clampf(minf(avail.x / content_size.x, avail.y / content_size.y), MIN_FIT_ZOOM, 1.0)
	if not is_equal_approx(z, zoom):
		zoom = z
		custom_minimum_size = content_size * zoom
		_relayout()

func _relayout() -> void:
	var pos0: Dictionary = model.get("pos", {})
	var fid := focus_id()
	if follow_current and pos0.has(fid):
		var p: Vector2i = pos0[fid] - _origin
		var cur_c := PAD + Vector2(p.x * CELL.x, p.y * CELL.y) + CELL / 2.0
		var box := Rect2(cur_c - BOX / 2.0, BOX)
		if size.x > 1.0 and size.y > 1.0:
			# 兩輪：出區箭頭的字大小跟著縮放變
			zoom = follow_zoom_max
			for _i in 2:
				box = neighbourhood_box()
				var avail := size - Vector2(FOLLOW_MARGIN, FOLLOW_MARGIN) * 2.0
				zoom = clampf(minf(follow_zoom_max, minf(avail.x / box.size.x, avail.y / box.size.y)), MIN_FOLLOW_ZOOM, follow_zoom_max)
		var view_c := size / zoom / 2.0
		var view_half := view_c - Vector2(FOLLOW_MARGIN, FOLLOW_MARGIN) / zoom
		var focus := box.get_center()
		# 放不下整圈時，至少讓目前房間整個在框內
		var lo := cur_c + BOX / 2.0 - view_half
		var hi := cur_c - BOX / 2.0 + view_half
		focus = Vector2(clampf(focus.x, minf(lo.x, hi.x), maxf(lo.x, hi.x)), clampf(focus.y, minf(lo.y, hi.y), maxf(lo.y, hi.y)))
		_offset = view_c - focus
	else:
		_offset = ((size / zoom - content_size) / 2.0).max(Vector2.ZERO)
	_segments.clear()
	_label_rects.clear()
	_rects.clear()
	var pos: Dictionary = model.get("pos", {})
	for id in pos:
		_rects[id] = Rect2(center_of(pos[id]) - BOX / 2.0, BOX)
	queue_redraw()

## 小地圖要整個看得到的範圍（未加 _offset 的內容座標）：目前房間、畫得出來的相鄰房間、這些房間（到過的）的出區箭頭與字
func neighbourhood_box() -> Rect2:
	var pos: Dictionary = model.get("pos", {})
	var cur := focus_id()
	if not pos.has(cur):
		return Rect2()
	var base := func(id: String) -> Vector2:
		var q: Vector2i = pos[id] - _origin
		return PAD + Vector2(q.x * CELL.x, q.y * CELL.y) + CELL / 2.0
	# 相鄰＝格子座標前後左右與斜角各一格（例如大理驛站斜上方的大理北門）
	var ids: Array = [cur]
	var pc: Vector2i = pos[cur]
	for id in pos:
		var d: Vector2i = (pos[id] as Vector2i) - pc
		if id != cur and is_shown(id) and absi(d.x) <= 1 and absi(d.y) <= 1:
			ids.append(id)
	var c0: Vector2 = base.call(cur)
	var r := Rect2(c0 - BOX / 2.0, BOX)
	for id in ids:
		var c: Vector2 = base.call(id)
		r = r.merge(Rect2(c - BOX / 2.0, BOX))
	var f := _font()
	for oe in model.get("out_exits", []):
		var from := str(oe.get("from", ""))
		if not ids.has(from) or not _vis.has(from):
			continue
		var v := Vector2(MapLayout.dir_vec(str(oe.get("dir", "")))).normalized()
		var c: Vector2 = base.call(from)
		var tip := c + Vector2(v.x * BOX.x / 2.0, v.y * BOX.y / 2.0) + v * ARROW_LEN
		var label := "往%s" % str(oe.get("to_region_name", ""))
		if not MapLayout.is_planar(str(oe.get("dir", ""))):
			label = "%s・%s" % [UiKeys.dir_label(str(oe.get("dir", ""))), label]
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_size() + 1) if f != null else Vector2(60, 16)
		var lat := tip + v * (10.0 + absf(v.x) * lw.x / 2.0 + absf(v.y) * lw.y / 2.0)
		r = r.merge(Rect2(tip - Vector2(7, 7), Vector2(14, 14))).merge(Rect2(lat - lw / 2.0, lw))
	return r

## 畫面中心：目前房間在本區就是它，否則 focus_room（瀏覽別區）
func focus_id() -> String:
	var pos: Dictionary = model.get("pos", {})
	if pos.has(current):
		return current
	return focus_room if pos.has(focus_room) else ""

func set_walk_target(id: String) -> void:
	walk_target = id
	queue_redraw()

func set_quest_mark(id: String) -> void:
	quest_mark = id
	queue_redraw()

func center_of(p: Vector2i) -> Vector2:
	var q := p - _origin
	return _offset + PAD + Vector2(q.x * CELL.x, q.y * CELL.y) + CELL / 2.0

## 從這些房間出發的「往XXX」出區箭頭與字框在畫面上的範圍（夜晚小地圖的亮區要包含它們；M3d 審查）。
## 夜晚的霧每一格都重畫 → 結果依（房間組、縮放、大小、目前房間）快取，setup() 時清掉（out_exit_items 要量字、排位置，不便宜）
var _oe_cache_key := ""
var _oe_cache: Array = []
func out_exit_screen_rects(from_ids: Dictionary) -> Array:
	var ids: Array = from_ids.keys()
	ids.sort()
	var key := "%s|%s|%s|%s|%s|%s" % [str(ids), str(zoom), str(size), current, focus_room, str(_offset)]
	if key == _oe_cache_key:
		return _oe_cache
	var out: Array = []
	for it in out_exit_items():
		if from_ids.has(str(it.get("from", ""))):
			var h: Rect2 = it["hit"]
			out.append(Rect2(h.position * zoom, h.size * zoom))
	_oe_cache_key = key
	_oe_cache = out
	return out

func is_shown(id: String) -> bool:
	return _vis.has(id) or _unk.has(id)

func visible_rooms() -> Dictionary:
	return _vis

func unknown_rooms() -> Dictionary:
	return _unk

## 小地圖（follow_current）：房間方框沒有整個在畫面裡（被邊緣切到）
const CLIPPED_ALPHA := 0.35
func is_clipped(id: String) -> bool:
	if not follow_current or not _rects.has(id):
		return false
	return not Rect2(Vector2.ZERO, size).grow(1.0).encloses(screen_rect(id))

## 房間方框在畫面（本控制項的區域座標）上的位置
func screen_rect(id: String) -> Rect2:
	var r: Rect2 = _rects.get(id, Rect2())
	return Rect2(r.position * zoom, r.size * zoom)

func name_size() -> int:
	if zoom >= 1.0:
		return NAME_SIZE
	# 大地圖縮小放進視窗（0.72–1）：畫到螢幕上約 13–14 px；小地圖（0.55）用 19
	return mini(19, int(ceil(NAME_SIZE * 0.9 / zoom))) if zoom >= MIN_FIT_ZOOM - 0.001 else mini(22, int(ceil(10.5 / zoom)))

## 小字（NPC／地形、出口方向、出區箭頭）：縮小時也放大，畫到螢幕上至少約 10 px（審查：0.55 倍時只剩 6 px）
func badge_size() -> int:
	return BADGE_SIZE if zoom >= 1.0 else int(ceil(10.5 / zoom))

## 房間小字：「客棧・師父・灶」放不下方框時從後面捨去、加「…」
func badge_text(badges: Array, fs: int) -> String:
	var t := "・".join(PackedStringArray(badges))
	var f := _font()
	if f == null:
		return t
	var maxw := BOX.x - 8.0
	var n := badges.size()
	while n > 1 and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw:
		n -= 1
		t = "・".join(PackedStringArray(badges.slice(0, n))) + "…"
	return t

func room_at(p: Vector2) -> String:
	p /= zoom
	for id in _rects:
		if is_shown(id) and (_rects[id] as Rect2).has_point(p):
			return id
	return ""

# ---------- 繪圖 ----------
func _font() -> Font:
	return get_theme_font("font", "Label")

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var bg_tex := MapArt.texture("region_bg")
	if bg_tex != null:
		MapArt.draw_tiled(self, bg_tex, Rect2(Vector2.ZERO, size), BG_TILE_SCALE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(zoom, zoom))
	var by_id: Dictionary = model.get("by_id", {})
	var pos: Dictionary = model.get("pos", {})
	if by_id.is_empty():
		_text_center(size / zoom / 2.0, "（沒有地圖資料）", NAME_SIZE, LINE)
		return
	if _vis.is_empty() and not pos.has(current):
		_text_center(size / zoom / 2.0, empty_text, NAME_SIZE + 2, LINE, true)
	# 連線（至少一端到過）：從框邊畫到框邊，不穿過「？」與房名
	_segments.clear()
	_label_rects.clear()
	var drawn := {}
	for id in _vis:
		if not pos.has(id):
			continue
		for ex in by_id[id].get("exits", []):
			if not (ex is Dictionary):
				continue
			var to := str(ex.get("to", ""))
			if not pos.has(to) or not is_shown(to):
				continue
			var key := "%s|%s" % ([id, to] if id < to else [to, id])
			if drawn.has(key):
				continue
			drawn[key] = true
			var dir := str(ex.get("dir", ""))
			var seg := link_segment(id, to)
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			_segments.append(seg)
			if MapLayout.is_planar(dir) and not _unk.has(to):
				draw_line(a, b, LINE, 3.0, true)
			else:
				draw_dashed_line(a, b, LINE, 2.0, 7.0)
			if not MapLayout.is_planar(dir) and label_in_view((a + b) / 2.0):
				_text_center((a + b) / 2.0, UiKeys.dir_label(dir), badge_size(), BADGE, true)
	# 離開本區的出口（「往XXX」可以點：切到那個鄰區）
	var exit_icon := MapArt.icon("exit")
	for it in out_exit_items():
		var start: Vector2 = it["start"]
		var tip: Vector2 = it["tip"]
		var v: Vector2 = it["v"]
		draw_line(start, tip, OUT_COLOR, 3.0, true)
		_segments.append([start, tip])
		var side := Vector2(-v.y, v.x) * 7.0
		draw_colored_polygon(PackedVector2Array([tip + v * 6.0, tip - v * 6.0 + side, tip - v * 6.0 - side]), OUT_COLOR)
		var lr: Rect2 = it["label_rect"]
		_label_rects.append(lr)
		if exit_icon != null:
			var isz := _icon_px()
			draw_texture_rect(exit_icon, Rect2(tip - Vector2(isz, isz) / 2.0, Vector2(isz, isz)), false)
		# 「往XXX」的字在房間方框之後才畫（M3c 審查：字被房間框蓋住）
	# 房間方框
	var fr_room := MapArt.texture("node_room")
	var fr_cur := MapArt.texture("node_current")
	var fr_fog := MapArt.texture("node_fog")
	var danger_icon := MapArt.icon("danger")
	for id in pos:
		if not is_shown(id):
			continue
		var r: Rect2 = _rects[id]
		if is_clipped(id):
			# M3c 第三輪審查：小地圖邊緣只露出一部分的房間——不寫房名（「夏衙門」「夏錢莊」會被看成別的地方），只畫淡淡的框
			draw_rect(r, Color(BOX_FILL if not _unk.has(id) else UNKNOWN_FILL, CLIPPED_ALPHA))
			draw_rect(r, Color(BOX_EDGE if not _unk.has(id) else UNKNOWN_EDGE, CLIPPED_ALPHA), false, thin_line())
			continue
		if _unk.has(id):
			if fr_fog != null:
				MapArt.draw_nine(self, fr_fog, r)
			else:
				draw_rect(r, UNKNOWN_FILL)
				draw_rect(r, UNKNOWN_EDGE, false, thin_line())
			_text_center(r.get_center(), "？", name_size() + 4, UNKNOWN_EDGE)
			continue
		var room: Dictionary = by_id[id]
		var is_cur: bool = id == current
		var frame := fr_cur if is_cur and fr_cur != null else fr_room
		if frame != null:
			MapArt.draw_nine(self, frame, r)
			if id == walk_target and not is_cur:
				draw_rect(r.grow(2.0), TARGET, false, 3.0)
		else:
			draw_rect(r, CUR_FILL if is_cur else BOX_FILL)
			var edge := DANGER if is_cur else (TARGET if id == walk_target else BOX_EDGE)
			draw_rect(r, edge, false, 3.5 if is_cur or id == walk_target else thin_line())
		var badges := MapData.room_badges(tables, room)
		var bs := badge_size()
		var icons := badge_icons(badges)
		if not icons.is_empty():
			# 有圖示：房名在上、一排 18–22px 圖示在下（字放不下的問題不存在）
			_text_center(Vector2(r.get_center().x, r.get_center().y - 9.0), str(room.get("name", id)), name_size(), UiTheme.INK)
			var isz := _icon_px()
			var gap := 2.0
			var total := icons.size() * isz + (icons.size() - 1) * gap
			var x0 := r.get_center().x - total / 2.0
			for i in icons.size():
				draw_texture_rect(icons[i], Rect2(Vector2(x0 + i * (isz + gap), r.get_center().y + 3.0), Vector2(isz, isz)), false)
		else:
			# 小地圖（縮小）：小字放不下就整行不畫（審查 round 3：「西夏客棧／客棧…」多一行被截斷、又跟房名重複）
			if zoom < 1.0 and not badges.is_empty() and badge_text(badges, bs).ends_with("…"):
				badges = []
			var name_y := r.get_center().y - ((8.0 if zoom >= 1.0 else 10.0) if not badges.is_empty() else 0.0)
			_text_center(Vector2(r.get_center().x, name_y), str(room.get("name", id)), name_size(), UiTheme.INK)
			if not badges.is_empty():
				_text_center(Vector2(r.get_center().x, r.get_center().y + (13.0 if zoom >= 1.0 else 14.0)), badge_text(badges, bs), bs, BADGE)
		if MapData.encounter_rate(room) > 0.0:
			# 右上角小紅點＝會遇敵（有圖示時畫圖示）
			if danger_icon != null:
				var dsz := _icon_px() * 0.8
				draw_texture_rect(danger_icon, Rect2(r.position + Vector2(r.size.x - dsz - 2.0, 2.0), Vector2(dsz, dsz)), false)
			else:
				draw_circle(r.position + Vector2(r.size.x - 8.0, 8.0), 4.5, DANGER)
	# 趕路路線（M3c 審查：地圖上看不出要走哪條路）：剩下的路在本區的那幾段畫藍色粗虛線、目的地加「目的地」字
	_draw_walk_path()
	# 「往XXX」的字：畫在房間方框之上（M3c 審查），位置已夾在畫面內（out_exit_items）
	var walk_exits := _walk_exit_regions()
	for it in out_exit_items():
		var lr2: Rect2 = it["label_rect"]
		var col: Color = WALK_PATH if walk_exits.has(str(it["to_region"])) else OUT_COLOR
		_text_center(lr2.get_center(), str(it["label"]), badge_size() + 1, col, true)
		# 可點的提示：字底下一條細線
		draw_line(Vector2(lr2.position.x + 3.0, lr2.end.y), Vector2(lr2.end.x - 3.0, lr2.end.y), Color(col, 0.6), 1.0 / zoom)
	# 任務提示地點：畫得出來（到過或相鄰的「？」）才標
	if quest_mark != "" and _rects.has(quest_mark) and is_shown(quest_mark):
		var qr: Rect2 = (_rects[quest_mark] as Rect2).grow(5.0)
		draw_dashed_line(qr.position, Vector2(qr.end.x, qr.position.y), QUEST_MARK, 2.5, 6.0)
		draw_dashed_line(Vector2(qr.end.x, qr.position.y), qr.end, QUEST_MARK, 2.5, 6.0)
		draw_dashed_line(qr.end, Vector2(qr.position.x, qr.end.y), QUEST_MARK, 2.5, 6.0)
		draw_dashed_line(Vector2(qr.position.x, qr.end.y), qr.position, QUEST_MARK, 2.5, 6.0)
		var qicon := MapArt.icon("quest")
		var qc := Vector2(qr.get_center().x, qr.position.y - badge_size())
		if qicon != null:
			var qs := _icon_px()
			draw_texture_rect(qicon, Rect2(qc - Vector2(qs, qs) / 2.0, Vector2(qs, qs)), false)
		else:
			_text_center(qc, QUEST_MARK_TEXT, badge_size() + 1, QUEST_MARK, true)
	# 小地圖跟著玩家置中、目前房間有朱紅粗框：不另外寫「你在這裡」（縮小後只剩 6 px，看不清又壓到連線）
	var marker := MapArt.texture("marker_here")
	if marker != null and _rects.has(current) and is_shown(current):
		# 有「你在這裡」圖：畫在房間框上方（小地圖也畫，圖比字好認）
		var cr: Rect2 = _rects[current]
		var ms := (18.0 / zoom) if zoom < 1.0 else 22.0   # 畫到螢幕上約 18–22 px
		draw_texture_rect(marker, Rect2(Vector2(cr.get_center().x - ms / 2.0, cr.position.y - ms - 1.0), Vector2(ms, ms)), false)
	else:
		var here := here_label() if zoom >= MIN_FIT_ZOOM - 0.001 else {}
		if not here.is_empty():
			_text_center((here["rect"] as Rect2).get_center(), str(here["text"]), badge_size(), DANGER, true)

## 小字 → 圖示（只有每一個小字都有圖時才換成圖示，否則整行照舊寫字）
func badge_icons(badges: Array) -> Array:
	if badges.is_empty():
		return []
	var out: Array = []
	for b in badges:
		var key := str(MapArt.BADGE_ICONS.get(str(b), ""))
		var t := MapArt.icon(key) if key != "" else null
		if t == null:
			return []
		out.append(t)
	# 方框放得下的數量
	var isz := _icon_px()
	var fit := int((BOX.x - 8.0 + 2.0) / (isz + 2.0))
	return out.slice(0, maxi(1, fit))

## 圖示大小（內容座標）：畫到螢幕上 18–22 px
func _icon_px() -> float:
	return clampf(20.0 / zoom, 18.0, 36.0) if zoom < 1.0 else 20.0

## 出區箭頭（只畫到過的房間的）：[{ from, to, to_region, label, v, start, tip, label_rect, hit }]，內容座標（含 _offset）。
## hit＝箭頭＋字的可點範圍（region_at 用）
func out_exit_items() -> Array:
	var out: Array = []
	var placed: Array = []   # 已經放好的「往XXX」字框（後面的不疊上去）
	var pos: Dictionary = model.get("pos", {})
	var f := _font()
	for oe in model.get("out_exits", []):
		var from := str(oe.get("from", ""))
		if not _vis.has(from) or not pos.has(from):
			continue
		var v := Vector2(MapLayout.dir_vec(str(oe.get("dir", "")))).normalized()
		var c := center_of(pos[from])
		var start := c + Vector2(v.x * BOX.x / 2.0, v.y * BOX.y / 2.0)
		var tip := start + v * ARROW_LEN
		var label := "往%s" % str(oe.get("to_region_name", ""))
		if not MapLayout.is_planar(str(oe.get("dir", ""))):
			label = "%s・%s" % [UiKeys.dir_label(str(oe.get("dir", ""))), label]
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_size() + 1) if f != null else Vector2(60, 16)
		var lr := place_exit_label(tip, v, lw, placed)
		placed.append(lr)
		var hit := lr.grow(4.0).merge(Rect2(tip - Vector2(10, 10), Vector2(20, 20))).merge(Rect2(start.min(tip) - Vector2(6, 6), (start - tip).abs() + Vector2(12, 12)))
		out.append({ "from": from, "to": str(oe.get("to", "")), "to_region": str(oe.get("to_region", "")),
			"label": label, "v": v, "start": start, "tip": tip, "label_rect": lr, "hit": hit })
	return out

## M3c 第二輪審查（小地圖「往西夏東郊」蓋住胡楊林的房名）：字框放在箭頭尖端附近**沒有房間方框、也沒有別的「往XXX」**的地方。
## 依序試：箭頭方向往外（原本的位置）→ 尖端左、右 → 尖端上、下 → 箭頭兩側；都會壓到時取壓到面積最小的。每個都先夾在畫面內
func place_exit_label(tip: Vector2, v: Vector2, lw: Vector2, placed: Array = []) -> Rect2:
	var gap := 6.0
	var cands: Array = [
		tip + v * (10.0 + absf(v.x) * lw.x / 2.0 + absf(v.y) * lw.y / 2.0),
		tip + Vector2(-(lw.x / 2.0 + gap), 0), tip + Vector2(lw.x / 2.0 + gap, 0),
		tip + Vector2(0, -(lw.y / 2.0 + gap)), tip + Vector2(0, lw.y / 2.0 + gap),
		tip + Vector2(-(lw.x / 2.0 + gap), -(lw.y / 2.0 + gap)), tip + Vector2(lw.x / 2.0 + gap, -(lw.y / 2.0 + gap)),
		tip + Vector2(-(lw.x / 2.0 + gap), lw.y / 2.0 + gap), tip + Vector2(lw.x / 2.0 + gap, lw.y / 2.0 + gap),
	]
	var best := Rect2()
	var best_cost := INF
	for c in cands:
		var r := clamp_label(Rect2((c as Vector2) - lw / 2.0, lw))
		var cost := _label_overlap(r, placed)
		if cost <= 0.0:
			return r
		if cost < best_cost:
			best_cost = cost
			best = r
	return best

## 字框壓到房間方框（畫得出來的）與已放好字框的面積
func _label_overlap(r: Rect2, placed: Array) -> float:
	var a := 0.0
	for id in _rects:
		if is_shown(str(id)):
			var b: Rect2 = (_rects[id] as Rect2).grow(2.0)
			if b.intersects(r):
				a += b.intersection(r).get_area()
	for q in placed:
		if (q as Rect2).intersects(r):
			a += (q as Rect2).intersection(r).get_area()
	return a

## M3c 審查（小地圖切掉「往西夏郊」）：「往XXX」的字框夾在看得到的範圍內（內容座標；邊上留一點空）。
## 箭頭本身照畫（可以出框），字一定看得到、點得到
func clamp_label(lr: Rect2) -> Rect2:
	if size.x <= 1.0 or size.y <= 1.0 or zoom <= 0.0:
		return lr
	var vis := Rect2(Vector2.ZERO, size / zoom).grow(-LABEL_MARGIN / zoom)
	if vis.size.x < lr.size.x or vis.size.y < lr.size.y:
		return lr
	var p := lr.position.clamp(vis.position, vis.end - lr.size)
	return Rect2(p, lr.size)

const LABEL_MARGIN := 4.0   # 畫面 px

## ---------------------------------------------------------------- 趕路路線（M3c 審查）
## walk_path = 剩下的路（[目前房間, …, 目的地]，可以跨區）；本區裡相鄰兩間都在的那幾段才畫
var walk_path: Array = []
const WALK_PATH := Color("1f5fa8")
const DEST_TEXT := "目的地"

func set_walk_path(path: Array) -> void:
	walk_path = path.duplicate()
	queue_redraw()

## 路線接下來會走出本區的「往XXX」（那幾個出口的字改用路線色）
func _walk_exit_regions() -> Dictionary:
	var out := {}
	var pos: Dictionary = model.get("pos", {})
	for i in walk_path.size() - 1:
		var a := str(walk_path[i])
		var b := str(walk_path[i + 1])
		if pos.has(a) and not pos.has(b):
			for oe in model.get("out_exits", []):
				if str(oe.get("from", "")) == a and str(oe.get("to", "")) == b:
					out[str(oe.get("to_region", ""))] = true
	return out

func _draw_walk_path() -> void:
	if walk_path.size() < 2:
		return
	var pos: Dictionary = model.get("pos", {})
	for i in walk_path.size() - 1:
		var a := str(walk_path[i])
		var b := str(walk_path[i + 1])
		if pos.has(a) and pos.has(b) and is_shown(a) and is_shown(b):
			var seg := link_segment(a, b)
			draw_dashed_line(seg[0], seg[1], WALK_PATH, 5.0, 9.0)
		elif pos.has(a) and not pos.has(b):
			# 走出本區：從房間框邊畫到那個出口箭頭的尖端
			for it in out_exit_items():
				if str(it["from"]) == a and str(it["to"]) == b:
					draw_dashed_line(it["start"], it["tip"], WALK_PATH, 5.0, 9.0)
	var dest := str(walk_path[walk_path.size() - 1])
	if _rects.has(dest) and is_shown(dest) and dest != current:
		var r: Rect2 = (_rects[dest] as Rect2).grow(4.0)
		draw_rect(r, WALK_PATH, false, 3.0)
		_text_center(Vector2(r.get_center().x, r.position.y - badge_size()), DEST_TEXT, badge_size() + 1, WALK_PATH, true)

## 畫面座標 p 上的「往XXX」→ 那個地區的 id；沒有回 ""
func region_at(p: Vector2) -> String:
	var q := p / zoom
	for it in out_exit_items():
		if (it["hit"] as Rect2).has_point(q):
			return str(it["to_region"])
	return ""

## 方框細邊：縮小時至少 1.2 個螢幕 px（審查 round 4：0.55 倍時 1.5 px 的橫邊只剩 0.8 px、整條消失，看起來像房間被框切掉）
func thin_line() -> float:
	return maxf(1.5, 1.2 / zoom)

## 小地圖：連線中點的「上／下／入」字不在框內就不畫（連到框外的房間時，半個字貼在上緣標題列下面）
func label_in_view(content_p: Vector2) -> bool:
	if not follow_current:
		return true
	return Rect2(Vector2.ZERO, size).grow(-10.0).has_point(content_p * zoom)

## 兩間房之間的連線：從 a 的框邊到 b 的框邊
func link_segment(a: String, b: String) -> Array:
	var pos: Dictionary = model.get("pos", {})
	var ca := center_of(pos[a])
	var cb := center_of(pos[b])
	var d := cb - ca
	if d.length_squared() < 1.0:
		return [ca, cb]
	return [MapLayout.box_edge_point(ca, BOX / 2.0, d.normalized()), MapLayout.box_edge_point(cb, BOX / 2.0, -d.normalized())]

## 「你在這裡」：框上方置中、下方置中、上方偏左／偏右、下方偏左／偏右，挑第一個不壓到連線、箭頭、其他房間的
func here_label() -> Dictionary:
	if not _rects.has(current) or not is_shown(current):
		return {}
	var r: Rect2 = _rects[current]
	var w := Vector2(_text_w(HERE_ABOVE, badge_size()) + 6.0, badge_size() + 4.0)
	var cx := r.get_center().x
	var above := r.position.y - 2.0 - w.y
	var below := r.end.y + 2.0
	var cands := [
		[Rect2(Vector2(cx - w.x / 2.0, above), w), HERE_ABOVE],
		[Rect2(Vector2(cx - w.x / 2.0, below), w), HERE_BELOW],
		[Rect2(Vector2(cx - w.x - 5.0, above), w), HERE_ABOVE],
		[Rect2(Vector2(cx + 5.0, above), w), HERE_ABOVE],
		[Rect2(Vector2(cx - w.x - 5.0, below), w), HERE_BELOW],
		[Rect2(Vector2(cx + 5.0, below), w), HERE_BELOW],
	]
	var obstacles: Array = _label_rects.duplicate()
	for id in _rects:
		if id != current and is_shown(id):
			obstacles.append(_rects[id])
	var rects: Array = []
	for c in cands:
		rects.append(c[0])
	var i := MapLayout.pick_free_rect(rects, segments(), obstacles)
	return { "rect": cands[i][0], "text": cands[i][1] }

## 目前畫面上的連線與出口箭頭（_draw 之前呼叫時現算）
func segments() -> Array:
	if _segments.is_empty():
		var out: Array = []
		var pos: Dictionary = model.get("pos", {})
		var by_id: Dictionary = model.get("by_id", {})
		for id in _vis:
			if not pos.has(id):
				continue
			for ex in by_id.get(id, {}).get("exits", []):
				if ex is Dictionary and pos.has(str(ex.get("to", ""))) and is_shown(str(ex.get("to", ""))):
					out.append(link_segment(id, str(ex.get("to", ""))))
		return out
	return _segments

func _text_w(text: String, fsize: int) -> float:
	var font := _font()
	return 70.0 if font == null else font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x

func _text_center(at: Vector2, text: String, fsize: int, color: Color, backdrop := false) -> void:
	var font := _font()
	if font == null:
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var top_left := at - Vector2(w.x / 2.0, w.y / 2.0)
	if backdrop:
		draw_rect(Rect2(top_left - Vector2(3, 1), w + Vector2(6, 2)), Color(BG, 0.85))
	draw_string(font, top_left + Vector2(0, font.get_ascent(fsize)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)

# ---------- 互動 ----------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var rid := region_at(event.position)
		var room := room_at(event.position)
		if rid != "" and room == "":
			region_clicked.emit(rid)
		else:
			room_clicked.emit(room)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		context_requested.emit(event.position)
		accept_event()

func _get_tooltip(at_position: Vector2) -> String:
	var room := room_at(at_position)
	if room == "":
		var rid := region_at(at_position)
		if rid != "":
			return "%s\n點擊切換到這一區的地圖" % MapData.region_name(tables, rid)
	return tooltip_for(room)

func tooltip_for(id: String) -> String:
	if id == "":
		return ""
	if _unk.has(id):
		return "還沒去過的地方。"
	var room: Dictionary = model.get("by_id", {}).get(id, {})
	if room.is_empty():
		return ""
	var lines: PackedStringArray = [str(room.get("name", id))]
	var npcs := MapData.room_npc_names(tables, room)
	if not npcs.is_empty():
		lines.append("人物：%s" % "、".join(npcs))
	var danger := MapData.room_danger(tables, room)
	if not danger.is_empty():
		lines.append("危險：%s" % "、".join(danger))
	else:
		lines.append("無遇敵")   # M3c 審查：不寫「安全」（城裡沒有遇敵，但照樣能動手、會有官兵）
	if not (room.get("requires", []) as Array).is_empty():
		lines.append("（需符合條件才能進入）")
	if id == current:
		lines.append("你在這裡")
	else:
		lines.append("點擊前往")
	return "\n".join(lines)
