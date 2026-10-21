extends "res://tests/test_case.gd"
## 大地圖面板與點擊趕路（ui/game/map）：AutoWalker 一步一步送 move、等房間視圖、遇到失敗／戰鬥／取消就停；
## MapPanel 迷霧與點擊尋路；主畫面「地圖」按鈕與 M 鍵。

var loader: DataLoader
var view: Dictionary
var _nodes: Array = []
var sent: Array = []      # [[seq, kind, args]]
var _seq := 100
var _dir := ""

func before_each() -> void:
	# 這個檔案量的是程式繪圖的地圖版面：強制不用地圖美術（ART_REQUEST §10 的圖已經匯入，見 test_ui_m3c_nav 的美術版測試）
	MapArt.use_textures({})
	if loader == null:
		loader = DataLoader.new()
		loader.load_all("res://data")
		view = loader.activate(["1.0A"])
	sent.clear()
	_dir = temp_dir("mappanel")

func after_each() -> void:
	MapArt.use_textures(null)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame
	remove_dir_recursive(_dir)

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _sender(kind: String, args: Dictionary) -> int:
	_seq += 1
	sent.append([_seq, kind, args])
	return _seq

func _make_walker() -> AutoWalker:
	var gate := _add(IntentGate.new()) as IntentGate
	gate.set_sender(_sender)
	var w := AutoWalker.new()
	w.gate = gate
	w.step_delay_s = 0.0
	_add(w)
	return w

func _room_view(room: String) -> Dictionary:
	var idx := MapData.room_index(view)
	var region: String = idx[room]["region"]
	return { "room": room, "room_name": str(idx[room]["room"]["name"]), "region": region,
		"region_name": MapData.region_name(view, region), "exits": [], "npcs": [] }

func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame

# ---------------------------------------------------------------- AutoWalker

func test_walker_walks_step_by_step() -> void:
	var w := _make_walker()
	var path := [{ "dir": "W", "to": "xx_street" }, { "dir": "W", "to": "xx_wuguan" }]
	var texts: Array = []
	w.state_changed.connect(func(walking: bool, t: String): texts.append([walking, t]))
	w.start(path, "xx_square")
	assert_true(w.is_walking())
	assert_eq(sent.size(), 1, "one move at a time")
	assert_eq(sent[0][1], UiKeys.I_MOVE)
	assert_eq(sent[0][2], { "dir": "W" })
	assert_eq(texts[0][0], true)
	assert_true(str(texts[0][1]).begins_with("趕路中：往"), str(texts[0][1]))
	assert_true(str(texts[0][1]).contains("剩2步"), str(texts[0][1]))
	# 主機回 ok 但房間視圖還沒到：不能送下一步
	w.gate.resolve(sent[0][0], true, "")
	await _frames(2)
	assert_eq(sent.size(), 1, "waits for room view")
	w.on_view(_room_view("xx_street"))
	await _frames(2)
	assert_eq(sent.size(), 2, "second step after view")
	w.gate.resolve(sent[1][0], true, "")
	w.on_view(_room_view("xx_wuguan"))
	assert_false(w.is_walking(), "arrived")
	assert_eq(texts[texts.size() - 1], [false, "已抵達。"])

func test_walker_stops_on_failure() -> void:
	var w := _make_walker()
	w.start([{ "dir": "N", "to": "hs_hall" }, { "dir": "N", "to": "x" }], "hs_square")
	w.gate.resolve(sent[0][0], false, "room_locked")
	assert_false(w.is_walking())
	assert_true(w.last_text.begins_with("趕路中斷"), w.last_text)
	await _frames(2)
	assert_eq(sent.size(), 1, "no further moves")

