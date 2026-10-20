extends "res://tests/test_case.gd"
## 回歸（WORLD_2001 介面審查 round 4）：戰報／系統訊息框只露整行並捲到最新、結果小條出來後不留飄字、
## 「取消選擇」只在選擇中出現、腰部氣跟 HUD 一致、名字牌有深色底、指令窗方鈕填滿黑框、江湖全圖的洞窟有自己的路、
## 小地圖放得下目前房間與相鄰一圈。

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

## 可視區剛好是整數行、而且最後一行在最底
func _assert_whole_lines(rtl: RichTextLabel, what: String) -> void:
	var sb := rtl.get_theme_stylebox("normal")
	var top := sb.get_margin(SIDE_TOP)
	var page := rtl.size.y - top - sb.get_margin(SIDE_BOTTOM)
	var h := float(rtl.get_content_height())
	assert_true(h > page, "%s: content taller than the box (%s > %s)" % [what, h, page])
	var bar := rtl.get_v_scroll_bar()
	var v := bar.value
	assert_true(absf(v + page - h) < 1.0, "%s: scrolled to the newest line (%s + %s vs %s)" % [what, v, page, h])
	var on_line := false
	for i in rtl.get_line_count():
		if absf(float(rtl.get_line_offset(i)) - v) < 1.0:
			on_line = true
			break
	assert_true(on_line, "%s: top of the box starts on a whole line (scroll %s)" % [what, v])

# ---------------------------------------------------------------- 1. 戰報 / 5. 系統訊息框

func test_battle_log_scrolls_to_the_newest_whole_line() -> void:
	var bs: BattleScreen = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	bs.size = Vector2(1280, 552)
	await _frames(1)
	bs.setup(STATE_SCRIPT.state())
	for i in 40:
		bs._log_plain("第 %d 行戰報：大野兔猛地一撲，「撲咬」咬中你的頭頂！（-10）" % i)
	await _frames(3)
	_assert_whole_lines(bs.log_text, "battle log")

func test_hud_message_box_shows_whole_lines() -> void:
	var ml := MessageLog.new()
	_add(ml)
	var host := VBoxContainer.new()
	host.size = Vector2(380, 110)
	_add(host)
	ml.build_announce(host)
	host.size = Vector2(380, 110)
	for i in 6:
		ml.add_announcement("【任務】第 %d 則：驛站在五華樓前廣場的西邊。大漠一帶有野狼、山豬，新手別硬拼，一開打就往白框「逃」字的逃跑格跑。" % i, false)
	await _frames(4)
	_assert_whole_lines(ml.announce, "HUD message box")

# ---------------------------------------------------------------- 3. 飄字 / 10. 取消選擇

func test_result_strip_clears_popups_and_cancel_only_while_selecting() -> void:
	var bs: BattleScreen = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	bs.size = Vector2(1280, 552)
	await _frames(1)
	bs.setup(STATE_SCRIPT.state())
	await _frames(1)
	assert_false(bs.cancel_button.visible, "蓄勢中 nothing selected: no 取消選擇")
	bs.apply_event({ "ch": "BATTLE", "key": "battle_await", "bid": 3, "ui": true, "p": { "units": [1], "deadline_tick": 400 } })
	bs._process(0.016)
	assert_false(bs.cancel_button.visible, "my turn but nothing selected: no 取消選擇")
	bs._on_command(UiKeys.CMD_MOVE)
	bs._process(0.016)
	assert_true(bs.cancel_button.visible and not bs.cancel_button.disabled, "move selected: 取消選擇 shown")
	bs.cancel_mode()
	bs._process(0.016)
	assert_false(bs.cancel_button.visible)
	var s: UnitSprite = bs.grid_view.sprites[2]
	bs.grid_view.fx.popup(s, "-19", BattleFx.DMG_COLOR, 1.0, 0.0)
	bs.grid_view.fx.popup(s, "閃", BattleFx.MISS_COLOR, 1.0, 0.0)
	bs.show_result({ "bid": 3, "result": "VICTORY", "rewards": { "combat_xp": 12 } })
	var texts := bs.grid_view.fx.items.filter(func(it): return str(it["type"]) == "text")
	assert_eq(texts.size(), 0, "no damage numbers left under the result strip")
	bs.grid_view.fx.popup(s, "-5", BattleFx.DMG_COLOR, 1.0, 0.0)
	assert_eq(bs.grid_view.fx.items.filter(func(it): return str(it["type"]) == "text").size(), 0, "late events do not float numbers")

# ---------------------------------------------------------------- 4. 腰部氣 / 2. 名字牌

