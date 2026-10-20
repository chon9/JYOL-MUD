extends "res://tests/test_case.gd"
## M3c 審查（第一輪，介面）回歸：更換造型的回饋、小地圖「返」與瀏覽標籤、「往XXX」字夾在畫面內、趕路路線畫在
## 區域圖／小地圖／江湖全圖、「你在這裡」貼著自己的記號、動手確認框（標題、再想想）、「無遇敵」標籤、
## 武器特效最短長度、背包格名與詳情不重複、部位名一致、條件文字不露型別碼。全部用假資料或 res://data。

var loader: DataLoader
var view: Dictionary
var _nodes: Array = []
var _dir := ""
var _seq := 900

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	if loader == null:
		loader = DataLoader.new()
		loader.load_all("res://data")
		view = loader.activate(["1.0A"])
	_dir = temp_dir("m3c_review1")
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

func _room_view(room: String) -> Dictionary:
	var idx := MapData.room_index(view)
	var region: String = idx[room]["region"]
	return { "room": room, "room_name": str(idx[room]["room"]["name"]), "region": region,
		"region_name": MapData.region_name(view, region), "exits": [], "npcs": [] }

func _panel() -> MapPanel:
	var gate := _add(IntentGate.new()) as IntentGate
	gate.set_sender(func(_k, _a):
		_seq += 1
		return _seq)
	var p := MapPanel.new()
	p.gate = gate
	p.tables_override = view
	p.memory = MapMemory.new(_dir)
	_add(p)
	p.size = Vector2(900, 480)
	p.walker.step_delay_s = 0.0
	var mm := MiniMap.new()
	_add(mm)
	mm.size = Vector2(264, 228)
	p.bind_mini_map(mm)
	p.apply_sheet({ "char_id": "ch_review1", "vitals": { "qi": 100, "qi_max": 100, "food": 90, "water": 90 } })
	return p

# ---------------------------------------------------------------- 地圖

func test_walk_path_drawn_on_region_mini_and_world_maps() -> void:
	var p := _panel()
	for r in ["xx_square", "xx_gate_e", "xw_road", "xw_grass", "xw_road", "xx_gate_e", "xx_square"]:
		p.apply_view(_room_view(r))
	p.world_view.size = Vector2(900, 440)
	p.world_view.setup(MapData.world_model(view), "xixia")
	p.walk_to_region("xixia_wild")
	assert_true(p.is_walking())
	var rooms: Array = p.walker.remaining_rooms()
	assert_eq(str(rooms[0]), "xx_square", "starts at the current room")
	assert_eq(str(rooms[rooms.size() - 1]), p.walker.target(), "ends at the target")
	assert_eq(p.region_view.walk_path, rooms, "region map has the route")
	assert_eq(p.mini_map.view.walk_path, rooms, "mini map has the route")
	assert_eq(p.world_view.walk_route, ["xixia", "xixia_wild"], "world map: regions on the way")
	assert_true(p.region_view._walk_exit_regions().has("xixia_wild") or rooms.all(func(r): return (p.region_view.model["pos"] as Dictionary).has(r)),
		"the 往西夏郊外 exit is on the route")
	p.walker.stop("")
	assert_eq(p.region_view.walk_path, [], "cleared when stopped")
	assert_eq(p.world_view.walk_route, [])

func test_route_regions_merges_runs() -> void:
	var p := _panel()
	assert_eq(p.route_regions(["xx_square", "xx_gate_e", "xw_road", "xw_grass"]), ["xixia", "xixia_wild"])
	assert_eq(p.route_regions([]), [])

func test_edge_labels_clamped_inside_view() -> void:
	var rv := RegionMapView.new()
	_add(rv)
	rv.size = Vector2(200, 120)
	rv.zoom = 0.5
	var out := rv.clamp_label(Rect2(Vector2(380, -20), Vector2(60, 16)))
	var vis := Rect2(Vector2.ZERO, rv.size / rv.zoom)
	assert_true(vis.encloses(out), "label pulled inside the view: %s" % str(out))
	var inside := Rect2(Vector2(100, 100), Vector2(60, 16))
	assert_eq(rv.clamp_label(inside), inside, "labels already inside do not move")