func test_walker_stops_on_battle_and_cancel() -> void:
	var w := _make_walker()
	w.start([{ "dir": "N", "to": "xw_wood" }, { "dir": "S", "to": "xw_grass" }], "xw_grass")
	w.gate.resolve(sent[0][0], true, "")
	# M3c：遇敵＝暫停（不送下一步），戰鬥結束後依結果決定
	w.on_battle()
	assert_true(w.is_walking(), "battle pauses walking")
	assert_eq(w.phase, "battle")
	w.on_view(_room_view("xw_wood"))
	await _frames(2)
	assert_eq(sent.size(), 1, "no move during battle")
	w.resume_delay_s = 0.0
	w.on_battle_end("DEFEAT", true)
	await _frames(2)
	assert_false(w.is_walking())
	assert_eq(w.last_text, AutoWalkCore.MSG_DEFEAT)
	assert_eq(sent.size(), 1, "defeat stops walking")

	w.start([{ "dir": "S", "to": "xw_grass" }, { "dir": "W", "to": "xw_road" }], "xw_wood")
	w.stop("已取消趕路。")
	w.gate.resolve(sent[1][0], true, "")
	w.on_view(_room_view("xw_grass"))
	await _frames(2)
	assert_eq(sent.size(), 2, "cancel stops walking")
	assert_false(w.is_walking())

func test_walker_stops_on_unexpected_room() -> void:
	var w := _make_walker()
	w.start([{ "dir": "E", "to": "xx_gate_e" }, { "dir": "E", "to": "xw_road" }], "xx_square")
	w.gate.resolve(sent[0][0], true, "")
	w.on_view(_room_view("dl_square"))   # 例如死亡重生被送走
	assert_false(w.is_walking())

func test_walker_view_timeout() -> void:
	var w := _make_walker()
	w.start([{ "dir": "E", "to": "xx_gate_e" }], "xx_square")
	w.gate.resolve(sent[0][0], true, "")
	w.deadline_ms = 0
	await _frames(2)
	assert_false(w.is_walking())
	assert_true(w.last_text.contains("沒有收到房間資訊"), w.last_text)

# ---------------------------------------------------------------- MapPanel

func _make_panel() -> MapPanel:
	var gate := _add(IntentGate.new()) as IntentGate
	gate.set_sender(_sender)
	var p := MapPanel.new()
	p.gate = gate
	p.tables_override = view
	p.memory = MapMemory.new(_dir)
	_add(p)
	p.walker.step_delay_s = 0.0
	p.apply_sheet({ "char_id": "ch_maptest" })
	return p

func test_panel_fog_and_click_to_walk() -> void:
	var p := _make_panel()
	p.apply_view(_room_view("xx_square"))
	p.apply_view(_room_view("xx_street"))
	p.apply_view(_room_view("xx_wuguan"))
	await tree.process_frame
	var rv := p.region_view
	assert_true(rv.visible_rooms().has("xx_square"))
	assert_true(rv.visible_rooms().has("xx_wuguan"))
	assert_true(rv.unknown_rooms().has("xx_pharmacy"), "neighbour shown as ？")
	assert_false(rv.is_shown("xx_inn_2f"), "far room hidden")
	assert_eq(rv.tooltip_for("xx_pharmacy"), "還沒去過的地方。")
	assert_true(rv.tooltip_for("xx_square").contains("點擊前往"))
	assert_true(p.memory.has("xx_wuguan"), "remembered")

	# 點沒去過的房間：不走
	p._on_room_clicked("xx_pharmacy")
	assert_eq(sent.size(), 0)
	# 點到過的房間：沿已知出口走 E、E
	p._on_room_clicked("xx_square")
	assert_true(p.walker.is_walking())
	assert_true(p.status_label.text.begins_with("趕路中：往"), p.status_label.text)
	assert_eq(sent.size(), 1)
	assert_eq(sent[0][2], { "dir": "E" })
	p.walker.gate.resolve(sent[0][0], true, "")
	p.apply_view(_room_view("xx_street"))
	await _frames(2)
	assert_eq(sent.size(), 2)
	# 再點一次＝取消
	p._on_room_clicked("")
	assert_false(p.walker.is_walking())
	assert_eq(p.status_label.text, "已取消趕路。")

