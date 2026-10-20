extends UiScreen
## 創角（M1_PLAN 3.12、GDD 2.1）：名稱、性別、生日月份、出生城；「擲骰」→ char_roll，
## 從 char_rolled 事件顯示 7 項；5 點分配（+／−，總和必須 5 才能送出）；「建立」→ char_create。
## M3c（M3C_PLAN §3.4 第 2 點）：右半邊是大型造型選擇器（LookPicker，依性別 9 種；性別切換時重設為 0 號布衣），
## 送出時帶 look。出生地羊皮紙地圖（AUTHENTIC_UI_SPEC §8.11）移到同一區的第二個分頁「出生地圖」（與出生城市下拉同步）。

var name_edit: LineEdit
var gender_opt: OptionButton
var month_opt: OptionButton
var city_opt: OptionButton
var btn_roll: Button
var btn_create: Button
var btn_back: Button
var remain_label: Label
var total_label: Label
var status_label: Label
var _attr_rows: Dictionary = {}     # attr -> { roll: Label, alloc: Label, final: Label, plus: Button, minus: Button }
var _cities: Array = []
var birth_map: BirthMap
var picker: LookPicker
var look_label: Label
var tab_looks: Button
var tab_map: Button

var rolled: Dictionary = {}         # attr -> int（char_rolled 的值）
var alloc: Dictionary = {}          # attr -> int（0..5）
var _awaiting_enter := false

func _ready() -> void:
	_build()
	for a in UiKeys.ATTR_IDS:
		alloc[a] = 0
	UiClient.connect_signal("events_received", _on_events)
	UiClient.connect_signal("sheet_changed", _on_sheet)
	refresh()

func _exit_tree() -> void:
	super._exit_tree()
	UiClient.disconnect_signal("events_received", _on_events)
	UiClient.disconnect_signal("sheet_changed", _on_sheet)

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	# AUTHENTIC_UI_SPEC §8.11、§14：玉石框；右側羊皮紙「請選擇出生地」地圖（城市朱印可點，與出生城市下拉同步）
	var frame := UiBuild.framed(center, UiFrame.Kind.JADE)
	var two := UiBuild.hbox(frame, 16)
	var col := UiBuild.vbox(two, 6)
	col.custom_minimum_size = Vector2(540, 0)
	UiBuild.title(col, "建立角色")

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	UiBuild.label(grid, "名稱")
	name_edit = UiBuild.line_edit(grid, "", "1–8 字，不含空白與括號", UiKeys.NAME_MAX_LEN)
	name_edit.text_changed.connect(func(_t): refresh())
	UiBuild.label(grid, "性別")
	gender_opt = OptionButton.new()
	gender_opt.add_item("男", 0)
	gender_opt.add_item("女", 1)
	grid.add_child(gender_opt)
	gender_opt.item_selected.connect(func(_i: int): _on_gender_changed())
	UiBuild.label(grid, "生日月份")
	month_opt = OptionButton.new()
	for m in range(1, 13):
		month_opt.add_item("%d 月" % m, m)
	grid.add_child(month_opt)
	UiBuild.label(grid, "出生城市")
	city_opt = OptionButton.new()
	_cities = UiClient.birth_cities()
	for i in _cities.size():
		city_opt.add_item(str(_cities[i]["name"]), i)
	grid.add_child(city_opt)
	birth_map = BirthMap.new()
	birth_map.cities = _cities
	birth_map.city_picked.connect(func(i: int):
		city_opt.select(i)
		birth_map.selected = i
		birth_map.queue_redraw())
	city_opt.item_selected.connect(func(i: int):
		birth_map.selected = i
		birth_map.queue_redraw())
	# 右半邊：分頁「外觀造型」（預設）／「出生地圖」
	var right := UiBuild.vbox(two, 6)
	var tabs := UiBuild.hbox(right, 8)
	var group := ButtonGroup.new()
	tab_looks = UiBuild.button(tabs, "外觀造型", func(): show_tab("looks"), 110)
	tab_map = UiBuild.button(tabs, "出生地圖", func(): show_tab("map"), 110)
	for b in [tab_looks, tab_map]:
		b.toggle_mode = true
		b.button_group = group
	look_label = UiBuild.label(tabs, "", 16)
	UiBuild.accent(look_label)
	look_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	look_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	picker = LookPicker.new()
	picker.set_cell_size(Vector2(200, 188))
	picker.look_selected.connect(func(_i: int): _sync_look())
	right.add_child(picker)
	# 兩個分頁同一個大小（切到出生地圖時視窗不縮）；地圖保持直式卷軸，置中
	right.custom_minimum_size = picker.custom_minimum_size + Vector2(0, tabs.get_combined_minimum_size().y + 6)
	birth_map.custom_minimum_size = Vector2(340, 360)
	birth_map.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	birth_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(birth_map)
	show_tab("looks")
	_sync_look()


	col.add_child(HSeparator.new())
	var head := UiBuild.hbox(col, 10)
	btn_roll = UiBuild.button(head, "擲骰", _on_roll, 100)
	UiBuild.muted(UiBuild.label(head, "每項 13–25，可無限重擲；另有 5 點自由分配（可超過 25）。臂力影響攻擊，新手建議加在臂力。", 15, true)).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var ag := GridContainer.new()
	ag.columns = 6
	ag.add_theme_constant_override("h_separation", 14)
	col.add_child(ag)
	for h in ["屬性", "擲骰", "", "分配", "", "合計"]:
		UiBuild.muted(UiBuild.label(ag, h, 15))
	for a in UiKeys.ATTR_IDS:
		var r := {}
		UiBuild.label(ag, UiClient.attr_name(a))
		r["roll"] = UiBuild.label(ag, "—")
		r["minus"] = UiBuild.button(ag, "−", _on_alloc.bind(a, -1), 36)
		r["alloc"] = UiBuild.label(ag, "0")
		r["plus"] = UiBuild.button(ag, "+", _on_alloc.bind(a, 1), 36)
		r["final"] = UiBuild.label(ag, "—")
		_attr_rows[a] = r
	var sumrow := UiBuild.hbox(col, 20)
	remain_label = UiBuild.label(sumrow, "")
	total_label = UiBuild.label(sumrow, "")

	col.add_child(HSeparator.new())
	var row := UiBuild.hbox(col, 10)
	btn_create = UiBuild.button(row, "建立", _on_create, 120)
	btn_back = UiBuild.button(row, "返回", func(): go("char_select"), 100)
	status_label = UiBuild.label(col, "", 16, true)
	status_label.add_theme_color_override("font_color", UiTheme.JY_ERROR_LIGHT)

