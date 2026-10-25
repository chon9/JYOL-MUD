extends "res://tests/test_case.gd"
## ROGUE WP-ALLY（ROGUE_PLAN §4.6、§9.1 test_ui_rogue_battle）：戰鬥畫面上的試煉隊友——名牌「〔友〕」與我方顏色、
## 人形剪影、時間棒清單；攻擊目標不含隊友、醫可以選隊友；ROGUE 結果框沒有獎勵列、改顯示回合與倒下的隊友、按鈕「繼續」。
## 全部用假快照（headless，不需要主機）。

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

## 我（uid 1）在 (3,3)；試煉隊友（uid 3，kind ALLY）在 (3,4)；敵人：野狼（uid 2）在 (4,3)
static func state() -> Dictionary:
	var me := { "uid": 1, "name": "試煉者", "side": 0, "kind": "PLAYER", "peer": 1, "pos": [3, 3],
		"qi": 150, "qi_max": 200, "neili": 80, "neili_max": 100, "jing": 90, "jing_max": 100, "shen": 90, "shen_max": 100,
		"gauge": 0.0, "rate": 7.0, "state": "CHARGING", "move_range": 2,
		"weapon": { "uid": "", "name": "", "weapon_type": "FIST" }, "weapon_options": [], "arts": [],
		"cmd_avail": { "POISON": false, "MEDIC": true, "HIDDEN": false, "FORMATION": false,
			"INNER": ["HEAL", "TRANSFER"], "ACUPOINT": false, "ITEM": false },
		"cmd_arts": { "POISON": [], "MEDIC": [], "HIDDEN": [], "FORMATION": [], "INNER": [ { "id": "t_xinfa", "name": "測試心法", "range": 0 } ], "ACUPOINT": [] },
		"hidden_items": [], "battle_items": [], "formation": null, "statuses": [] }
	return {
		"bid": 7, "w": 12, "h": 8, "tick": 0, "wait_mode": true, "my_uid": 1, "escape": [], "kind": "ROGUE", "no_flee": true,
		"units": [
			me,
			{ "uid": 2, "name": "野狼", "side": 1, "kind": "MONSTER", "peer": 0, "pos": [4, 3], "qi": 80, "qi_max": 80,
			  "gauge": 0.0, "rate": 6.0, "state": "CHARGING", "ref": "m_wolf" },
			{ "uid": 3, "name": "令狐沖", "short": "令狐", "side": 0, "kind": "ALLY", "peer": 0, "pos": [3, 4], "qi": 120, "qi_max": 300,
			  "gauge": 0.0, "rate": 6.0, "state": "CHARGING", "ref": "n_hs_linghuchong" },
		],
	}

func _screen(sent: Array) -> BattleScreen:
	var bs: BattleScreen = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	bs.setup(state())
	bs.gate.set_sender(func(kind: String, args: Dictionary) -> int:
		sent.append([kind, args])
		return 5000 + sent.size())
	bs.apply_event({ "ch": "BATTLE", "key": "battle_await", "bid": 7, "ui": true, "p": { "units": [1], "deadline_tick": 900 } })
	bs.apply_event({ "ch": "BATTLE", "key": "battle_gauges", "bid": 7, "ui": true,
		"p": { "tick": 10, "units": [[1, 100.0, 7.0, false], [2, 50.0, 6.0, false], [3, 40.0, 6.0, false]] } })
	bs.sending = false
	bs._refresh()
	await tree.process_frame
	return bs

func test_ally_name_plate_tag_and_color() -> void:
	var bs: BattleScreen = await _screen([])
	var sp: UnitSprite = bs.grid_view.sprites[3]
	assert_true(sp.ally, "隊友在我方（名字用我方黃）")
	assert_true(sp.label_text().begins_with("〔友〕"), sp.label_text())
	assert_true(sp.label_text().contains("令狐沖"))
	assert_eq(sp.shape, "human", "隊友當人形")
	assert_eq(UnitSprite.shape_for({ "kind": "ALLY", "name": "小黃" }), "human")
	var foe: UnitSprite = bs.grid_view.sprites[2]
	assert_false(foe.ally)
	assert_false(foe.label_text().contains("〔友〕"))
	var me: UnitSprite = bs.grid_view.sprites[1]
	assert_false(me.label_text().contains("〔友〕"), "玩家自己不加")
	# 時間棒清單：名字前加「〔友〕」、我方顏色
	var row: Dictionary = bs._gauge_rows[3]
	var nl: Label = row["name"]
	assert_true(nl.text.begins_with("〔友〕"), nl.text)
	assert_eq(nl.get_theme_color("font_color"), UiTheme.NAME_ALLY)
	assert_eq((bs._gauge_rows[2]["name"] as Label).get_theme_color("font_color"), UiTheme.NAME_ENEMY)

