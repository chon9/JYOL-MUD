extends "res://tests/test_case.gd"
## 等角戰場（BattleIsoView）：投影來回、菱形點選、邊界、置中縮放、前後排序、事件動畫不阻擋回合

const STATE_SCRIPT := preload("res://tests/unit/test_ui_battle_view_model.gd")

var _nodes: Array = []

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

func _view(sz: Vector2) -> BattleIsoView:
	var v := BattleIsoView.new()
	tree.root.add_child(v)
	_nodes.append(v)
	v.size = sz
	v.set_vm(BattleViewModel.from_state(STATE_SCRIPT.state()))
	return v

func test_projection_round_trip_every_cell() -> void:
	for sz in [Vector2(1280, 720), Vector2(1920, 1032), Vector2(900, 560), Vector2(500, 320)]:
		var v := _view(sz)
		var bad := 0
		for y in 8:
			for x in 12:
				var c := Vector2i(x, y)
				if v.cell_at(v.cell_center(c)) != c:
					bad += 1
		assert_eq(bad, 0, "every cell center maps back at %s" % str(sz))

func test_diamond_hit_test_edges() -> void:
	var v := _view(Vector2(1280, 720))
	var tw := v.tile_w
	var c := Vector2i(5, 3)
	var p := v.cell_center(c)
	# 菱形頂點內側一點點仍屬同格，外側一點點屬鄰格
	assert_eq(v.cell_at(p + Vector2(tw / 2.0 - 2.0, 0)), c, "near right corner inside")
	assert_eq(v.cell_at(p + Vector2(0, tw / 4.0 - 1.5)), c, "near bottom corner inside")
	assert_eq(v.cell_at(p + Vector2(tw / 4.0 + 2.0, tw / 8.0 + 2.0)), Vector2i(6, 3), "past lower-right edge = x+1")
	assert_eq(v.cell_at(p + Vector2(-tw / 4.0 - 2.0, tw / 8.0 + 2.0)), Vector2i(5, 4), "past lower-left edge = y+1")
	assert_eq(v.cell_at(p + Vector2(tw / 4.0 + 2.0, -tw / 8.0 - 2.0)), Vector2i(5, 2), "past upper-right edge = y-1")
	assert_eq(v.cell_at(p + Vector2(-tw / 4.0 - 2.0, -tw / 8.0 - 2.0)), Vector2i(4, 3), "past upper-left edge = x-1")

func test_out_of_bounds() -> void:
	var v := _view(Vector2(1280, 720))
	assert_eq(v.cell_at(Vector2(2, 2)), Vector2i(-1, -1), "top-left corner of the rect is outside the diamond")
	assert_eq(v.cell_at(Vector2(1278, 718)), Vector2i(-1, -1))
	var tw := v.tile_w
	assert_eq(v.cell_at(v.cell_center(Vector2i(0, 0)) + Vector2(0, -tw / 4.0 - 3.0)), Vector2i(-1, -1), "above the top cell")
	assert_eq(v.cell_at(v.cell_center(Vector2i(11, 0)) + Vector2(tw / 2.0 + 3.0, 0)), Vector2i(-1, -1), "right of the right corner")
	assert_eq(v.cell_at(v.cell_center(Vector2i(0, 7)) + Vector2(-tw / 2.0 - 3.0, 0)), Vector2i(-1, -1), "left of the left corner")
	assert_eq(v.cell_at(v.cell_center(Vector2i(11, 7)) + Vector2(0, tw / 4.0 + 3.0)), Vector2i(-1, -1), "below the bottom cell")
	for c in [Vector2i(0, 0), Vector2i(11, 0), Vector2i(0, 7), Vector2i(11, 7)]:
		assert_eq(v.cell_at(v.cell_center(c)), c, "corner cell %s" % str(c))