func test_minimap_back_and_browse_title() -> void:
	var p := _panel()
	for r in ["xx_square", "xx_gate_e", "xw_road", "xx_gate_e"]:
		p.apply_view(_room_view(r))
	p.show_region("xixia_wild")
	assert_eq(MiniMap.BACK_TEXT, "返", "CJK back label (not ⟲)")
	assert_true(p.mini_map.back_button.visible)
	assert_true(p.mini_map.title_label.text.begins_with("瀏覽 "), p.mini_map.title_label.text)
	assert_eq(p.mini_map.status_label.text, MapPanel.MINI_BROWSE_HINT, "short footer on the mini map")
	assert_true(p.status_label.text.begins_with("瀏覽西夏郊外"), "full sentence stays on the big map")
	p.back_to_current()
	assert_false(p.mini_map.title_label.text.begins_with("瀏覽"), p.mini_map.title_label.text)

func test_world_here_label_anchored_to_own_mark() -> void:
	# 「你在這裡」要嘛離自己的記號最近，要嘛有一條引線接到自己的朱紅圈（M3c 審查：760 寬時曾貼在高昌旁邊）
	var model := MapData.world_model(view)
	for sz in [Vector2(760, 440), Vector2(1000, 470)]:
		var w := WorldMapView.new()
		_add(w)
		w.size = sz
		for r in model["regions"]:
			w.setup(model, str(r["id"]))
			var here := w.here_label()
			if here.is_empty():
				continue
			var hr: Rect2 = here["rect"]
			var d_own := WorldMapView.rect_dist(hr, (w._marks[r["id"]] as Rect2).get_center())
			var nearer := ""
			for id in w._marks:
				if id != r["id"] and WorldMapView.rect_dist(hr, (w._marks[id] as Rect2).get_center()) + 2.0 < d_own:
					nearer = str(id)
			if nearer != "":
				var lead: Array = here.get("leader", [])
				assert_eq(lead.size(), 2, "%s @ %s: label nearer to %s needs a leader line" % [r["id"], str(sz), nearer])
				if lead.size() == 2:
					var mr: Rect2 = w._marks[r["id"]]
					assert_true((lead[1] as Vector2).distance_to(mr.get_center()) <= maxf(mr.size.x, mr.size.y) * 0.75 + 6.0,
						"%s: leader ends on its own ring" % r["id"])

# ---------------------------------------------------------------- 主畫面：造型回饋、動手確認框、標籤

func _sheet() -> Dictionary:
	return { "char_id": "ch_me", "name": "我", "sect": "", "gender": "M", "appearance": 0, "in_battle": false, "enemy_of": [],
		"vitals": { "water": 50, "food": 50 }, "is_admin": false, "mail_unread": 0,
		"prefs": { "accept_challenge": true, "accept_party": true }, "party": {},
		"pending": { "party_invite": {}, "challenges": [] }, "my_corpses": [] }

func _dali_view() -> Dictionary:
	return { "room": "dl_square", "room_name": "五華樓前", "region": "dali", "region_name": "大理", "safe": true,
		"exits": [], "npcs": [], "players": [] }

func test_look_change_feedback_and_attrs_reopen() -> void:
	var ms: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	ms.gate.set_sender(func(_k, _a): return -1)
	ms.apply_sheet(_sheet())
	ms.open_panel("attributes")
	ms.open_look_dialog()
	assert_true(ms.look_dialog.visible)
	var before: int = ms.message_log.entries.size()
	ms.look_dialog.close()
	ms.handle_event({ "ch": "SYSTEM", "key": "look_changed", "ui": true,
		"p": { "look": 2, "look_name": "刀客", "shown": "look_m02", "note": "", "peer": UiClient.my_peer() } })
	assert_eq(ms.message_log.entries.size(), before + 1, "one line printed")
	assert_true(str(ms.message_log.entries.back()["bb"]).contains("你換上了刀客的打扮"), str(ms.message_log.entries.back()))
	assert_eq(ms.current_panel, "attributes", "屬性 window comes back")
	assert_true(ms.panel_frame.visible)

func test_npc_attack_confirm_title_and_cancel_label() -> void:
	var ms: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	ms.gate.set_sender(func(_k, _a): return -1)
	ms.apply_sheet(_sheet())
	ms.apply_view(_dali_view())
	ms.request_npc_attack({ "id": "n_na_dl_xiaohai", "name": "小孩", "kind": "STORY", "services": [],
		"atk": { "mode": "KILL", "category": "CHILD", "align": "GOOD", "sect": "", "menu_label": "", "via": "CTRL", "effect": "" } })
	assert_true(ms.confirm_dialog.visible)
	assert_eq(ms.confirm_dialog.title_label.text, "動手")
	assert_eq(ms.confirm_dialog.cancel_button.text, "再想想", "same words as the 滅派 confirm")
	ms.confirm_dialog.close()
	ms.ask_confirm("請出隊伍", "x", "請出", func(): pass)
	assert_eq(ms.confirm_dialog.cancel_button.text, "取消", "other confirms keep 取消")

