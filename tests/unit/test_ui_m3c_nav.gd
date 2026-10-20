extends "res://tests/test_case.gd"
## M3C_PLAN §4.5、§4.6（WP-NAV）：「往XXX」切到鄰區（瀏覽中）與返回、瀏覽中點房間＝跨區趕路、江湖全圖點地區趕路、
## 快捷選單、全圖有／無底圖的站點座標（底圖＝tools/make_map_layout_guide.py 同一轉換）、區域圖美術（9 宮格、圖示）。

var loader: DataLoader
var view: Dictionary
var _nodes: Array = []
var sent: Array = []
var _seq := 900
var _dir := ""

func before_each() -> void:
	if loader == null:
		loader = DataLoader.new()
		loader.load_all("res://data")
		view = loader.activate(["1.0A"])
	sent.clear()
	_dir = temp_dir("m3cnav")
	MapArt.use_textures(null)

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

func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame

func _room_view(room: String) -> Dictionary:
	var idx := MapData.room_index(view)
	var region: String = idx[room]["region"]
	return { "room": room, "room_name": str(idx[room]["room"]["name"]), "region": region,
		"region_name": MapData.region_name(view, region), "exits": [], "npcs": [] }

func _panel(with_mini := true) -> MapPanel:
	var gate := _add(IntentGate.new()) as IntentGate
	gate.set_sender(_sender)
	var p := MapPanel.new()
	p.gate = gate
	p.tables_override = view
	p.memory = MapMemory.new(_dir)
	_add(p)
	p.size = Vector2(900, 480)
	p.walker.step_delay_s = 0.0
	if with_mini:
		var mm := MiniMap.new()
		_add(mm)
		mm.size = Vector2(264, 228)
		p.bind_mini_map(mm)
	p.apply_sheet({ "char_id": "ch_navtest", "vitals": { "qi": 100, "qi_max": 100, "food": 90, "water": 90 } })
	return p

## 走過 西夏廣場 → 東門 → 西夏郊外 → 草地，再回到東門
func _explore(p: MapPanel) -> void:
	for r in ["xx_square", "xx_gate_e", "xw_road", "xw_grass", "xw_road", "xx_gate_e"]:
		p.apply_view(_room_view(r))

func _tex(w: int, h: int, c: Color = Color(0.8, 0.7, 0.5)) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- 「往XXX」

func test_edge_node_is_clickable_and_emits_region() -> void:
	var p := _panel()
	_explore(p)
	await _frames(1)
	var rv := p.region_view
	var items := rv.out_exit_items()
	var to_wild: Dictionary = {}
	for it in items:
		if it["to_region"] == "xixia_wild":
			to_wild = it
	assert_false(to_wild.is_empty(), "東門 has 往西夏郊外: %s" % str(items.map(func(i): return i["label"])))
	assert_true(str(to_wild["label"]).begins_with("往"))
	var at := (to_wild["label_rect"] as Rect2).get_center() * rv.zoom
	assert_eq(rv.region_at(at), "xixia_wild")
	assert_eq(rv.room_at(at), "", "label is not a room")
	var tip := rv._get_tooltip(at)
	assert_true(tip.contains("切換"), "tooltip <%s>" % tip)
	var got: Array = []
	rv.region_clicked.connect(func(id: String): got.append(id))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	rv._gui_input(ev)
	assert_eq(got, ["xixia_wild"])
	# 點下去之後面板已切到西夏郊外（瀏覽中）
	assert_eq(p.browse_region, "xixia_wild", "MapPanel switched the view")

func test_show_region_browse_and_back() -> void:
	var p := _panel()
	_explore(p)
	assert_eq(p.current_region(), "xixia")
	p.show_region("xixia_wild")
	await _frames(1)
	assert_eq(p.browse_region, "xixia_wild")
	assert_eq(p.region_view.model.get("region"), "xixia_wild")
	assert_true(p.region_title.text.contains("（瀏覽中）"), p.region_title.text)
	assert_true(p.back_button.visible, "返回目前區域 shown")
	assert_true(p.mini_map.back_button.visible, "mini map ⟲ shown")
	# M3c 審查：瀏覽中標題前加「瀏覽 」、返回鈕寫「返」（不再用看不懂的「⟲」）
	# M3c 第二輪審查：瀏覽中不寫探索數、地圖鈕只寫「地圖」（標題才放得下，不會切成「瀏覽 西夏郊⁄」）
	assert_eq(p.mini_map.title_label.text, "瀏覽 西夏郊外")
	assert_eq(p.mini_map.map_button.text, "地圖")
	assert_eq(p.mini_map.back_button.text, "返")
	assert_true(p.mini_map.status_label.text.length() <= 14, "mini status short enough: " + p.mini_map.status_label.text)
	assert_true(p.mini_map.title_label.tooltip_text.contains("瀏覽中"), p.mini_map.title_label.tooltip_text)
	assert_true(p.region_view.visible_rooms().has("xw_grass"), "explored rooms of the browsed region")
	assert_eq(p.mini_map.view.focus_id(), "xw_road", "mini map centred on the entry room from here")
	# 點那區到過的房間 → 跨區趕路
	p._on_room_clicked("xw_grass")
	assert_true(p.is_walking())
	assert_eq(sent[0][2], { "dir": "E" })
	assert_eq(p.walker.target(), "xw_grass")
	assert_true(p.status_label.text.contains("剩2步"), p.status_label.text)
	# 玩家移動：畫面不跳回
	p.walker.gate.resolve(sent[0][0], true, "")
	p.apply_view(_room_view("xw_road"))
	assert_true(p.browse_region == "" or p.browse_region == "xixia_wild")
	# 抵達：回到目前區域
	await _frames(2)
	p.walker.gate.resolve(sent[1][0], true, "")
	p.apply_view(_room_view("xw_grass"))
	assert_false(p.is_walking())
	assert_eq(p.browse_region, "")
	assert_false(p.back_button.visible)