func test_fit_centered_and_inside() -> void:
	for sz in [Vector2(1280, 720), Vector2(1920, 1032), Vector2(700, 600)]:
		var v := _view(sz)
		var left := v.grid_to_local(Vector2(-0.5, 7.5)).x
		var right := v.grid_to_local(Vector2(11.5, -0.5)).x
		var top := v.grid_to_local(Vector2(-0.5, -0.5)).y
		var bottom := v.grid_to_local(Vector2(11.5, 7.5)).y
		assert_true(left >= 0.0 and right <= sz.x, "grid fits horizontally at %s" % str(sz))
		assert_true(top - BattleIsoView.HEAD_ROOM * v.tile_w >= -0.5 and bottom <= sz.y, "grid + head room fits vertically at %s" % str(sz))
		assert_true(absf((left + right) / 2.0 - sz.x / 2.0) < 1.0, "centered horizontally")
		assert_true(is_equal_approx(bottom - top, (right - left) / 2.0), "2:1 diamond")
	var small := BattleIsoView.fit(Vector2(1280, 720), 12, 8)
	var big := BattleIsoView.fit(Vector2(1920, 1032), 12, 8)
	assert_true(float(big["tile_w"]) > float(small["tile_w"]), "scales up with the window")

func test_project_unproject_inverse() -> void:
	var org := Vector2(300, 120)
	for g in [Vector2(0, 0), Vector2(3.25, 1.5), Vector2(11, 7), Vector2(-0.5, 7.5)]:
		var back := BattleIsoView.unproject(BattleIsoView.project(g, org, 77.0), org, 77.0)
		assert_true(back.distance_to(g) < 0.0001, "round trip %s" % str(g))

func test_depth_sort_by_x_plus_y() -> void:
	var order := BattleIsoView.depth_order({ 1: Vector2(5, 5), 2: Vector2(0, 0), 3: Vector2(3, 1), 4: Vector2(1, 2), 5: Vector2(11, 7) })
	assert_eq(order, [2, 4, 3, 1, 5], "far (small x+y) first, ties by y")
	# 倒下的單位畫在同深度活人的後面（先畫）
	var o2 := BattleIsoView.depth_order({ 1: Vector2(2, 2), 2: Vector2(2, 2) }, { 1: false, 2: true })
	assert_eq(o2, [2, 1])
	# 移動中的連續座標也能排
	var o3 := BattleIsoView.depth_order({ 1: Vector2(2.6, 2), 2: Vector2(2, 2.4) })
	assert_eq(o3, [2, 1])
	# 屍體是地面的一部分：前一格的屍體也先畫，不會蓋到後一格活人的腳與氣條
	var o4 := BattleIsoView.depth_order({ 1: Vector2(2, 2), 2: Vector2(3, 2) }, { 1: false, 2: true })
	assert_eq(o4, [2, 1])

func test_sprites_depth_z_and_facing() -> void:
	var v := _view(Vector2(1280, 720))
	await tree.process_frame
	assert_eq(v.sprites.size(), 2)
	var me: UnitSprite = v.sprites[1]
	var foe: UnitSprite = v.sprites[2]
	# 我在 (1,3)、野兔在 (10,3)：x+y 較大的野兔在前面
	assert_true(foe.depth > me.depth, "nearer unit drawn on top")
	assert_true(foe.get_index() > me.get_index(), "draw order follows depth (tree order)")
	assert_eq(foe.z_index, 0, "no z_index: popups over the battlefield must stay on top")
	assert_eq(v.fx.z_index, 0)
	assert_true(me.facing_right, "player faces the enemy on the right")
	assert_false(foe.facing_right, "enemy faces left (art default)")
	assert_eq(me.display_name, "測試俠客", "full name, no truncation")
	assert_true(me.position.distance_to(v.cell_center(Vector2i(1, 3))) < 0.01, "feet on cell center")
	assert_eq(foe.shape, "hare", "placeholder silhouette by kind")