func test_attack_targets_exclude_ally_medic_includes() -> void:
	var sent: Array = []
	var bs: BattleScreen = await _screen(sent)
	var enemy_cells := bs.vm.enemy_cells_within(10)
	assert_has(enemy_cells, Vector2i(4, 3))
	assert_not_has(enemy_cells, Vector2i(3, 4), "ATTACK／ART 不能選隊友")
	assert_true(bs.vm.is_enemy(2))
	assert_false(bs.vm.is_enemy(3))
	bs._on_command(UiKeys.CMD_ATTACK)
	assert_false(bs.grid_view.highlight.has(Vector2i(3, 4)), "攻擊紅框沒有隊友")
	bs.cancel_mode()
	bs._on_command(UiKeys.CMD_MEDIC)
	assert_eq(bs.mode, UiKeys.CMD_MEDIC)
	assert_true(bs.grid_view.highlight.has(Vector2i(3, 4)), "醫可以選隊友")
	assert_false(bs.grid_view.highlight.has(Vector2i(4, 3)))
	bs._on_cell(Vector2i(3, 4))
	assert_eq(sent.size(), 1)
	assert_eq(sent[0][1], { "battle_id": 7, "cmd": "MEDIC", "target": [3, 4] })
	assert_has(bs.vm.ally_cells_within(1, false), Vector2i(3, 4), "傳力的目標格也含隊友")

func test_rogue_result_has_no_reward_lines() -> void:
	UiSettings.set_value("ui.battle_auto_return", false)
	var bs: BattleScreen = await _screen([])
	bs._show_result_now({ "bid": 7, "result": "VICTORY", "kind": "ROGUE", "you_died": false, "death": {},
		"rewards": { "combat_xp": 30, "learn_points": 5, "money": 300, "items": [] },
		"rogue": { "round": 3, "won": true, "boss": false, "allies_fallen": ["令狐沖"], "over": false } })
	var t: String = bs.result_detail.text
	assert_false(t.contains("實戰經驗"), t)
	assert_false(t.contains("學習點數"))
	assert_false(t.contains("銀兩"))
	assert_true(t.contains("第 3 回合　勝"), t)
	assert_true(t.contains("倒下的隊友：令狐沖"), t)
	assert_eq(bs.return_button.text, "繼續")
	assert_true(bs.return_button.visible)

func test_rogue_result_over() -> void:
	var bs: BattleScreen = await _screen([])
	bs._show_result_now({ "bid": 7, "result": "DEFEAT", "kind": "ROGUE", "you_died": true,
		"death": { "money_lost": 50, "skill_losses": [ { "name": "基本拳腳", "to": 3 } ] }, "rewards": {},
		"rogue": { "round": 6, "won": false, "boss": true, "allies_fallen": [], "over": true } })
	var t: String = bs.result_detail.text
	assert_true(t.contains("試煉結束"), t)
	assert_true(t.contains("你力戰倒下"))
	assert_false(t.contains("退步"), "沒有死亡損失列")
	assert_false(t.contains("兩銀子"))
	assert_false(t.contains("倒下的隊友"))
	assert_eq(BattleScreen.rogue_result_lines({ "result": "VICTORY", "rogue": { "round": 5, "won": true, "boss": true } }),
		PackedStringArray(["第 5 回合　勝（名人敗退）"]))
	assert_true(BattleScreen.is_rogue_result({ "kind": "ROGUE" }))
	assert_false(BattleScreen.is_rogue_result({ "kind": "ENCOUNTER" }))

func test_non_rogue_result_unchanged() -> void:
	var bs: BattleScreen = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	var st := state()
	st["kind"] = "ENCOUNTER"
	bs.setup(st)
	bs._show_result_now({ "bid": 7, "result": "VICTORY", "kind": "ENCOUNTER", "you_died": false, "death": {},
		"rewards": { "combat_xp": 30, "learn_points": 5, "money": 0, "items": [] } })
	assert_true(bs.result_detail.text.contains("實戰經驗 +30"))
	assert_eq(bs.return_button.text, "返回")