func test_browse_stays_while_moving_and_back_button() -> void:
	var p := _panel()
	_explore(p)
	p.show_region("xixia_wild")
	p.apply_view(_room_view("xx_square"))   # 自己走動
	assert_eq(p.browse_region, "xixia_wild", "view does not jump back")
	p.back_to_current()
	assert_eq(p.browse_region, "")
	assert_eq(p.region_view.model.get("region"), "xixia")
	assert_eq(p.status_label.text, MapPanel.HINT)
	# 小地圖的「往XXX」與 ⟲
	p.mini_map.region_clicked.emit("xixia_wild")
	assert_eq(p.browse_region, "xixia_wild")
	p.mini_map.back_requested.emit()
	assert_eq(p.browse_region, "")
	# 切到目前區域＝返回
	p.show_region("xixia_wild")
	p.show_region("xixia")
	assert_eq(p.browse_region, "")

func test_browse_unexplored_region_shows_fog() -> void:
	var p := _panel()
	_explore(p)
	p.show_region("dali")
	assert_eq(p.browse_region, "dali")
	assert_eq(p.region_view.visible_rooms().size(), 0)
	assert_eq(p.status_label.text, MapPanel.NEVER_BEEN)
	assert_eq(p.mini_map.status_label.text, MapPanel.NEVER_BEEN)
	p._on_room_clicked("dl_square")
	assert_false(p.is_walking(), "can't walk to an unexplored room")
	p.show_region("no_such_region")
	assert_eq(p.browse_region, "dali", "unknown region ignored")

# ---------------------------------------------------------------- 江湖全圖點地區、快捷

func test_world_map_click_walks_to_region() -> void:
	var p := _panel()
	_explore(p)
	p.apply_view(_room_view("xx_square"))
	var got: Array = []
	p.world_view.region_clicked.connect(func(id: String): got.append(id))
	p.world_view.size = Vector2(900, 440)
	p.world_view.setup(MapData.world_model(view), "xixia")
	var c := p.world_view.center_of("xixia_wild")
	assert_eq(p.world_view.region_at(c), "xixia_wild")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = c
	p.world_view._gui_input(ev)
	assert_eq(got, ["xixia_wild"])
	assert_true(p.is_walking(), "world-map click starts walking")
	assert_eq(p.walker.target(), "xw_road", "nearest explored room of 西夏郊外")
	p.walker.stop("")
	# 沒去過的地區：走到最近的已探索房間並說明
	p.walk_to_region("huashan")
	assert_true(p.is_walking())
	assert_true(p.status_label.text.contains("只能走到"), p.status_label.text)
	p.walker.stop("")
	p.walk_to_region("xixia")
	assert_false(p.is_walking())
	assert_true(p.status_label.text.contains("已經在"), p.status_label.text)

func test_quick_menu_items_and_walk() -> void:
	var p := _panel()
	_explore(p)
	p.apply_sheet({ "char_id": "ch_navtest", "respawn": { "room": "xx_square" }, "birth_city": "xixia",
		"vitals": { "qi": 100, "qi_max": 100, "food": 90, "water": 90 } })
	p.apply_view(_room_view("xw_grass"))
	var pm := PopupMenu.new()
	_add(pm)
	p._fill_quick(pm)
	assert_eq(pm.item_count, 5)
	assert_true(pm.get_item_text(0).begins_with("記錄點："), pm.get_item_text(0))
	assert_false(pm.is_item_disabled(0))
	assert_true(pm.is_item_disabled(2), "no sect: greyed")
	assert_true(pm.get_item_text(2).contains("你沒有門派"))
	assert_true(pm.is_item_disabled(4), "no quest mark")
	p.walk_quick(0)
	assert_true(p.is_walking())
	assert_eq(p.walker.target(), "xx_square")
	assert_true(p.status_label.text.begins_with("趕路中：往"), p.status_label.text)
	p.walk_quick(2)   # 灰掉的：寫原因，不走
	assert_true(p.status_label.text.contains("你沒有門派"), p.status_label.text)