func test_events_animate_without_blocking() -> void:
	var v := _view(Vector2(1280, 720))
	var vm := v.vm
	var ev := func(key: String, p: Dictionary) -> Dictionary:
		var e := { "ch": "BATTLE", "key": key, "bid": 3, "p": p }
		vm.apply_event(e)
		v.on_event(e)
		return e
	ev.call("battle_move", { "uid": 1, "from": [1, 3], "to": [3, 3] })
	var me: UnitSprite = v.sprites[1]
	assert_eq(me.gpos, Vector2(1, 3), "move starts from the old cell")
	assert_eq(vm.unit(1)["pos"], Vector2i(3, 3), "VM already authoritative")
	ev.call("atk_fist", { "atk_uid": 2, "def_uid": 1, "dmg": 12, "crit": true, "def_qi": 168 })
	ev.call("battle_miss", { "atk_uid": 1, "def_uid": 2 })
	ev.call("battle_defend", { "uid": 1 })
	ev.call("battle_rest", { "uid": 1, "qi_gain": 5, "qi": 173 })
	ev.call("battle_kill", { "uid": 2 })
	assert_true(v.fx.items.size() >= 4, "damage / miss / shield / rest popups queued")
	# 輪到我：VM 立刻可下令，動畫不影響
	vm.apply_event({ "ch": "BATTLE", "key": "battle_await", "bid": 3, "p": { "units": [1], "deadline_tick": 200 } })
	assert_true(vm.is_my_turn(0.0), "animations never gate the turn")
	# 排隊超過上限的動畫會被丟掉，不會無限落後
	assert_true(me.ready_at - BattleIsoView.now_s() <= BattleIsoView.MAX_BACKLOG + 1.5, "backlog bounded")
	for i in 90:
		await tree.process_frame
	await tree.create_timer(2.5).timeout
	await tree.process_frame
	assert_eq(me.gpos, Vector2(3, 3), "ends on the authoritative cell")
	assert_eq((v.sprites[2] as UnitSprite).vis_state, "DEAD", "killed unit lies down")
	assert_eq(me.shown_qi, 173)

func test_path_between_avoids_units() -> void:
	var v := _view(Vector2(1280, 720))
	var p := v.path_between(Vector2i(1, 3), Vector2i(3, 3), 1)
	assert_eq(p, [Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)])
	# 野兔擋在 (10,3)：繞過去
	var p2 := v.path_between(Vector2i(9, 3), Vector2i(11, 3), 1)
	assert_eq(p2.size(), 5, "detour around the blocking unit")
	assert_false(p2.has(Vector2i(10, 3)))

func test_art_lookup_uses_registry_refs() -> void:
	assert_eq(BattleIsoView.unit_ref({ "kind": "MONSTER", "name": "野兔甲", "ref": "m_rabbit" }), "m_rabbit")
	assert_eq(BattleIsoView.unit_ref({ "kind": "PLAYER", "name": "測試俠客", "look": "shaolin_m" }), "shaolin_m")
	assert_eq(BattleIsoView.unit_ref({ "kind": "PLAYER", "name": "測試俠客" }), "player_m", "old snapshot: player fallback")
	# 舊快照沒有 ref：用名字對回資料表（取最長前綴：大野兔不是野兔）
	assert_eq(BattleIsoView.unit_ref({ "kind": "MONSTER", "name": "大野兔乙" }), "m_bigrabbit")
	assert_eq(BattleIsoView.unit_ref({ "kind": "MONSTER", "name": "野兔" }), "m_rabbit")
	var d := BattleIsoView.unit_display({ "kind": "MONSTER", "ref": "m_rabbit" })
	assert_true(float(d.get("scale", 0.0)) > 0.0, "display scale from art.json")

func test_names_never_truncated_and_no_tokens() -> void:
	var v := _view(Vector2(1280, 720))
	var st := STATE_SCRIPT.state()
	st["units"][0]["name"] = "張靜安"
	v.set_vm(BattleViewModel.from_state(st))
	var s: UnitSprite = v.sprites[1]
	assert_eq(s.display_name, "張靜安")
	assert_true(s.figure_height() > v.tile_w, "a standing figure, not a flat token")

func test_name_plates_never_overlap_when_units_meet() -> void:
	var v := _view(Vector2(1280, 720))
	var vm := v.vm
	# 野兔走到我旁邊（同一格前後相鄰），名字牌要分開
	vm.units[2]["pos"] = Vector2i(2, 3)
	await tree.process_frame
	await tree.process_frame
	var me: UnitSprite = v.sprites[1]
	var foe: UnitSprite = v.sprites[2]
	BattleFx.layout_names([me, foe])
	assert_true(me.name_box.size.x > 0.0 and foe.name_box.size.x > 0.0, "both plates laid out")
	assert_false(me.name_box.intersects(foe.name_box), "name plates pushed apart")
	# 疊在同一格（動畫中）也一樣
	foe.gpos = me.gpos
	foe.position = me.position
	BattleFx.layout_names([me, foe])
	assert_false(me.name_box.intersects(foe.name_box), "even on the same spot")