func test_waist_hp_follows_the_host_value() -> void:
	var bs: BattleScreen = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	bs.size = Vector2(1280, 552)
	await _frames(1)
	bs.setup(STATE_SCRIPT.state())
	await _frames(1)
	var me: UnitSprite = bs.grid_view.sprites[1]
	# 兩下連擊：第二下的動畫還在排隊（shown_qi 停在第一下），字要跟主機（HUD）一致
	bs.apply_event({ "ch": "BATTLE", "key": "battle_hit", "bid": 3, "p": { "atk_uid": 2, "def_uid": 1, "dmg": 10, "def_qi": 170 } })
	bs.apply_event({ "ch": "BATTLE", "key": "battle_hit", "bid": 3, "p": { "atk_uid": 2, "def_uid": 1, "dmg": 13, "def_qi": 157 } })
	await _frames(2)
	var host_qi := int(bs.vm.unit(1).get("qi", 0))
	assert_eq(me.hp_text(), "%d/%d" % [host_qi, 180], "waist text matches the host qi")

func test_unit_names_have_a_dark_backing() -> void:
	# 名字牌底色不透明度夠（亮沙地上看得清）；損血字是亮色
	assert_true(UnitSprite.NAME_PLATE.a >= 0.6)
	assert_true(UnitSprite.HP_PLATE.a >= 0.8)
	assert_true(UnitSprite.HP_INK.get_luminance() > 0.6, "HP text is bright on its dark plate")

# ---------------------------------------------------------------- 7. 神條

func test_shen_value_has_a_heavy_outline() -> void:
	var sb := StatusBar.new()
	_add(sb)
	await _frames(1)
	var t: Label = sb.bar_texts["shen"]
	assert_true(t.get_theme_constant("outline_size") >= 5, "神 value outlined")
	assert_true(t.get_theme_color("font_outline_color").a >= 0.99)

# ---------------------------------------------------------------- 11. 指令窗

func test_command_grid_fills_the_frame() -> void:
	var holder := VBoxContainer.new()
	holder.size = Vector2(506, 300)
	_add(holder)
	var cp := CommandPanel.new()
	cp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(cp)
	await _frames(4)
	var sb := cp.frame.get_theme_stylebox("panel")
	var inner := cp.frame.size.x - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT)
	assert_true(cp.btn_size.x > CommandPanel.BTN.x, "buttons grew: %s" % cp.btn_size)
	assert_true(inner - cp.grid.size.x < CommandPanel.COLS + 1.0 or cp.btn_size.x >= CommandPanel.BTN_MAX,
		"grid fills the frame width: %s of %s" % [cp.grid.size.x, inner])

# ---------------------------------------------------------------- 12. 江湖全圖

func test_dungeon_mark_keeps_clear_of_other_roads() -> void:
	var loader := DataLoader.new()
	loader.load_all("res://data")
	var view := loader.activate(["1.0A"])
	for sz in [Vector2(880, 400), Vector2(1190, 430), Vector2(1600, 800)]:
		var w := WorldMapView.new()
		_add(w)
		w.size = sz
		w.setup(MapData.world_model(view), "xixia")
		w.routes()
		var gw: Vector2 = w.center_of("guiwang")
		var has_road := false
		for pr in w.model.get("walk", []):
			if "guiwang" in pr:
				has_road = true
				continue
			var q := Geometry2D.get_closest_point_to_segment(gw, w.center_of(pr[0]), w.center_of(pr[1]))
			assert_true(gw.distance_to(q) >= 8.0 + WorldMapView.ROAD_CLEAR - 0.5, "%s: 血刀洞迷宮 clear of road %s" % [str(sz), str(pr)])
		assert_true(has_road, "血刀洞迷宮 has its own road")

# ---------------------------------------------------------------- 8. 小地圖

func test_mini_map_fits_the_neighbourhood() -> void:
	var loader := DataLoader.new()
	loader.load_all("res://data")
	var tables := loader.activate(["1.0A"])
	var mm := MiniMap.new()
	_add(mm)
	mm.size = Vector2(264, 228)
	await _frames(1)
	for c in [["xixia", "xx_square", ["xx_inn", "xx_square", "xx_station", "xx_street"]],
			["dali", "dl_station", ["dl_station", "dl_square", "dl_gate_n"]]]:
		var model := MapData.region_model(tables, c[0])
		var known := {}
		for id in c[2]:
			known[id] = true
		if not (model.get("pos", {}) as Dictionary).has(c[1]):
			continue
		mm.show_region(tables, model, known, c[1], c[0], "")
		await _frames(2)
		var vr := Rect2(Vector2.ZERO, mm.view.size)
		var nb := mm.view.neighbourhood_box()
		var nb_screen := Rect2((nb.position + mm.view._offset) * mm.view.zoom, nb.size * mm.view.zoom)
		assert_true(vr.grow(0.5).encloses(nb_screen), "%s: neighbourhood %s inside %s (zoom %s)" % [c[1], str(nb_screen), str(vr), mm.view.zoom])
		assert_true(mm.view.name_size() * mm.view.zoom >= 10.0, "names still readable")
