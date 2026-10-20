extends "res://tests/test_case.gd"
## 回歸（WORLD_2001 介面審查第 1 輪）：NPC 氣泡不蓋出口、戰場損血字不和鄰居疊在一起、結束後的指令區、
## 系統訊息框有內容、商店待買欄不切半格、小地圖標題與小字、江湖全圖（羊皮紙＋未開放的山門）、出生地圖的地理。

const STATE_SCRIPT := preload("res://tests/unit/test_ui_battle_view_model.gd")

var _nodes: Array = []

func before_each() -> void:
	UiSettings.reset_for_tests(true)

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame

# ---------------------------------------------------------------- 1. NPC 氣泡

func test_npc_bubble_sits_beside_the_name_not_over_exits_and_expires() -> void:
	var holder := Control.new()
	holder.size = Vector2(640, 260)
	_add(holder)
	var sp := ScenePanel.new()
	holder.add_child(sp)
	sp.size = Vector2(620, 240)
	sp.apply_view({ "room_name": "西夏廣場", "region_name": "西夏", "safe": true, "desc": "廣場。",
		"exits": [{ "dir": "E", "to_name": "西夏東門" }, { "dir": "S", "to_name": "西夏驛站" }, { "dir": "W", "to_name": "西大街" }],
		"npcs": [{ "id": "n_a", "name": "武介山", "services": ["QUEST"] }], "players": [], "corpses": [], "features": [] })
	await _frames(3)
	sp.show_bubble("n_a", "武介山愁眉苦臉地說：「最近西夏郊外荒草坡的大野兔越來越多。」")
	await _frames(2)
	assert_eq(sp.active_bubbles(), ["n_a"])
	var b: Button = sp.npc_buttons["n_a"]
	var r := sp.bubble_rect(b, 120.0, 13)
	var brect := Rect2(b.global_position - sp.bubble_layer.global_position, b.size)
	assert_true(absf(r.get_center().y - brect.get_center().y) < 2.0, "same row as the name: %s vs %s" % [r, brect])
	assert_false(r.intersects(brect), "does not cover the name itself")
	for ex in sp.exits_box.get_children():
		var er := Rect2((ex as Control).global_position - sp.bubble_layer.global_position, (ex as Control).size)
		assert_false(r.intersects(er), "bubble %s covers exit %s" % [r, er])
	# 3 秒後消失（不靠重畫）
	sp._bubbles["n_a"]["until"] = Time.get_ticks_msec() - 1
	sp._process(0.016)
	assert_eq(sp.active_bubbles().size(), 0, "expired bubble is gone")

# ---------------------------------------------------------------- 3. 損血字

func test_waist_hp_text_moves_into_the_plate_when_it_would_hit_a_neighbour() -> void:
	var v := BattleIsoView.new()
	_add(v)
	v.size = Vector2(1280, 552)
	v.set_vm(BattleViewModel.from_state(STATE_SCRIPT.state()))
	var vm := v.vm
	await _frames(2)
	var me: UnitSprite = v.sprites[1]
	var foe: UnitSprite = v.sprites[2]
	# 分開站：腰部顯示
	BattleFx.layout_names_with_hp([me, foe], true)
	assert_false(me.hp_line, "far apart: hp text stays at the waist")
	# 野兔貼到我腳邊：牠的名字牌會在我腰部的高度
	vm.units[2]["pos"] = Vector2i(1, 4)
	await _frames(3)
	BattleFx.layout_names_with_hp([me, foe], true)
	var plates := [me.name_box, foe.name_box]
	var texts: Array = []
	for s in [me, foe]:
		if not s.hp_line:
			texts.append(s.waist_hp_rect())
	for t in texts:
		for p in plates:
			assert_false((t as Rect2).intersects(p), "waist hp %s overlaps a name plate %s" % [t, p])
	assert_false(me.name_box.intersects(foe.name_box), "plates (with hp line) still apart")
	if me.hp_line:
		assert_true(me.name_box.size.y >= me.name_font_size() + me.bars_h() + me.hp_h(), "plate grew a line for cur/max")
	# 損血顯示關掉：不畫
	BattleFx.layout_names_with_hp([me, foe], false)
	assert_eq(me.waist_hp_rect(), Rect2())
	assert_eq(me.hp_h(), 0.0)

# ---------------------------------------------------------------- 10. 系統訊息框

func test_hud_message_box_gets_system_notices() -> void:
	var ml := MessageLog.new()
	_add(ml)
	var host := VBoxContainer.new()
	host.size = Vector2(400, 120)
	_add(host)
	var box := ml.build_announce(host)
	await _frames(1)
	ml.announce_lines.clear()   # 前面測試留下的事件（MessageLog 開啟時會重播最近的事件）
	ml.add_event({ "ch": "SYSTEM", "key": "quest_accepted", "p": { "name": "驛站送信" } })
	ml.add_event({ "ch": "BATTLE", "key": "battle_kill", "p": { "uid": 2, "name": "野兔", "peer": 7 } })
	assert_eq(ml.announce_lines.size(), 1, "system notice goes to the HUD box; battle text does not")
	assert_true(box.get_parsed_text().contains("quest_accepted") or box.get_parsed_text().contains("驛站送信"), box.get_parsed_text())
	# 江湖謠言關掉：公告不顯示，系統通知照樣顯示
	ml.add_announcement("某某拜入少林")
	ml.set_channel_enabled("江湖謠言", false)
	assert_false(box.get_parsed_text().contains("某某拜入少林"))
	assert_true(box.get_parsed_text().strip_edges() != "", "system notices stay")

