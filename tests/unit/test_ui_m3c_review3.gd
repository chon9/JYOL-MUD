extends "res://tests/test_case.gd"
## M3c 審查（第三輪，介面）回歸：
## 1. 刀特效身後的白色箭頭＝「輪到我」的雙線菱形畫在 VM 的格子（前衝／走路動畫還沒播完時在身體後面）→ 只在靜止時畫、畫在人物的格子
## 3. 結果框「得到：」一件一件整件換行（不會只剩「×1」在下一行）
## 4. 出招時腰間氣值小條畫在特效上面、底板變淡
## 5. 江湖全圖「你在這裡」不指著自己的地名、不擠在別的地名旁邊
## 6. 小地圖邊緣被切到的房間不寫房名（is_clipped）
## 7. 打贏之後等續走時寫「戰鬥結束，稍後繼續趕路。」

const FX := preload("res://tests/unit/test_m3c_weapon_fx.gd")

var loader: DataLoader
var view: Dictionary
var _nodes: Array = []
var _dir := ""
var _seq := 3900

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	if loader == null:
		loader = DataLoader.new()
		loader.load_all("res://data")
		view = loader.activate(["1.0A"])
	_dir = temp_dir("m3c_review3")
	MapArt.use_textures(null)

func after_each() -> void:
	MapArt.use_textures(null)
	WeaponFx.override_texture("", null)
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

func _battle() -> BattleIsoView:
	var v := BattleIsoView.new()
	_add(v)
	v.size = Vector2(1280, 720)
	v.set_vm(BattleViewModel.from_state(FX._state()))
	return v

func _send(v: BattleIsoView, key: String, p: Dictionary) -> void:
	var e := FX._ev(key, p)
	v.vm.apply_event(e)
	v.on_event(e)

# ---------------------------------------------------------------- 1：輪到我的菱形
func test_my_turn_ring_only_at_rest_and_under_the_figure() -> void:
	var v := _battle()
	await tree.process_frame
	_send(v, "battle_await", { "units": [1], "deadline_tick": 999999 })
	await tree.process_frame
	var me: UnitSprite = v.sprites[1]
	assert_true(v.my_turn_ring_visible(), "my turn, standing still: ring drawn")
	assert_true(v.my_turn_ring_center().distance_to(v.grid_to_local(me.gpos)) < 0.01)
	# 出招前衝中（動畫鎖住）：不畫——以前畫在 VM 的格子，人物衝出去之後只露出兩個角
	_send(v, "atk_blade", { "atk_uid": 1, "def_uid": 2, "dmg": 5, "def_qi": 55 })
	assert_true(me.locked_until > BattleIsoView.now_s(), "the lunge holds the sprite")
	assert_false(v.my_turn_ring_visible(), "no ring while my figure is animating")
	# 走路動畫還沒走到（人物的格子 ≠ VM 的格子）：畫在人物現在的格子
	me.locked_until = 0.0
	me.anim_offset = Vector2.ZERO
	me.gpos = Vector2(4, 3)
	assert_true(v.my_turn_ring_center().distance_to(v.grid_to_local(Vector2(4, 3))) < 0.01, "ring follows the figure, not the VM cell")