func remaining() -> int:
	var s := 0
	for a in alloc:
		s += int(alloc[a])
	return UiKeys.FREE_POINTS - s

func can_create() -> bool:
	return not rolled.is_empty() and remaining() == 0 and name_edit.text.strip_edges() != "" and not _cities.is_empty()

func refresh() -> void:
	var rem := remaining()
	var total := 0
	for a in UiKeys.ATTR_IDS:
		var r: Dictionary = _attr_rows[a]
		var base := int(rolled.get(a, 0))
		(r["roll"] as Label).text = str(base) if not rolled.is_empty() else "—"
		(r["alloc"] as Label).text = str(alloc[a])
		(r["final"] as Label).text = str(base + int(alloc[a])) if not rolled.is_empty() else "—"
		(r["minus"] as Button).disabled = int(alloc[a]) <= 0
		(r["plus"] as Button).disabled = rem <= 0
		total += base + int(alloc[a])
	remain_label.text = "剩餘點數：%d" % rem
	total_label.text = "合計：%d" % total if not rolled.is_empty() else "尚未擲骰"
	btn_create.disabled = not can_create()

func _on_alloc(attr: String, delta: int) -> void:
	var v := int(alloc[attr]) + delta
	if v < 0 or (delta > 0 and remaining() <= 0):
		return
	alloc[attr] = v
	refresh()

func _on_roll() -> void:
	send(UiKeys.I_CHAR_ROLL, {}, [btn_roll], func(ok: bool, reason: String):
		if not ok:
			status_label.text = UiClient.reason_inline(reason))

## char_rolled 的 payload：str, guts, wit, luck, cal, agi, con, total
func apply_roll(p: Dictionary) -> void:
	rolled = {}
	for a in UiKeys.ATTR_IDS:
		rolled[a] = UiBuild.num(p.get(a, 0))
	status_label.text = ""
	refresh()

func build_args() -> Dictionary:
	var a := {}
	for k in alloc:
		if int(alloc[k]) > 0:
			a[k] = int(alloc[k])
	var city := str(_cities[city_opt.selected]["id"]) if not _cities.is_empty() and city_opt.selected >= 0 else ""
	return {
		"name": name_edit.text.strip_edges(),
		"gender": "M" if gender_opt.selected == 0 else "F",
		"birth_month": month_opt.get_selected_id() if month_opt.selected >= 0 else 1,
		"birth_city": city,
		"alloc": a,
		"look": picker.selected,   # M3c：初始造型 0–8
	}

## 右半邊分頁："looks"（造型選擇器）／"map"（出生地圖）
func show_tab(which: String) -> void:
	var looks := which != "map"
	picker.visible = looks
	birth_map.visible = not looks
	look_label.visible = looks
	tab_looks.set_pressed_no_signal(looks)
	tab_map.set_pressed_no_signal(not looks)
	if not looks:
		birth_map.queue_redraw()