# ---------------------------------------------------------------- 11. 商店待買

func test_shop_zones_show_whole_rows_only() -> void:
	var d := ShopDialog.new()
	_add(d)
	d.ensure_built()
	for g in [d.mine_grid, d.shop_grid, d.cart_grid]:
		var sc := (g as Control).get_parent() as ScrollContainer
		var row := ShopDialog.SLOT.y + 4.0
		var h := sc.custom_minimum_size.y
		assert_eq(fmod(h + 4.0, row), 0.0, "zone height %.0f is a whole number of rows" % h)

# ---------------------------------------------------------------- 9. 小地圖

func test_mini_map_title_is_compact_and_small_text_readable() -> void:
	assert_eq(MiniMap.compact_title("西夏　已探索 4／9 處"), "西夏 4/9")
	assert_eq(MiniMap.compact_title("（尚未進入世界）"), "（尚未進入世界）")
	var rv := RegionMapView.new()
	rv.zoom = MiniMap.MINI_ZOOM
	assert_true(rv.badge_size() * rv.zoom >= 10.0, "badges at least 10 px on screen")
	assert_true(rv.name_size() * rv.zoom >= 10.0, "names at least 10 px on screen")
	rv.free()

# ---------------------------------------------------------------- 7. 江湖全圖

func test_world_map_is_a_parchment_map_with_closed_gates() -> void:
	var loader := DataLoader.new()
	loader.load_all("res://data")
	var view := loader.activate(["1.0A"])
	for sz in [Vector2(1190, 430), Vector2(1000, 400), Vector2(1600, 800)]:
		var w := WorldMapView.new()
		_add(w)
		w.size = sz
		w.setup(MapData.world_model(view), "xixia")
		w.routes()
		var names: PackedStringArray = []
		for st in w.sites():
			names.append(str(st["name"]))
		# M3a：恆山、武當、終南山（全真／古墓）、峨嵋、星宿、血刀已開放，畫成門派地區；
		# 故事包（STORY_PLAN §2.1）：衡山、雁門關也開了，畫成地區，不再有「未開」的地點
		for nm in ["恆山派", "武當派", "全真教", "古墓派", "峨嵋派", "星宿派", "血刀門", "衡山", "雁門關"]:
			assert_true(nm in names, "%s on the world map" % nm)
		assert_eq(w._closed_rects.size(), 0, "no closed sites left")
		var all: Array = w._rects.values() + w._closed_rects.values()
		for i in all.size():
			assert_true(Rect2(Vector2.ZERO, sz).encloses(all[i]), "%s inside the view" % str(all[i]))
			for j in range(i + 1, all.size()):
				assert_false((all[i] as Rect2).intersects(all[j]), "%s: site %s overlaps %s" % [str(sz), str(all[i]), str(all[j])])
		# 步行線從記號邊緣畫到記號邊緣：線的兩端不在任何記號裡面
		for sg in w.walk_segments():
			for id in w._marks:
				var inner := (w._marks[id] as Rect2).grow(-1.0)
				assert_false(inner.has_point(sg[0]) or inner.has_point(sg[1]), "road ends inside mark %s" % id)
		# 地理方向：西夏在大理北邊、少林在華山東邊、血刀門在最西
		assert_true(w.center_of("xixia").y < w.center_of("dali").y, "西夏 north of 大理")
		assert_true(w.center_of("shaolin").x > w.center_of("huashan").x, "少林 east of 華山")
		assert_true(w.center_of("closed_xuedao").x < w.center_of("dali").x, "血刀門 far west")

# ---------------------------------------------------------------- 8. 出生地圖

func test_birth_map_keeps_the_original_geography() -> void:
	var cc = (load("res://ui/game/char/char_create.gd") as GDScript)
	var bm = cc.BirthMap.new()
	_add(bm)
	bm.size = Vector2(260, 540)
	bm.cities = [{ "id": "xixia", "name": "西夏" }, { "id": "dali", "name": "大理" }]
	bm._layout()
	var xx: Rect2 = bm._rects[0]
	var dl: Rect2 = bm._rects[1]
	assert_true(xx.get_center().y < dl.get_center().y, "西夏 is north of 大理")
	assert_true(xx.get_center().x >= dl.get_center().x, "西夏 is a little east of 大理")
	assert_true(xx.get_center().x - dl.get_center().x < bm.size.x * 0.2, "only a little east")
	assert_true(xx.get_center().x < bm.size.x * 0.5 and dl.get_center().x < bm.size.x * 0.5, "both on the west side")
	assert_true(xx.position.y > 60.0, "西夏 seal stays below the title")
	assert_true(bm._dots.size() > 0, "other places drawn faintly for context")