# ---------------------------------------------------------------- 3：結果框的「得到：」整件換行
func test_loot_line_wraps_whole_items() -> void:
	var font := ThemeDB.fallback_font
	var items := [
		{ "id": "c_jinchuang", "name": "金創藥", "n": 1, "rarity": "COMMON" },
		{ "id": "w_dandao", "name": "單刀", "n": 1, "rarity": "COMMON" },
		{ "id": "a_lt_jinggangjie", "name": "精鋼戒", "n": 1, "rarity": "TREASURE" },
		{ "id": "w_lt_zijinbaguadao", "name": "紫金八卦刀", "n": 2, "rarity": "RARE" } ]
	assert_false(BattleScreen.loot_line_bb(items).contains("\n"), "no font: one line, autowrap decides")
	for w in [140.0, 200.0, 260.0, 336.0]:
		var bb := BattleScreen.loot_line_bb(items, font, 16, w)
		var lines := bb.split("\n")
		var plain_total := 0
		for ln in lines:
			var t := ln
			# 去掉 BBCode 看純文字
			var re := RegEx.create_from_string("\\[/?color[^\\]]*\\]")
			t = re.sub(t, "", true)
			assert_false(t.strip_edges().begins_with("×"), "@%d a line starts with ×: %s" % [w, t])
			plain_total += t.count("×")
			if lines.size() > 1 and ln != lines[0]:
				assert_true(font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x <= maxf(w, font.get_string_size(t.trim_suffix("、"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x) + 0.5,
					"@%d line fits or is a single item: %s" % [w, t])
		assert_eq(plain_total, 4, "every item once @%d" % w)
	assert_true(BattleScreen.loot_line_bb(items, font, 16, 140.0).count("\n") >= 2, "narrow box: several lines")

func test_battle_screen_result_uses_packed_loot_line() -> void:
	var Scenes := load("res://tests/unit/test_ui_scenes.gd")
	var bs = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	bs.setup(Scenes._battle_state())
	bs.show_result({ "bid": 3, "result": "VICTORY", "you_died": false, "death": {},
		"rewards": { "combat_xp": 30, "learn_points": 5, "money": 0, "items": [
			{ "id": "c_jinchuang", "name": "金創藥", "n": 1, "rarity": "COMMON" },
			{ "id": "w_dandao", "name": "單刀", "n": 1, "rarity": "COMMON" },
			{ "id": "a_lt_jinggangjie", "name": "精鋼戒", "n": 1, "rarity": "TREASURE" } ] } })
	var parsed: String = bs.result_detail.get_parsed_text()
	for ln in parsed.split("\n"):
		assert_false(ln.strip_edges() == "×1", "a lone ×1 line: %s" % parsed)
	assert_true(parsed.contains("精鋼戒 ×1"), parsed)

# ---------------------------------------------------------------- 4：氣值小條在特效上面、底板變淡
func test_hp_pill_plate_fades_while_striking() -> void:
	var v := _battle()
	await tree.process_frame
	var me: UnitSprite = v.sprites[1]
	var wolf: UnitSprite = v.sprites[2]
	var now := BattleIsoView.now_s()
	v.fx.weapon(me, wolf, "blade", WeaponFx.LEAD)
	assert_has(v.fx.weapon_fx_sprites(now + WeaponFx.FADE_IN), me, "the striker is listed while the fx shows")
	assert_false(v.fx.weapon_fx_sprites(now + WeaponFx.FADE_IN).has(wolf))
	assert_true(v.fx.weapon_fx_sprites(now + WeaponFx.DUR + 0.2).is_empty(), "not after the fx")
	assert_true(BattleFx.WEAPON_HP_PLATE < 0.5)
	var src := FileAccess.get_file_as_string("res://ui/game/battle/battle_fx.gd")
	assert_true(src.find("_draw_weapon_fx(now)") < src.find("draw_hp_text(self"), "the HP pill is drawn after (over) the weapon fx")

# ---------------------------------------------------------------- 5：江湖全圖「你在這裡」
func test_here_label_not_pointing_at_own_name_in_cities() -> void:
	var model := MapData.world_model(view)
	for sz in [Vector2(880, 395), Vector2(900, 440), Vector2(880, 390), Vector2(1000, 470)]:
		var w := WorldMapView.new()
		_add(w)
		w.size = sz
		for rid in ["xixia", "dali"]:
			w.setup(model, rid)
			var here := w.here_label()
			assert_false(here.is_empty())
			var hr: Rect2 = here["rect"]
			var mark: Rect2 = w._marks[rid]
			var p: float = w.here_style_penalty(hr, str(here["text"]), mark)
			print("  here %s @ %s: %s「%s」mark %s penalty %.1f" % [rid, str(sz), str(hr), str(here["text"]), str(mark), p])
			if WorldMapView.rect_dist(hr, mark.get_center()) > WorldMapView.HERE_FAR:
				assert_eq(str(here["text"]), WorldMapView.HERE_PLAIN, "far from the mark: no arrow pointing elsewhere")
				assert_eq((here.get("leader", []) as Array).size(), 2, "far label has a leader to the ring")
			assert_true(p < 2.0, "%s @ %s: 你在這裡 %s「%s」crowds a name or points at its own name (penalty %.1f)" % [rid, str(sz), str(hr), str(here["text"]), p])
	# 規則本身：▶ 指著自己的地名（地名夾在標籤與記號之間）要扣分
	var w2 := WorldMapView.new()
	_add(w2)
	w2.size = Vector2(900, 440)
	w2.setup(model, "xixia")
	w2.here_label()
	var own: Rect2 = w2._labels["xixia"]
	var mk: Rect2 = w2._marks["xixia"]
	if own.end.x <= mk.position.x + 1.0:
		var bad := Rect2(Vector2(own.position.x - 70.0, own.position.y), Vector2(66, 16))
		assert_true(w2.here_style_penalty(bad, "你在這裡 ▶", mk) >= 3.0, "▶ at its own name is penalised")

# ---------------------------------------------------------------- 6：小地圖邊緣
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
	p.apply_sheet({ "char_id": "ch_review3", "vitals": { "qi": 100, "qi_max": 100, "food": 90, "water": 90 } })
	return p

func test_minimap_clipped_rooms_are_detected() -> void:
	var p := _panel()
	for r in ["xx_square", "xx_gate_e", "xx_square", "xx_inn", "xx_square", "xx_street", "xx_square"]:
		if MapData.room_index(view).has(r):
			p.apply_view(_room_view(r))
	await tree.process_frame
	await tree.process_frame
	var mv: RegionMapView = p.mini_map.view
	var full := Rect2(Vector2.ZERO, mv.size).grow(1.0)
	var n_clipped := 0
	for id in mv._rects:
		if not mv.is_shown(str(id)):
			continue
		var inside := full.encloses(mv.screen_rect(str(id)))
		assert_eq(mv.is_clipped(str(id)), not inside, "%s clipped flag" % str(id))
		if not inside:
			n_clipped += 1
	assert_false(mv.is_clipped(mv.current), "the current room is never clipped")
	for id in p.region_view._rects:
		assert_false(p.region_view.is_clipped(str(id)), "the big map never fades rooms")
	print("  minimap clipped rooms: %d" % n_clipped)

# ---------------------------------------------------------------- 7：打贏之後等續走
func test_resume_wait_text_after_a_won_fight() -> void:
	var w := AutoWalker.new()
	_add(w)
	var texts: Array = []
	w.state_changed.connect(func(_on: bool, t: String): texts.append(t))
	w.phase = "delay"
	w.on_battle()
	assert_eq(w.last_text, AutoWalker.PAUSE_TEXT)
	w.on_battle_end("VICTORY", true)
	assert_eq(w.last_text, AutoWalker.RESUME_WAIT_TEXT, "fight over: not「遇敵交戰中」any more")
	w.phase = "battle"
	w.last_text = AutoWalker.PAUSE_TEXT
	w.on_battle_end("VICTORY", false)
	assert_eq(w.last_text, AutoWalker.PAUSE_TEXT, "no resume → the stop reason comes from the core, not the wait text")
	w.phase = ""