func test_panel_tooltip_shows_danger() -> void:
	var p := _make_panel()
	p.apply_view(_room_view("xw_road"))
	p.apply_view(_room_view("xw_grass"))
	var tip := p.region_view.tooltip_for("xw_grass")
	assert_true(tip.contains("危險："), tip)
	assert_true(p.region_view.tooltip_for("xw_road").contains(str(view["npcs"]["n_chenjialuo"]["name"])))

func test_panel_world_tab() -> void:
	var p := _make_panel()
	p.apply_view(_room_view("dl_square"))
	p.show_tab(MapPanel.TAB_WORLD)
	await _frames(2)
	assert_eq(p.world_view.current_region, "dali")
	assert_true(p.world_view.center_of("dali") != p.world_view.center_of("xixia"))

# ---------------------------------------------------------------- 主畫面掛鉤

func test_main_screen_map_button_and_hotkey() -> void:
	var main: Node = (load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate()
	_add(main)
	await tree.process_frame
	main.map_panel.memory = MapMemory.new(_dir)
	assert_true(main.panel_buttons.has("map"), "map button")
	assert_eq(main.panel_buttons["map"].text, "地圖(Ctrl+M)")
	main.toggle_panel("map")
	assert_true(main.map_panel.visible and main.panel_frame.visible)
	assert_eq(main.panel_title.text, "地圖")
	var k := InputEventKey.new()
	k.keycode = KEY_M
	k.pressed = true
	main._shortcut_input(k)
	assert_false(main.panel_frame.visible, "M closes")
	main._shortcut_input(k)
	assert_true(main.map_panel.visible, "M opens")
	main.apply_view(_room_view("xx_square"))
	await tree.process_frame
	assert_true(main.map_panel.region_view.visible_rooms().has("xx_square"))
	main.close_panel()

# ---------------------------------------------------------------- 第一輪 UI 稽核

func test_panel_footer_resets_on_region_change() -> void:
	var p := _make_panel()
	p.apply_view(_room_view("xx_square"))
	p.apply_view(_room_view("xx_station"))
	p._on_room_clicked("xx_square")
	assert_true(p.walker.is_walking())
	p.walker.gate.resolve(sent[0][0], true, "")
	p.apply_view(_room_view("xx_square"))
	await _frames(2)
	assert_eq(p.status_label.text, "已抵達。")
	# 坐驛站車到大理：新區域的頁尾回到說明，不留「已抵達。」
	p.apply_view(_room_view("dl_station"))
	assert_eq(p.status_label.text, MapPanel.HINT)

func test_world_map_routes_avoid_other_regions() -> void:
	# 預設（驛站馬車關）：全圖只有步行線，沒有驛站路線
	var w0 := WorldMapView.new()
	_add(w0)
	w0.size = Vector2(1000, 470)
	w0.setup(MapData.world_model(view), "xixia")
	assert_eq(w0.routes().size(), 0, "stagecoach off: no travel routes drawn")
	# 原作座標很擠（西夏一帶）：方框不能疊在一起，也不能超出畫面
	for sz in [Vector2(1000, 470), Vector2(760, 440), Vector2(1600, 800)]:
		w0.size = sz
		w0.setup(MapData.world_model(view), "xixia")
		w0.routes()
		var ids: Array = w0._rects.keys()
		assert_eq(ids.size(), view["regions"].size(), "every region boxed")
		for i in ids.size():
			assert_true(Rect2(Vector2.ZERO, sz).encloses(w0._rects[ids[i]]), "%s %s inside view" % [str(sz), ids[i]])
			for j in range(i + 1, ids.size()):
				assert_false((w0._rects[ids[i]] as Rect2).intersects(w0._rects[ids[j]]), "%s: %s overlaps %s" % [str(sz), ids[i], ids[j]])
	# 驛站馬車開（1.0B 有京城）：路線繞開其他區域方框
	var vb := DataLoader.new()
	vb.load_all("res://data")
	var tb := vb.activate(["1.0A", "1.0B"])
	for vw in [[view, "xixia"], [tb, "jingcheng"]]:
		var tables: Dictionary = vw[0]
		for sz in [Vector2(1000, 470), Vector2(760, 440), Vector2(1600, 800)]:
			var w := WorldMapView.new()
			_add(w)
			w.size = sz
			w.setup(MapData.world_model(tables, true), vw[1])
			var routes: Dictionary = w.routes()
			assert_true(routes.size() >= 1, "travel routes exist")
			for key in routes:
				var ab: PackedStringArray = str(key).split("|")
				for id in w._rects:
					if id == ab[0] or id == ab[1]:
						continue
					assert_false(MapLayout.polyline_hits_rect(routes[key], w._rects[id]),
						"%s %s: route %s passes through %s" % [vw[1], str(sz), key, id])
	# 「你在這裡」不壓在任何線上（每個區域都試，預設與馬車開都試）
	for coach in [false, true]:
		for sz in [Vector2(1000, 470), Vector2(760, 440), Vector2(1600, 800)]:
			var w := WorldMapView.new()
			_add(w)
			w.size = sz
			var model := MapData.world_model(view, coach)
			for r in model["regions"]:
				w.setup(model, r["id"])
				var here: Dictionary = w.here_label()
				assert_false(here.is_empty(), r["id"])
				var segs: Array = w.walk_segments()
				for pts in w.routes().values():
					for i in (pts as PackedVector2Array).size() - 1:
						segs.append([pts[i], pts[i + 1]])
				for sg in segs:
					assert_false(MapLayout.segment_hits_rect(sg[0], sg[1], here["rect"]), "%s %s coach=%s: 你在這裡 label on a line" % [str(sz), r["id"], str(coach)])

func test_region_map_links_stop_at_box_edges() -> void:
	var p := _make_panel()
	p.apply_view(_room_view("xx_square"))
	await _frames(1)
	var rv := p.region_view
	assert_true(rv.unknown_rooms().size() > 0, "start: neighbours are ？")
	for seg in rv.segments():
		for id in rv._rects:
			if rv.is_shown(id):
				var inner := (rv._rects[id] as Rect2).grow(-2.0)
				assert_false(MapLayout.segment_hits_rect(seg[0], seg[1], inner), "link %s crosses box %s" % [str(seg), id])
	var here := rv.here_label()
	assert_false(here.is_empty())
	for seg in rv.segments():
		assert_false(MapLayout.segment_hits_rect(seg[0], seg[1], here["rect"]), "你在這裡 label on a link")

func test_mini_map_follows_and_walks() -> void:
	var p := _make_panel()
	var mm := MiniMap.new()
	_add(mm)
	mm.size = Vector2(400, 260)
	p.mini_map = mm
	mm.room_clicked.connect(p.walk_to)
	p.apply_view(_room_view("xx_square"))
	p.apply_view(_room_view("xx_station"))
	await _frames(1)
	assert_eq(mm.view.current, "xx_station")
	assert_true(mm.title_label.text.begins_with("西夏"), mm.title_label.text)
	var cur: Rect2 = mm.view.screen_rect("xx_station")
	# 審查 round 4：不再死板地讓目前房間置中，而是讓目前房間＋相鄰一圈（含出區箭頭）整個放進框裡
	var view_r := Rect2(Vector2.ZERO, mm.view.size)
	assert_true(view_r.encloses(cur), "current room inside the mini map: %s in %s" % [str(cur), str(view_r)])
	var nb := mm.view.neighbourhood_box()
	var nb_screen := Rect2((nb.position + mm.view._offset) * mm.view.zoom, nb.size * mm.view.zoom)
	assert_true(view_r.grow(0.5).encloses(nb_screen), "neighbourhood inside the mini map: %s in %s" % [str(nb_screen), str(view_r)])
	mm.room_clicked.emit("xx_square")
	assert_true(p.walker.is_walking(), "mini map click walks")
	assert_eq(mm.view.walk_target, "xx_square")
	assert_true(mm.status_label.text.begins_with("趕路中：往"), mm.status_label.text)