func test_lunge_stops_short_and_settle_lays_dead_down() -> void:
	var v := _view(Vector2(1280, 720))
	var vm := v.vm
	vm.units[2]["pos"] = Vector2i(2, 3)
	await tree.process_frame
	var me: UnitSprite = v.sprites[1]
	var foe: UnitSprite = v.sprites[2]
	var e := { "ch": "BATTLE", "key": "atk_fist", "bid": 3, "p": { "atk_uid": 1, "def_uid": 2, "dmg": 5, "def_qi": 10 } }
	vm.apply_event(e)
	v.on_event(e)
	var gap := v.cell_center(Vector2i(2, 3)).distance_to(v.cell_center(Vector2i(1, 3)))
	var peak := 0.0
	for i in 30:
		await tree.process_frame
		peak = maxf(peak, me.anim_offset.length())
	assert_true(peak > 1.0 and peak <= gap * BattleIsoView.LUNGE_REACH + 0.5, "lunge stops at the cell edge (%.1f of %.1f)" % [peak, gap])
	# 戰鬥結束：已倒地的人立刻躺下、名字變灰、不畫氣條
	vm.units[2]["state"] = "DEAD"
	foe.locked_until = BattleIsoView.now_s() + 10.0
	v.settle()
	assert_eq(foe.vis_state, "DEAD")
	assert_eq(foe.lie, 1.0)
	assert_eq(foe.anim_offset, Vector2.ZERO, "back on its own cell")

func test_idle_units_turn_to_face_nearest_enemy() -> void:
	var v := _view(Vector2(1280, 720))
	var vm := v.vm
	await tree.process_frame
	var me: UnitSprite = v.sprites[1]
	assert_true(me.facing_right, "enemy starts on the right")
	# 敵人繞到左邊（螢幕 x 較小）：閒著的我要轉過去，不能背對牠
	vm.units[2]["pos"] = Vector2i(0, 6)
	await tree.process_frame
	await tree.process_frame
	assert_false(me.facing_right, "player turns to face an enemy on the left")
	assert_true((v.sprites[2] as UnitSprite).facing_right, "enemy faces back toward the player")

func test_dead_body_lies_on_its_own_cell() -> void:
	var v := _view(Vector2(1280, 720))
	var vm := v.vm
	vm.units[1]["state"] = "DEAD"
	v.settle()
	await tree.process_frame
	var me: UnitSprite = v.sprites[1]
	assert_eq(me.lie, 1.0)
	# 躺下後頭頂高度很低、名字牌貼著屍體（不是浮在原本站著的頭頂高度）
	assert_true(me.body_top() < me.head_height() * 0.5, "lying body is low")
	var box := me.default_name_box(me.position)
	assert_true(me.position.y - box.end.y < me.head_height() * 0.5, "dead plate stays near the corpse")

## AUTHENTIC_UI_SPEC §12.1：時間棒（綠）與氣條（紅）在名字下面（不在腳下），名字牌框把兩條算進去，
## 相鄰兩人的名字牌（含兩條）互不重疊；倒下的沒有兩條，名字後面加「倒下」
func test_time_and_qi_bars_sit_under_the_name() -> void:
	var v := _view(Vector2(1280, 720))
	var vm := v.vm
	vm.units[2]["pos"] = Vector2i(1, 4)   # 螢幕上在我的左下，水平只差半格寬
	await tree.process_frame
	await tree.process_frame
	var me: UnitSprite = v.sprites[1]
	var foe: UnitSprite = v.sprites[2]
	assert_eq(me.bar_rect(me.position), Rect2(), "no bars at the feet any more")
	assert_true(me.bars_h() > 0.0, "alive: bars under the name")
	var box := me.default_name_box(me.position)
	assert_true(box.size.y >= me.name_font_size() + me.bars_h(), "name box includes the two bars")
	assert_false(me.name_box.intersects(foe.name_box), "neighbouring name plates (with bars) do not overlap")
	assert_eq(me.label_text(), me.display_name)
	vm.units[2]["state"] = "DEAD"
	v.settle()
	assert_eq(foe.bars_h(), 0.0, "dead: no bars")
	assert_eq(foe.label_text(), foe.display_name + UnitSprite.DOWN_SUFFIX, "dead units say 倒下")

