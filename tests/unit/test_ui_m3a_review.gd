extends "res://tests/test_case.gd"
## M3a 審查修正（介面部分）的回歸測試：滿血不能療傷／不標為醫的目標、醫的目標箭頭、相鄰時名字牌與氣血字不蓋到別人、
## 冷卻層灰掉、「查看」同名、世界地圖地名靠近自己的記號。假快照沿用 test_ui_m3a_battle.gd 的 state()。

const B := preload("res://tests/unit/test_ui_m3a_battle.gd")

var _nodes: Array = []
var _old_wi: Dictionary = {}

func before_each() -> void:
	# 這個檔案量的是程式繪圖的地圖版面：強制不用地圖美術（ART_REQUEST §10 的圖已經匯入，見 test_ui_m3c_nav 的美術版測試）
	MapArt.use_textures({})
	UiSettings.reset_for_tests(true)
	_old_wi = ClientState.world_info

func after_each() -> void:
	MapArt.use_textures(null)
	ClientState.world_info = _old_wi
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _frame() -> void:
	await tree.process_frame

static func state(extra_me: Dictionary = {}) -> Dictionary:
	return B.state(extra_me)

func _screen(st: Dictionary, sent: Array) -> BattleScreen:
	var bs: BattleScreen = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	await _frame()
	bs.setup(st)
	bs.gate.set_sender(func(kind: String, args: Dictionary) -> int:
		sent.append([kind, args])
		return 5000 + sent.size())
	bs.apply_event({ "ch": "BATTLE", "key": "battle_await", "bid": 7, "ui": true, "p": { "units": [1], "deadline_tick": 900 } })
	bs.apply_event({ "ch": "BATTLE", "key": "battle_gauges", "bid": 7, "ui": true,
		"p": { "tick": 10, "units": [[1, 100.0, 7.0, false], [2, 50.0, 6.0, false], [3, 40.0, 6.0, false], [4, 40.0, 6.0, false]] } })
	bs.sending = false
	bs._refresh()
	return bs

func test_heal_greyed_at_full_health() -> void:
	var full: BattleScreen = await _screen(state({ "qi": 200, "qi_max": 200 }), [])
	assert_eq(full.inner_block("HEAL"), "氣血已滿")
	full._on_command(UiKeys.CMD_INNER)
	assert_true((full.cmd_menu_box.get_child(0) as Button).disabled, "滿血：運功療傷灰掉")
	assert_true(str(full.menu_texts()[0]).contains("氣血已滿"))
	var hurt: BattleScreen = await _screen(state({ "qi": 150, "qi_max": 200 }), [])
	assert_eq(hurt.inner_block("HEAL"), "")

func test_medic_targets_skip_full_health() -> void:
	# 我滿血、沒有中毒；隊友 100/200：醫只標隊友
	var sent: Array = []
	var bs: BattleScreen = await _screen(state({ "qi": 200, "qi_max": 200, "statuses": [] }), sent)
	bs._on_command(UiKeys.CMD_MEDIC)
	assert_eq(bs.mode, UiKeys.CMD_MEDIC)
	assert_eq(bs.grid_view.highlight, [Vector2i(3, 4)], "滿血的自己不是目標")
	# 大家都滿血：不進選格模式，提示不必療傷
	var st := state({ "qi": 200, "qi_max": 200, "statuses": [] })
	st["units"][2]["qi"] = 200
	var bs2: BattleScreen = await _screen(st, [])
	bs2._on_command(UiKeys.CMD_MEDIC)
	assert_eq(bs2.mode, "")
	assert_true(bs2.grid_view.highlight.is_empty())
	assert_true(bs2.hint_label.text.contains("不必療傷"), bs2.hint_label.text)
	# 滿血但中毒：還是目標（醫能解毒）
	var bs3: BattleScreen = await _screen(state({ "qi": 200, "qi_max": 200 }), [])
	assert_true(bs3.vm.needs_medic(1), "中毒的人是醫的目標")

## M3a UI 審查 #4：只有自己、又滿血 →「醫」跟「運功療傷」一樣灰掉，原因在提示裡
func test_medic_greyed_when_nobody_needs_it() -> void:
	var st := state({ "qi": 200, "qi_max": 200, "statuses": [] })
	st["units"][2]["qi"] = 200
	var bs: BattleScreen = await _screen(st, [])
	assert_eq(CommandBar.unavailable_reason(bs.vm, UiKeys.CMD_MEDIC), CommandBar.MEDIC_NOTHING_TIP)
	var hurt: BattleScreen = await _screen(state({ "qi": 150, "qi_max": 200, "statuses": [] }), [])
	assert_eq(CommandBar.unavailable_reason(hurt.vm, UiKeys.CMD_MEDIC), "", "自己受傷：可以醫")