func test_scene_tag_no_encounter_vs_safe() -> void:
	var sp := ScenePanel.new()
	_add(sp)
	await tree.process_frame
	sp.apply_sheet(_sheet())
	sp.apply_view(_dali_view())
	assert_true(sp.region_label.text.contains("無遇敵"), sp.region_label.text)
	assert_false(sp.region_label.text.contains("安全"), "a city square is not 安全 (you can still fight there)")

# ---------------------------------------------------------------- 戰鬥、背包

func test_weapon_fx_min_length_for_adjacent_target() -> void:
	var feet := Vector2(100, 200)
	var g := WeaponFx.geometry(feet, 40.0, 90.0, feet + Vector2(30, -45), 64.0)
	assert_true(float(g.length) >= 0.8 * 64.0 - 0.01, "adjacent target: at least 0.8 tile (%.1f)" % float(g.length))
	var far := WeaponFx.geometry(feet, 40.0, 90.0, feet + Vector2(600, -45), 64.0)
	assert_true(float(far.length) <= 1.6 * 64.0 + 0.01, "still capped at 1.6 tiles")

func test_inventory_glyph_detail_and_slot_names() -> void:
	assert_eq(InventoryPanel.slot_glyph("精鋼戒"), "精鋼戒", "three characters fit")
	assert_eq(InventoryPanel.slot_glyph("華陀內昭圖"), "華陀")
	for bs in InventoryPanel.BODY_SLOTS:
		var slot := str(bs["slot"])
		if slot != "WEAPON":
			assert_eq(LootUi.SLOT_NAMES[slot], str(bs["name"]), "slot name for %s matches the paper doll" % slot)
	var ip := InventoryPanel.new()
	_add(ip)
	await tree.process_frame
	var it := { "uid": "u1", "id": "a_lt_jinggangjie", "name": "精鋼戒", "n": 1, "weight": 1, "rarity": "TREASURE",
		"slot": "RING", "req_ok": true, "bonus": { "str": 3 } }
	var row := { "id": "a_lt_jinggangjie", "name": "精鋼戒", "slot": "RING", "def": 2, "weight": 1, "rarity": "TREASURE" }
	var bb: String = ip.detail_bb(it, row, -1)
	assert_eq(bb.count("珍品"), 1, "rarity shown once: " + bb)
	assert_false(bb.contains("【珍品】"), "no 【珍品】 prefix in the detail")
	assert_eq(bb.count("重量"), 1, "weight shown once")
	assert_false(bb.contains("重 1"), "no second weight in the head line")

func test_req_text_never_shows_type_codes() -> void:
	var t := LootUi.req_text_of({ "requires": [{ "type": "attr_min", "attr": "wit", "value": 25 }, { "type": "gender", "value": "F" }] })
	assert_false(t.contains("attr_min"), t)
	assert_true(t.contains("限女性"), t)
	var t2 := LootUi.req_text_of({ "requires": [{ "type": "zz_unknown" }] })
	assert_false(t2.contains("zz_unknown"), t2)

## 結束時排在後面的武器特效拉到現在（依序隔 0.08 秒），結果框等它播完（最多 0.6 秒）
func test_weapon_fx_compressed_at_battle_end() -> void:
	var fx := BattleFx.new()
	var now := BattleIsoView.now_s()
	fx.items.append({ "type": "weapon", "sprite": null, "target": null, "kind": "blade", "miss": false, "start": now + 1.2, "dur": WeaponFx.DUR })
	fx.items.append({ "type": "weapon", "sprite": null, "target": null, "kind": "fist", "miss": false, "start": now + 0.9, "dur": WeaponFx.DUR })
	fx.compress_weapon_fx()
	var starts: Array = fx.items.map(func(it): return float(it["start"]) - now)
	assert_true(starts.max() < 0.2, "pulled to now: %s" % str(starts))
	assert_true(float(fx.items[1]["start"]) < float(fx.items[0]["start"]), "order kept (fist first)")
	var left: float = fx.weapon_fx_left()
	assert_true(left > 0.2 and left < 0.6, "result waits about one effect: %.2f" % left)
	fx.free()