## 回歸（審查：玩家的屍體被敵人蓋住看不到）：屍體一律先畫；有活人站在屍體那一格時屍體往前挪；
## 擋到我方屍體的活人變半透明
func test_corpse_stays_visible_under_a_standing_enemy() -> void:
	var v := _view(Vector2(1280, 720))
	var vm := v.vm
	vm.units[1]["state"] = "DEAD"
	vm.units[2]["pos"] = vm.units[1]["pos"]   # 敵人踩在我的屍體上
	v.settle()
	await tree.process_frame
	await tree.process_frame
	var me: UnitSprite = v.sprites[1]
	var foe: UnitSprite = v.sprites[2]
	assert_true(me.get_index() < foe.get_index(), "corpse drawn below the living")
	assert_true(me.position.y > v.cell_center(BattleViewModel.to_cell(vm.units[1]["pos"])).y, "corpse shifted forward out from under the enemy")
	assert_true(foe.xray_target < 1.0, "enemy standing on my corpse turns see-through")
	var pos := { 1: Vector2(2, 3), 2: Vector2(2, 3), 3: Vector2(4, 4) }
	assert_true(BattleIsoView.corpse_covered(1, pos, { 1: true }))
	assert_false(BattleIsoView.corpse_covered(3, pos, { 3: true }))

## 攻擊範圍藍格、目標紅格；cells_within 只列格子內、曼哈頓距離 1..r 的格
func test_attack_range_and_targets() -> void:
	var cells := BattleIsoView.cells_within(Vector2i(0, 0), 1, 12, 8)
	assert_eq(cells.size(), 2, "corner: only two neighbours")
	assert_eq(BattleIsoView.cells_within(Vector2i(5, 4), 2, 12, 8).size(), 12)
	var v := _view(Vector2(1280, 720))
	v.set_range(cells)
	v.set_highlight([Vector2i(1, 0)], UiTheme.HIGHLIGHT_TARGET)
	assert_eq(v.range_cells.size(), 2)
	v.clear_highlight()
	assert_true(v.range_cells.is_empty() and v.highlight.is_empty(), "clear removes range too")
	assert_true(UiTheme.HIGHLIGHT_MOVE.g > UiTheme.HIGHLIGHT_MOVE.r and UiTheme.HIGHLIGHT_MOVE.g > UiTheme.HIGHLIGHT_MOVE.b, "move = green")
	assert_true(UiTheme.HIGHLIGHT_RANGE.b > UiTheme.HIGHLIGHT_RANGE.r, "attack range = blue")
	assert_true(UiTheme.HIGHLIGHT_TARGET.r > UiTheme.HIGHLIGHT_TARGET.b, "target = red")
	assert_eq(BattleIsoView.ESCAPE_EDGE, Color.WHITE, "escape tile = white")


func test_front_unit_covering_player_turns_see_through() -> void:
	var v := _view(Vector2(1280, 720))
	var vm := v.vm
	vm.units[2]["pos"] = Vector2i(2, 4)   # 我的正前方（x+y 大一格、螢幕上同一直線下方）
	await tree.process_frame
	await tree.process_frame
	var me: UnitSprite = v.sprites[1]
	var foe: UnitSprite = v.sprites[2]
	assert_true(foe.depth > me.depth)
	var covers := foe.body_rect(foe.position).intersection(me.self_rect(me.position)).get_area() >= me.self_rect(me.position).get_area() * BattleIsoView.XRAY_COVER
	assert_eq(foe.xray_target, BattleIsoView.XRAY_ALPHA if covers else 1.0, "x-ray only when the front unit really covers me")
	assert_eq(me.xray_target, 1.0, "the player is never see-through")
	# 我倒地：屍體不變淡、名字牌照常
	vm.units[1]["state"] = "DEAD"
	v.settle()
	assert_eq(me.body_alpha, UnitSprite.MY_DEAD_ALPHA)
	# 光圈只在輪到我時：蓄勢中 my_turn 為 false
	assert_false(me.my_turn)