## M3a UI 審查 #8：小條寫「戰鬥結束」；自動返回開著時沒有「返回」鈕
func test_result_strip_follows_spec() -> void:
	var bs: BattleScreen = await _screen(state(), [])
	bs.show_result({ "result": "VICTORY", "rewards": { "combat_xp": 5, "learn_points": 1, "money": 0, "items": [] } })
	assert_eq(bs.result_title.text, "戰鬥結束")
	assert_eq(bs.result_label.text, "勝利")
	assert_false(bs.return_button.visible, "自動返回：不放返回鈕")
	assert_true(bs.return_at_ms >= 0)
	assert_true(BattleScreen.AUTO_RETURN_S <= 2.5)
	UiSettings.set_value("ui.battle_auto_return", false)
	var bs2: BattleScreen = await _screen(state(), [])
	bs2.show_result({ "result": "DEFEAT", "rewards": {} })
	assert_true(bs2.return_button.visible, "關掉自動返回才需要按鈕")
	assert_eq(bs2.return_at_ms, -1)

## M3a UI 審查 #6：運功選單開著、壓到戰報 → 戰報藏起來
func test_menu_hides_battle_log() -> void:
	var bs: BattleScreen = await _screen(state({ "qi": 200, "qi_max": 200 }), [])
	bs._on_command(UiKeys.CMD_INNER)
	await _frame()
	bs._process(0.0)
	if bs.cmd_menu.get_global_rect().intersects(bs.log_text.get_global_rect()):
		assert_false(bs.log_text.visible, "選單壓到戰報：戰報藏起來")
	bs.cancel_mode()
	bs._process(0.0)
	assert_true(bs.log_text.visible)

## M3a UI 審查 #5：狀態圓章直徑約 19 px，畫在自己名字牌裡的左端（牌子為它加寬），名字仍對準自己的中線
func test_status_badge_inside_own_plate() -> void:
	assert_true(BattleFx.BADGE_R * 2.0 >= 18.0 and BattleFx.BADGE_R * 2.0 <= 20.0)
	var plate := Rect2(Vector2(500, 150), Vector2(60 + BattleFx.badge_room(2), 40))
	var c0 := BattleFx.badge_center(plate, 20.0, Vector2(530, 200), 0, 2)
	var c1 := BattleFx.badge_center(plate, 20.0, Vector2(530, 200), 1, 2)
	assert_true(c0.x - BattleFx.BADGE_R >= plate.position.x, "圓章在牌子裡")
	assert_true(c1.x + BattleFx.BADGE_R <= plate.position.x + BattleFx.badge_room(2), "圓章不壓到名字區")
	assert_true(c0.y > plate.position.y and c0.y < plate.position.y + 20.0, "名字那一列")
	var bs: BattleScreen = await _screen(state(), [])
	await _frame()
	var foe: UnitSprite = bs.grid_view.sprites[2]
	foe.badge_w = 0.0
	var plain := foe.default_name_box(foe.position)
	foe.badge_w = BattleFx.badge_room(1)
	var wide := foe.default_name_box(foe.position)
	assert_true(absf(wide.size.x - (plain.size.x + BattleFx.badge_room(1))) < 0.01, "牌子為圓章加寬")
	assert_true(absf(foe.plate_center_x(wide) - plain.get_center().x) < 0.01, "名字仍對準自己的中線")
	foe.badge_w = 0.0

func test_name_plates_lift_over_adjacent_body() -> void:
	var bs: BattleScreen = await _screen(state(), [])
	var v: BattleIsoView = bs.grid_view
	await _frame()
	await _frame()
	var me: UnitSprite = v.sprites[1]
	var foe: UnitSprite = v.sprites[2]
	var bodies := BattleFx.layout_names_with_hp([foe, me], true)
	var my_body := me.body_rect(me.position)
	assert_false(foe.name_box.intersects(my_body), "敵人的名字牌不蓋在我身上 %s vs %s" % [foe.name_box, my_body])
	# 連手臂與兵器也不蓋（M3a UI 審查 #3：body_rect 只算軀幹，野兔的牌子壓在木刀上）
	var my_reach := me.reach_rect(me.position)
	assert_true(my_reach.size.x >= my_body.size.x)
	assert_false(foe.name_box.intersects(my_reach), "敵人的名字牌不蓋在我的兵器上 %s vs %s" % [foe.name_box, my_reach])
	if not foe.hp_line:
		assert_false(foe.waist_hp_rect().intersects(my_body), "敵人的腰部氣血字不蓋在我身上")
	assert_false(me.name_box.intersects(foe.name_box))
	assert_true(bodies.size() >= 2)