func gender() -> String:
	return "M" if gender_opt.selected <= 0 else "F"

## 性別切換：選項換成該性別的 9 種，選擇重設為 0 號（布衣）
func _on_gender_changed() -> void:
	picker.set_gender(gender())
	picker.set_selected(0)
	_sync_look()

func _sync_look() -> void:
	look_label.text = "造型：%s" % Looks.name_of(gender(), picker.selected)

func _on_create() -> void:
	if not can_create():
		return
	_awaiting_enter = true
	status_label.text = "建立中……"
	send(UiKeys.I_CHAR_CREATE, build_args(), [btn_create], func(ok: bool, reason: String):
		if not ok:
			_awaiting_enter = false
			status_label.text = UiClient.reason_inline(reason)
			refresh())

func _on_events(batch: Array) -> void:
	for e in batch:
		if e is Dictionary and e.get("key", "") == UiKeys.E_CHAR_ROLLED:
			apply_roll(e.get("p", {}))

func _on_sheet(sheet: Dictionary) -> void:
	if _awaiting_enter and str(sheet.get("char_id", "")) != "":
		go("main")

## 選擇出生地（AUTHENTIC_UI_SPEC §8.11）：羊皮紙地圖，標題「請選擇出生地」黑色毛筆大字；
## 可出生的城市（regions.birth_allowed）依 regions.world_pos 畫成朱紅印章，點一下選取。不寫死任何地區 id。
## 座標照整張江湖的範圍換算（所有地區的 world_pos），不是只拿兩座城撐滿：審查發現西夏被畫到右上角，
## 看起來在大理東北；原作西夏 (7296,2966)、大理 (5903,18617) 都在西邊，西夏只比大理偏東一點。
## 其他地區畫成淡淡的墨點與步行道路（門派、洞窟寫小字），讓羊皮紙看得出地理。
class BirthMap extends Control:
	signal city_picked(index: int)
	const SEAL := Vector2(56, 30)
	const ROAD := Color(0.35, 0.27, 0.19, 0.35)
	const FAINT := Color(0.35, 0.27, 0.19, 0.55)
	const LABEL_FS := 14
	const LABEL_INK := Color(0.27, 0.19, 0.12, 0.95)

	## 矩形有沒有壓到道路線（沿線取樣）
	func _hits_road(r: Rect2) -> bool:
		for sg in _roads:
			var a: Vector2 = sg[0]
			var b: Vector2 = sg[1]
			var n := maxi(2, int(a.distance_to(b) / 3.0))
			for k in n + 1:
				if r.has_point(a.lerp(b, float(k) / float(n))):
					return true
		return false
	var cities: Array = []
	var selected := 0
	var _rects: Array = []
	var _dots: Dictionary = {}     # region id -> Vector2（其他地區）
	var _names: Dictionary = {}    # region id -> 小字（門派、洞窟）
	var _roads: Array = []         # [Vector2, Vector2]

	func _init() -> void:
		custom_minimum_size = Vector2(260, 360)
		mouse_filter = Control.MOUSE_FILTER_STOP

	## 地圖座標 → 畫面：x、y 分開縮放（直式卷軸，y 最多比 x 多拉長 2 倍）
	func _layout() -> void:
		_rects.clear()
		_dots.clear()
		_names.clear()
		_roads.clear()
		var regions: Dictionary = UiClient.table("regions")
		var pos := {}
		for rid in regions:
			var wp: Variant = (regions[rid] as Dictionary).get("world_pos", null) if regions[rid] is Dictionary else null
			if wp is Array and (wp as Array).size() >= 2:
				pos[str(rid)] = Vector2(float(wp[0]), float(wp[1]))
		var pts: Array = []
		for c in cities:
			pts.append(pos.get(str(c.get("id", "")), Vector2(-1, -1)))
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in pos.values() + pts:
			if p.x < 0.0:
				continue
			lo = lo.min(p)
			hi = hi.max(p)
		if lo.x == INF:
			lo = Vector2.ZERO
			hi = Vector2(1000, 800)
		var area := Rect2(Vector2(14 + SEAL.x / 2.0, 72 + SEAL.y / 2.0), size - Vector2(28 + SEAL.x, 96 + SEAL.y))
		var span := (hi - lo).max(Vector2.ONE)
		var sx := area.size.x / span.x
		var sy := minf(area.size.y / span.y, sx * 2.0)
		var used := Vector2(span.x * sx, span.y * sy)
		var off := area.position + (area.size - used) / 2.0
		var to_screen := func(p: Vector2) -> Vector2:
			return off + Vector2((p.x - lo.x) * sx, (p.y - lo.y) * sy)
		for i in pts.size():
			var c: Vector2 = to_screen.call(pts[i]) if pts[i].x >= 0.0 else area.get_center() + Vector2(0, (float(i) - 0.5) * 80.0)
			_rects.append(Rect2(c - SEAL / 2.0, SEAL))
		var birth := {}
		for c in cities:
			birth[str(c.get("id", ""))] = true
		for rid in pos:
			if birth.has(rid):
				continue
			_dots[rid] = to_screen.call(pos[rid])
			var t := str((regions[rid] as Dictionary).get("type", ""))
			if t in ["SECT", "DUNGEON"]:
				_names[rid] = str((regions[rid] as Dictionary).get("name", rid))
		var tables := UiClient.tables()
		if not tables.is_empty():
			for pair in MapData.world_model(tables).get("walk", []):
				if pos.has(pair[0]) and pos.has(pair[1]):
					_roads.append([to_screen.call(pos[pair[0]]), to_screen.call(pos[pair[1]])])

	func _gui_input(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_layout()
			for i in _rects.size():
				if (_rects[i] as Rect2).grow(6).has_point(mb.position):
					city_picked.emit(i)
					accept_event()
					return

	func _draw() -> void:
		_layout()
		draw_style_box(UiFrame.style(UiFrame.Kind.SCROLL), Rect2(Vector2.ZERO, size))
		var font := UiTheme.brush_font(0.5)
		var t := "請選擇出生地"
		var fs := 24
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - w) / 2.0, 48), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.INK)
		# 淡淡的步行道路與其他地區（門派、洞窟寫小字）
		for sg in _roads:
			draw_line(sg[0], sg[1], ROAD, 1.5, true)
		var small := UiTheme.find_font()
		if small == null:
			small = ThemeDB.fallback_font
		# 門派／洞窟名：14 px 深墨色加羊皮紙色描邊（審查 round 3：原本 11 px 淡字、還壓在道路線上）；
		# 依序試 右、左、上、下，挑不壓到城市印章、不出框、不壓到道路的位置
		var placed: Array = []
		for rid in _dots:
			draw_circle(_dots[rid], 2.5, FAINT)
		for rid in _dots:
			if not _names.has(rid):
				continue
			var nw := small.get_string_size(_names[rid], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS).x
			var d: Vector2 = _dots[rid]
			var best := Rect2()
			for off in [Vector2(6, -LABEL_FS * 0.6), Vector2(-6 - nw, -LABEL_FS * 0.6), Vector2(-nw / 2.0, -LABEL_FS - 7), Vector2(-nw / 2.0, 6)]:
				var nr := Rect2(d + off, Vector2(nw, LABEL_FS * 1.2))
				if not Rect2(Vector2(8, 60), size - Vector2(16, 70)).encloses(nr):
					continue
				if _rects.any(func(sr): return (sr as Rect2).grow(4).intersects(nr)) or placed.any(func(pr): return (pr as Rect2).intersects(nr)):
					continue
				if best.size == Vector2.ZERO:
					best = nr
				if not _hits_road(nr.grow(1)):
					best = nr
					break
			if best.size == Vector2.ZERO:
				continue
			placed.append(best)
			var at := Vector2(best.position.x, best.position.y + LABEL_FS * 0.95)
			draw_string_outline(small, at, _names[rid], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS, 4, Color(0.93, 0.88, 0.76, 0.95))
			draw_string(small, at, _names[rid], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS, LABEL_INK)
		# 指北
		var nc := Vector2(size.x - 26.0, 78.0)
		draw_line(nc + Vector2(0, 10), nc + Vector2(0, -8), FAINT, 1.5, true)
		draw_colored_polygon(PackedVector2Array([nc + Vector2(0, -13), nc + Vector2(-4, -5), nc + Vector2(4, -5)]), UiTheme.CINNABAR)
		draw_string(small, nc + Vector2(-6, 24), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FAINT)
		for i in _rects.size():
			var r: Rect2 = _rects[i]
			var sel := i == selected
			draw_rect(r, UiTheme.CINNABAR if sel else Color("c8705a"))
			draw_rect(r, Color("5a1a10"), false, 2.0 if sel else 1.0)
			var nm := str(cities[i].get("seal", cities[i].get("name", "")))   # 印章只寫城名（下拉選單寫「京城（神鵰大俠）」）
			var fs2 := 18
			var w2 := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			draw_string(font, Vector2(r.get_center().x - w2 / 2.0, r.get_center().y + fs2 * 0.36), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, UiTheme.JY_PARCHMENT)