# ---------------------------------------------------------------- 地圖美術（§4.6）

func test_world_map_without_art_is_unchanged() -> void:
	var w := WorldMapView.new()
	_add(w)
	w.size = Vector2(1000, 470)
	w.setup(MapData.world_model(view), "xixia")
	assert_false(w.art_mode, "no map_world_base → procedural parchment")
	assert_false(MapArt.has_world_art())
	# 程式繪圖的版面（不鎖 4:3）：最西與最東的地點橫跨大半個畫面
	var xs: Array = []
	for r in MapData.world_model(view)["regions"]:
		xs.append(w.center_of(r["id"]).x)
	assert_true(xs.max() - xs.min() > 1000 * 0.6, "spread over the width")

func test_world_map_with_base_art_stations_follow_guide_transform() -> void:
	MapArt.use_textures({ "world_base": _tex(2400, 1800) })
	assert_true(MapArt.has_world_art())
	var model := MapData.world_model(view)
	for sz in [Vector2(1000, 470), Vector2(760, 440), Vector2(800, 600), Vector2(1600, 800)]:
		var w := WorldMapView.new()
		_add(w)
		w.size = sz
		w.setup(model, "xixia")
		assert_true(w.art_mode)
		var rect := MapArt.world_rect(sz)
		assert_true(is_equal_approx(rect.size.x / rect.size.y, 4.0 / 3.0), "4:3 locked")
		assert_true(Rect2(Vector2.ZERO, sz).grow(0.01).encloses(rect))
		for r in model["regions"]:
			var wp: Vector2 = r["pos"]
			var want := Vector2(rect.position.x + (60.0 / 1600.0 + wp.x / 1000.0 * 1480.0 / 1600.0) * rect.size.x,
				rect.position.y + (60.0 / 1200.0 + wp.y / 1000.0 * 1080.0 / 1200.0) * rect.size.y)
			var got := w.center_of(r["id"])
			assert_true(got.distance_to(want) < 0.01, "%s %s: %s vs %s" % [str(sz), r["id"], str(got), str(want)])
		assert_eq(w.region_at(w.center_of("dali")), "dali", "stations clickable in art mode")
	# 2400×1800 畫布上的像素＝make_map_layout_guide.py 的 P()×1.5
	var full := Rect2(Vector2.ZERO, Vector2(2400, 1800))
	assert_eq(MapArt.world_point(full, Vector2(0, 0)), Vector2(90, 90))
	assert_eq(MapArt.world_point(full, Vector2(1000, 1000)), Vector2(2310, 1710))
	assert_eq(MapArt.world_point(full, Vector2(500, 500)), Vector2(1200, 900))

func test_region_map_art_draws_without_errors() -> void:
	MapArt.use_textures({ "region_bg": _tex(64, 64), "node_room": _tex(384, 192), "node_current": _tex(384, 192, Color.RED),
		"node_fog": _tex(384, 192, Color.GRAY), "marker_here": _tex(256, 256), "icon:inn": _tex(256, 256),
		"icon:station": _tex(256, 256), "icon:shop": _tex(256, 256), "icon:master": _tex(256, 256), "icon:record": _tex(256, 256),
		"icon:stove": _tex(256, 256), "icon:danger": _tex(256, 256), "icon:exit": _tex(256, 256), "icon:quest": _tex(256, 256) })
	var p := _panel()
	_explore(p)
	p.apply_view(_room_view("xx_square"))
	await _frames(2)
	var rv := p.region_view
	var room: Dictionary = rv.model["by_id"]["xx_square"]
	var badges := MapData.room_badges(view, room)
	if not badges.is_empty():
		assert_eq(rv.badge_icons(badges).size() > 0, true, "icons replace badge text: %s" % str(badges))
	assert_eq(rv.badge_icons(["不存在"]), [], "missing icon → text")
	# 9 宮格：畫在 118×54 的框內（直接在一個 CanvasItem 上畫，確認不出錯）
	var ci := Control.new()
	_add(ci)
	ci.draw.connect(func(): MapArt.draw_nine(ci, MapArt.texture("node_room"), Rect2(4, 4, 118, 54)))
	ci.queue_redraw()
	await _frames(2)
	assert_eq(MapArt.texture("node_room").get_size(), Vector2(384, 192))
	MapArt.use_textures(null)
	assert_eq(MapArt.texture("node_room"), null, "back to registry (no art → null)")