func test_scout_button_named_look() -> void:
	assert_eq(ScenePanel.SCOUT_LABEL, "查看", "與 F3 熱鍵、偵察視窗同名")

func test_disabled_cooldown_uses_dim_ink() -> void:
	assert_true(JyButton.JY_COOL_NAME_OFF.v < JyButton.JY_COOL_NAME.v, "不能用時冷卻名字變暗")
	assert_true(JyButton.JY_COOL_OFF.v < JyButton.JY_COOL.v)

func test_world_map_labels_sit_next_to_their_own_mark() -> void:
	var loader := DataLoader.new()
	loader.load_all("res://data")
	var view := loader.activate(["1.0A"])
	for sz in [Vector2(1190, 430), Vector2(1000, 470), Vector2(1600, 800)]:
		var w := WorldMapView.new()
		_add(w)
		w.size = sz
		w.setup(MapData.world_model(view), "xixia")
		w.routes()
		var texts: Dictionary = {}
		for st in w.sites():
			texts[str(st["id"])] = w._site_text(st)
		assert_eq(texts.get("huashan", ""), "華山派", "門派地名帶「派」")
		for st in w.sites():
			var id := str(st["id"])
			if str(st["type"]) != "SECT" or not w._labels.has(id):
				continue
			var lr: Rect2 = w._labels[id]
			var own := WorldMapView.rect_dist(lr, (w._marks[id] as Rect2).get_center())
			for o in w._marks:
				if o == id:
					continue
				var d := WorldMapView.rect_dist(lr, (w._marks[o] as Rect2).get_center())
				assert_true(d + 2.0 >= own, "%s：%s 的地名比較靠近 %s（%.1f < %.1f）" % [str(sz), texts[id], o, d, own])

func test_battle_log_result_lines_stay_last() -> void:
	var bs: BattleScreen = await _screen(state(), [])
	bs.apply_event({ "ch": "BATTLE", "key": "battle_defend", "bid": 7, "p": { "uid": 1, "name": "測試俠客", "peer": 1 } })
	bs.show_result({ "result": "VICTORY", "rewards": { "combat_xp": 5, "learn_points": 1, "money": 0, "items": [] } })
	var n0 := bs.log_plain_lines().size()
	# 結果已經出來，最後一擊與主機的勝利、獎勵訊息才到：要排在「戰鬥結束」前面，獎勵不重複
	bs.apply_event({ "ch": "BATTLE", "key": "battle_victory", "bid": 7, "p": {} })
	bs.apply_event({ "ch": "BATTLE", "key": "battle_reward", "bid": 7, "p": { "combat_xp": 5, "learn_points": 1, "money": 0 } })
	var lines := bs.log_plain_lines()
	assert_eq(lines.size(), n0 + 2)
	assert_true(lines[lines.size() - 1].begins_with("戰鬥結束"), "「戰鬥結束」在最後：%s" % str(lines))
	var reward_rows := 0
	for l in lines:
		if l.contains("實戰"):
			reward_rows += 1
	assert_eq(reward_rows, 1, "獎勵只印一次：%s" % str(lines))

func test_join_rules_follow_violation_mode() -> void:
	var t: Dictionary = GameData.tables
	var saved := { "sect_rules": t.get("sect_rules", {}).duplicate(), "text_templates": t.get("text_templates", {}).duplicate(),
		"sects": t.get("sects", {}).duplicate() }
	t["sects"]["t_rv"] = { "id": "t_rv", "name": "測派", "gender": ["M"], "join_requires": [] }
	t["sect_rules"]["t_rv_jail"] = { "id": "t_rv_jail", "sect": "t_rv", "kind": "STATE", "modes": ["JAIL", "BAN"], "text": "t_rv_jail" }
	t["sect_rules"]["t_rv_expel"] = { "id": "t_rv_expel", "sect": "t_rv", "kind": "STATE", "modes": ["EXPEL"], "text": "t_rv_expel" }
	t["text_templates"]["t_rv_jail"] = { "id": "t_rv_jail", "self": "坐牢名單" }
	t["text_templates"]["t_rv_expel"] = { "id": "t_rv_expel", "self": "叛派名單" }
	ClientState.world_info = { "rule_profile": { "sect_violation_mode": "JAIL" } }
	assert_eq(SectUi.rule_texts("t_rv"), PackedStringArray(["坐牢名單"]))
	ClientState.world_info = { "rule_profile": { "sect_violation_mode": "EXPEL" } }
	assert_eq(SectUi.rule_texts("t_rv"), PackedStringArray(["叛派名單"]))
	for k in saved:
		t[k] = saved[k]
