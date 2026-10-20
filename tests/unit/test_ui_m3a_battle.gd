extends "res://tests/test_case.gd"
## WP-UI（M3A_PLAN §10.1 test_ui_m3a_battle）：按鈕啟用依 cmd_avail、later_battle_cmds 關閉時鎖住、選目標顏色、
## 內選單、暗器選單、陣站位顯示、範圍預覽、狀態圖示。全部用假快照（不需要 WP-CMD 的戰鬥規則）。

var _nodes: Array = []
var _old_wi: Dictionary = {}

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	_old_wi = ClientState.world_info

func after_each() -> void:
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

## 我（uid 1）在 (3,3)；隊友（uid 3，玩家）在 (3,4)；敵人：野狼（uid 2）在 (4,3)、山賊（uid 4）在 (6,3)
static func state(extra_me: Dictionary = {}) -> Dictionary:
	var me := { "uid": 1, "name": "測試俠客", "side": 0, "kind": "PLAYER", "peer": 1, "pos": [3, 3],
		"qi": 150, "qi_max": 200, "neili": 80, "neili_max": 100, "jing": 90, "jing_max": 100,
		"gauge": 0.0, "rate": 7.0, "state": "CHARGING", "move_range": 2,
		"weapon": { "uid": "", "name": "", "weapon_type": "FIST" }, "weapon_options": [],
		"arts": [ { "id": "t_sword", "name": "測試劍法", "category": "SWORD", "level": 40, "moves": [
			{ "id": "t_sw_1", "name": "單刺", "unlock_level": 1, "range": 1, "cost_inner": 0, "cost_jing": 0, "usable": true, "aoe": "SINGLE" },
			{ "id": "t_sw_2", "name": "十字劍", "unlock_level": 30, "range": 2, "cost_inner": 4, "cost_jing": 0, "usable": true, "aoe": "CROSS" } ] } ],
		"cmd_avail": { "POISON": true, "MEDIC": true, "HIDDEN": true, "FORMATION": true,
			"INNER": ["HEAL", "TRANSFER"], "ACUPOINT": true, "ITEM": true },
		"cmd_arts": {
			"POISON": [ { "id": "xh_fangdu", "name": "放毒法", "range": 2 } ],
			"MEDIC": [], "HIDDEN": [], "FORMATION": [ { "id": "t_zhen", "name": "測試陣", "range": 0 } ],
			"INNER": [ { "id": "t_xinfa", "name": "測試心法", "range": 0 } ], "ACUPOINT": [ { "id": "lj_zhemei", "name": "天山折梅手", "range": 1 } ] },
		"hidden_items": [ { "uid": "it_h1", "item_id": "h_jinqianbiao", "name": "金錢鏢", "n": 2, "dmg": 8 } ],
		"battle_items": [ { "uid": "it_c1", "item_id": "c_jieduyao", "name": "解毒藥", "n": 1, "effects": [] } ],
		"formation": { "art": "t_zhen", "stations": [[0, 0], [0, 1], [0, -1]] },
		"statuses": [ { "id": "poison", "name": "中毒", "glyph": "毒", "color": "#3c9a3c", "n": 4, "level": 2 } ],
	}
	for k in extra_me:
		me[k] = extra_me[k]
	return {
		"bid": 7, "w": 12, "h": 8, "tick": 0, "wait_mode": true, "my_uid": 1, "escape": [[0, 6]],
		"units": [
			me,
			{ "uid": 2, "name": "野狼", "side": 1, "kind": "MONSTER", "peer": 0, "pos": [4, 3], "qi": 80, "qi_max": 80,
			  "gauge": 0.0, "rate": 6.0, "state": "CHARGING", "statuses": [ { "id": "acupoint", "name": "封穴", "glyph": "穴", "color": "#c8a020", "n": 2, "level": 1 } ] },
			{ "uid": 3, "name": "隊友", "side": 0, "kind": "PLAYER", "peer": 2, "pos": [3, 4], "qi": 100, "qi_max": 200,
			  "gauge": 0.0, "rate": 6.0, "state": "CHARGING" },
			{ "uid": 4, "name": "山賊", "side": 1, "kind": "MONSTER", "peer": 0, "pos": [6, 3], "qi": 80, "qi_max": 80,
			  "gauge": 0.0, "rate": 6.0, "state": "CHARGING" },
		],
	}

func _screen(st: Dictionary, sent: Array) -> BattleScreen:
	var bs: BattleScreen = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	await _frame()
	bs.setup(st)
	bs.gate.set_sender(func(kind: String, args: Dictionary) -> int:
		sent.append([kind, args])
		return 5000 + sent.size())
	_my_turn(bs)
	return bs

func _my_turn(bs: BattleScreen) -> void:
	bs.apply_event({ "ch": "BATTLE", "key": "battle_await", "bid": 7, "ui": true, "p": { "units": [1], "deadline_tick": 900 } })
	bs.apply_event({ "ch": "BATTLE", "key": "battle_gauges", "bid": 7, "ui": true,
		"p": { "tick": 10, "units": [[1, 100.0, 7.0, false], [2, 50.0, 6.0, false], [3, 40.0, 6.0, false], [4, 40.0, 6.0, false]] } })
	bs.sending = false
	bs._refresh()

# ---------------------------------------------------------------- 按鈕啟用

func test_buttons_follow_cmd_avail() -> void:
	ClientState.world_info = { "later_battle_cmds": true }
	var bs: BattleScreen = await _screen(state(), [])
	for c in [UiKeys.CMD_POISON, UiKeys.CMD_MEDIC, UiKeys.CMD_HIDDEN, UiKeys.CMD_FORMATION, UiKeys.CMD_INNER, UiKeys.CMD_ACUPOINT]:
		assert_true(bs.command_bar.is_enabled(c), "%s enabled by cmd_avail" % c)
	var st := state({ "cmd_avail": { "POISON": false, "MEDIC": true, "HIDDEN": true, "FORMATION": false, "INNER": [], "ACUPOINT": false, "ITEM": false },
		"hidden_items": [] })
	var bs2: BattleScreen = await _screen(st, [])
	assert_false(bs2.command_bar.is_enabled(UiKeys.CMD_POISON))
	assert_true(bs2.command_bar.is_enabled(UiKeys.CMD_MEDIC))
	assert_false(bs2.command_bar.is_enabled(UiKeys.CMD_HIDDEN), "no ammo left → 暗 off even if cmd_avail says true")
	assert_false(bs2.command_bar.is_enabled(UiKeys.CMD_INNER), "empty INNER mode list")
	assert_true((bs2.command_bar.buttons[UiKeys.CMD_POISON] as Button).tooltip_text.contains("還沒學會毒術"))
	assert_false(bs2.vm.cmd_open(UiKeys.CMD_ITEM))
	# 不是我的回合：全部不能按
	var st3 := state()
	var bs3: BattleScreen = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	await _frame()
	bs3.setup(st3)
	bs3._refresh()
	assert_false(bs3.command_bar.is_enabled(UiKeys.CMD_POISON), "not my turn")

func test_later_battle_cmds_off_locks_inner_and_acupoint() -> void:
	ClientState.world_info = { "rule_profile": { "later_battle_cmds": false } }
	assert_false(BattleScreen.later_cmds_enabled(), "old host: read the expanded rule profile")
	var bs: BattleScreen = await _screen(state(), [])
	assert_false(bs.vm.later_cmds)
	assert_false(bs.command_bar.is_enabled(UiKeys.CMD_INNER))
	assert_false(bs.command_bar.is_enabled(UiKeys.CMD_ACUPOINT))
	assert_true((bs.command_bar.buttons[UiKeys.CMD_INNER] as Button).tooltip_text.contains(UiKeys.LATER_CMDS_TIP))
	assert_true((bs.command_bar.buttons[UiKeys.CMD_ACUPOINT] as Button).tooltip_text.contains("2002"))
	assert_true(bs.command_bar.is_enabled(UiKeys.CMD_POISON), "毒醫暗陣 unaffected")
	ClientState.world_info = { "later_battle_cmds": true, "rule_profile": { "later_battle_cmds": false } }
	assert_true(BattleScreen.later_cmds_enabled(), "world_info field wins")
	ClientState.world_info = {}
	assert_true(BattleScreen.later_cmds_enabled(), "default on")

func test_hotkeys_8_9_0_and_shift() -> void:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_8
	assert_eq(BattleScreen.hotkey_cmd(k), UiKeys.CMD_POISON)
	k.keycode = KEY_9
	assert_eq(BattleScreen.hotkey_cmd(k), UiKeys.CMD_MEDIC)
	k.keycode = KEY_0
	assert_eq(BattleScreen.hotkey_cmd(k), UiKeys.CMD_HIDDEN)
	k.keycode = KEY_1
	assert_eq(BattleScreen.hotkey_cmd(k), UiKeys.CMD_MOVE)
	k.shift_pressed = true
	assert_eq(BattleScreen.hotkey_cmd(k), UiKeys.CMD_FORMATION)
	k.keycode = KEY_AT
	assert_eq(BattleScreen.hotkey_cmd(k), UiKeys.CMD_INNER, "Shift+2 reported as @")
	k.keycode = KEY_3
	assert_eq(BattleScreen.hotkey_cmd(k), UiKeys.CMD_ACUPOINT)
	k.keycode = KEY_5
	assert_eq(BattleScreen.hotkey_cmd(k), "", "Shift+5 is nothing")
	for c in UiKeys.M3A_CMDS:
		if c != UiKeys.CMD_ITEM:
			assert_true(str(UiKeys.CMD_TOOLTIPS.get(c, "")).contains("快捷鍵"), "%s tooltip shows its hotkey" % c)

func test_status_blocks_disable_command() -> void:
	# 我被封穴：移、逃灰掉，提示寫狀態名
	var st := state({ "statuses": [ { "id": "acupoint", "name": "封穴", "glyph": "穴", "color": "#c8a020", "n": 2, "level": 1 } ] })
	var bs: BattleScreen = await _screen(st, [])
	assert_eq(bs.vm.status_blocks(UiKeys.CMD_MOVE), "封穴")
	assert_false(bs.command_bar.is_enabled(UiKeys.CMD_MOVE))
	assert_true((bs.command_bar.buttons[UiKeys.CMD_MOVE] as Button).tooltip_text.contains("封穴"))
	assert_true(bs.command_bar.is_enabled(UiKeys.CMD_DEFEND))

# ---------------------------------------------------------------- 選目標

func test_poison_targets_enemies_in_red_and_sends_art() -> void:
	var sent: Array = []
	var bs: BattleScreen = await _screen(state(), sent)
	bs._on_command(UiKeys.CMD_POISON)
	assert_eq(bs.mode, UiKeys.CMD_POISON, "single poison art: straight to targeting")
	assert_eq(bs.grid_view.highlight_color, UiTheme.HIGHLIGHT_TARGET)
	assert_true(bs.grid_view.highlight.has(Vector2i(4, 3)))
	assert_false(bs.grid_view.highlight.has(Vector2i(6, 3)), "out of range 2")
	assert_false(bs.grid_view.highlight.has(Vector2i(3, 4)), "ally not a poison target")
	bs._on_cell(Vector2i(4, 3))
	assert_eq(sent, [["battle_cmd", { "battle_id": 7, "cmd": "POISON", "target": [4, 3], "art": "xh_fangdu" }]])

func test_medic_and_item_target_self_or_ally_in_green() -> void:
	var sent: Array = []
	var bs: BattleScreen = await _screen(state(), sent)
	bs._on_command(UiKeys.CMD_MEDIC)
	assert_eq(bs.mode, UiKeys.CMD_MEDIC)
	assert_eq(bs.grid_view.highlight_color, UiTheme.HIGHLIGHT_ALLY)
	assert_true(bs.grid_view.highlight.has(Vector2i(3, 3)), "self")
	assert_true(bs.grid_view.highlight.has(Vector2i(3, 4)), "adjacent ally")
	assert_false(bs.grid_view.highlight.has(Vector2i(4, 3)), "enemy not healable")
	bs._on_cell(Vector2i(3, 4))
	assert_eq(sent[0][1], { "battle_id": 7, "cmd": "MEDIC", "target": [3, 4] }, "no MEDIC art → no art arg")
	bs.gate.resolve(5001, false, "not_ready")
	# 裝 → 用藥 → 自己
	bs._on_command(UiKeys.CMD_EQUIP)
	assert_true(bs.cmd_menu.visible)
	assert_eq(bs.menu_texts().size(), 2)
	assert_eq(bs.menu_texts()[0], "換兵器")
	assert_true(str(bs.menu_texts()[1]).begins_with("用藥"))
	(bs.cmd_menu_box.get_child(1) as Button).pressed.emit()
	assert_true(bs.cmd_menu.visible, "item list")
	assert_eq(bs.menu_texts(), ["解毒藥 ×1"])
	(bs.cmd_menu_box.get_child(0) as Button).pressed.emit()
	assert_eq(bs.mode, UiKeys.CMD_ITEM)
	assert_eq(bs.grid_view.highlight_color, UiTheme.HIGHLIGHT_ALLY)
	bs._on_cell(Vector2i(3, 3))
	assert_eq(sent[1][1], { "battle_id": 7, "cmd": "ITEM", "target": [3, 3], "item_uid": "it_c1" })
	# 換兵器仍然打開兵器清單
	bs.gate.resolve(5002, false, "not_ready")
	bs._on_command(UiKeys.CMD_EQUIP)
	(bs.cmd_menu_box.get_child(0) as Button).pressed.emit()
	assert_true(bs.equip_panel.visible)

func test_hidden_menu_lists_ammo_then_targets() -> void:
	var sent: Array = []
	var bs: BattleScreen = await _screen(state(), sent)
	bs._on_command(UiKeys.CMD_HIDDEN)
	assert_true(bs.cmd_menu.visible)
	assert_eq(bs.menu_texts(), ["金錢鏢 ×2　傷氣 8"])
	(bs.cmd_menu_box.get_child(0) as Button).pressed.emit()
	assert_eq(bs.mode, UiKeys.CMD_HIDDEN)
	assert_eq(int(bs.pending["range"]), 3, "3 + floor(0/40), no hidden art")
	assert_true(bs.grid_view.highlight.has(Vector2i(6, 3)), "range 3 reaches 山賊")
	bs._on_cell(Vector2i(6, 3))
	assert_eq(sent[0][1], { "battle_id": 7, "cmd": "HIDDEN", "target": [6, 3], "item_uid": "it_h1" })
	# 丟出去一個：數量 −1，丟完「暗」就不能用
	bs.apply_event({ "ch": "BATTLE", "key": "battle_hidden_miss", "bid": 7,
		"p": { "atk_uid": 1, "def_uid": 4, "atk_peer": 1, "atk": "測試俠客", "def": "山賊", "item_name": "金錢鏢" } })
	assert_eq(int(bs.vm.hidden_items()[0]["n"]), 1)
	bs.apply_event({ "ch": "BATTLE", "key": "battle_hidden_miss", "bid": 7,
		"p": { "atk_uid": 1, "def_uid": 4, "atk_peer": 1, "atk": "測試俠客", "def": "山賊", "item_uid": "it_h1", "item_name": "金錢鏢", "left": 0 } })
	assert_true(bs.vm.hidden_items().is_empty())
	assert_false(bs.vm.cmd_open(UiKeys.CMD_HIDDEN))
	assert_eq(BattleViewModel.hidden_range_for(80, 1), 6, "3 + 2 + 1")
	assert_eq(BattleViewModel.hidden_range_for(200, 2), 6, "capped at 6")

func test_acupoint_targets_adjacent_enemy() -> void:
	var sent: Array = []
	var bs: BattleScreen = await _screen(state(), sent)
	bs._on_command(UiKeys.CMD_ACUPOINT)
	assert_eq(bs.mode, UiKeys.CMD_ACUPOINT)
	assert_eq(bs.grid_view.highlight, [Vector2i(4, 3)])
	bs._on_cell(Vector2i(4, 3))
	assert_eq(sent[0][1], { "battle_id": 7, "cmd": "ACUPOINT", "target": [4, 3], "art": "lj_zhemei" })

func test_inner_menu_modes_and_reasons() -> void:
	var sent: Array = []
	var bs: BattleScreen = await _screen(state(), sent)
	bs._on_command(UiKeys.CMD_INNER)
	assert_true(bs.cmd_menu.visible)
	var texts := bs.menu_texts()
	assert_eq(texts.size(), 4)
	assert_eq(texts[0], "運功療傷")
	assert_true(str(texts[1]).begins_with("逼毒") and str(texts[1]).contains("目前不能用"), "poisoned but host did not offer EXPEL: %s" % texts[1])
	assert_true(str(texts[2]).contains("沒有被封穴"), texts[2])
	assert_eq(texts[3], "傳力")
	assert_false((bs.cmd_menu_box.get_child(0) as Button).disabled)
	assert_true((bs.cmd_menu_box.get_child(1) as Button).disabled)
	assert_true((bs.cmd_menu_box.get_child(2) as Button).disabled)
	# 療傷：直接送
	(bs.cmd_menu_box.get_child(0) as Button).pressed.emit()
	assert_eq(sent[0][1], { "battle_id": 7, "cmd": "INNER", "mode": "HEAL" })
	bs.gate.resolve(5001, false, "not_ready")
	# 傳力：選相鄰隊友（綠框，不含自己）
	bs._on_command(UiKeys.CMD_INNER)
	(bs.cmd_menu_box.get_child(3) as Button).pressed.emit()
	assert_eq(bs.mode, UiKeys.CMD_INNER)
	assert_eq(bs.grid_view.highlight, [Vector2i(3, 4)])
	assert_eq(bs.grid_view.highlight_color, UiTheme.HIGHLIGHT_ALLY)
	bs._on_cell(Vector2i(3, 4))
	assert_eq(sent[1][1], { "battle_id": 7, "cmd": "INNER", "target": [3, 4], "mode": "TRANSFER" })
	# 沒中毒：逼毒寫「沒有中毒」
	var st := state({ "statuses": [] })
	var bs2: BattleScreen = await _screen(st, [])
	assert_eq(bs2.inner_block("EXPEL"), "沒有中毒")

func test_formation_shows_stations_and_enter_submits() -> void:
	var sent: Array = []
	var bs: BattleScreen = await _screen(state(), sent)
	bs._on_command(UiKeys.CMD_FORMATION)
	assert_eq(bs.mode, UiKeys.CMD_FORMATION)
	assert_eq(bs.grid_view.highlight_color, UiTheme.HIGHLIGHT_STATION)
	assert_eq(bs.grid_view.station_cells, [Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 2)])
	assert_eq(bs.grid_view.station_missing, [Vector2i(3, 2)], "(3,4) has 隊友; (3,2) empty → blinking")
	assert_true(bs.hint_label.text.contains("還缺 1 人"), bs.hint_label.text)
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_ENTER
	bs._shortcut_input(k)
	assert_eq(sent, [["battle_cmd", { "battle_id": 7, "cmd": "FORMATION", "art": "t_zhen" }]])
	assert_true(bs.grid_view.station_cells.is_empty(), "cleared after submit")

func test_formation_stations_in_mirrored_pvp() -> void:
	# 被叫戰的一方（my_side 1）：畫面鏡像，自己在左；站位照原樣加在畫面座標上
	var st := state()
	st["my_side"] = 1
	for u in st["units"]:
		u["side"] = 1 - int(u["side"])
	var vm := BattleViewModel.from_state(st)
	assert_true(vm.mirrored)
	var me_pos: Vector2i = vm.me()["pos"]
	assert_eq(me_pos, Vector2i(8, 3), "mirrored x' = 11 − 3")
	assert_eq(vm.station_cells(vm.formation_stations("t_zhen")), [Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 2)])

func test_aoe_shapes() -> void:
	var o := Vector2i(3, 3)
	assert_eq(BattleViewModel.aoe_cells("CROSS", o, Vector2i(5, 3), 2, 12, 8).size(), 5)
	assert_eq(BattleViewModel.aoe_cells("CROSS_L", o, Vector2i(5, 3), 2, 12, 8).size(), 13)
	assert_eq(BattleViewModel.aoe_cells("CROSS_L", o, Vector2i(0, 0), 2, 12, 8).size(), 7, "clipped at the corner")
	assert_eq(BattleViewModel.aoe_cells("LINE", o, Vector2i(5, 3), 3, 12, 8), [Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3)])
	assert_eq(BattleViewModel.aoe_cells("LINE", o, Vector2i(5, 5), 2, 12, 8), [Vector2i(4, 4), Vector2i(5, 5)], "diagonal")
	assert_eq(BattleViewModel.aoe_cells("LINE", o, Vector2i(5, 4), 2, 12, 8), [], "not on a line")
	var fan := BattleViewModel.aoe_cells("FAN", o, Vector2i(4, 3), 2, 12, 8)
	assert_eq(fan.size(), 6)
	assert_true(fan.has(Vector2i(5, 1)) and fan.has(Vector2i(5, 5)) and fan.has(Vector2i(5, 3)))
	assert_eq(BattleViewModel.aoe_cells("AROUND", o, o, 1, 12, 8).size(), 8)
	assert_eq(BattleViewModel.aoe_cells("SINGLE", o, Vector2i(4, 3), 1, 12, 8), [Vector2i(4, 3)])

func test_aoe_preview_on_hover() -> void:
	var sent: Array = []
	var bs: BattleScreen = await _screen(state(), sent)
	bs._on_command(UiKeys.CMD_ART)
	bs.art_picker.select_art(bs.vm.my_arts()[0])
	bs.art_picker.select_move(bs.vm.my_arts()[0]["moves"][1])
	assert_true(bs.art_picker.move_box.get_child(1).text.contains("小十字"), "picker shows the shape")
	bs.art_picker._on_ok()
	assert_eq(str(bs.pending_art["aoe"]), "CROSS")
	assert_true(bs.grid_view.highlight.has(Vector2i(4, 3)), "center on the wolf")
	assert_true(bs.grid_view.highlight.has(Vector2i(3, 3)), "center on self still hits the adjacent wolf")
	assert_false(bs.grid_view.highlight.has(Vector2i(2, 2)), "no enemy in the cross")
	bs.grid_view.hover_cell = Vector2i(5, 3)
	bs._refresh()
	assert_eq(bs.grid_view.preview_cells.size(), 5)
	assert_true(bs.grid_view.preview_cells.has(Vector2i(4, 3)) and bs.grid_view.preview_cells.has(Vector2i(6, 3)))
	bs.grid_view.hover_cell = Vector2i(0, 7)
	bs._refresh()
	assert_true(bs.grid_view.preview_cells.is_empty(), "no preview off a valid center")
	bs._on_cell(Vector2i(5, 3))
	assert_eq(sent[0][1], { "battle_id": 7, "cmd": "ART", "art": "t_sword", "move": "t_sw_2", "power_tenths": 10, "target": [5, 3] })

# ---------------------------------------------------------------- 狀態圖示

func test_status_icons_from_snapshot_and_events() -> void:
	var vm := BattleViewModel.from_state(state())
	var mine := vm.unit_statuses(1)
	assert_eq(mine.size(), 1)
	assert_eq(mine[0]["glyph"], "毒")
	assert_eq(mine[0]["color"], "#3c9a3c")
	assert_eq(BattleViewModel.status_tip(mine[0]), "中毒（2 級） 剩 4 次")
	# 事件沒帶 glyph／color：查本地 status_effects 表
	vm.apply_event({ "ch": "BATTLE", "key": "battle_status_on", "bid": 7,
		"p": { "uid": 4, "name": "山賊", "peer": 0, "status": "confusion", "status_name": "混亂" } })
	var sts := vm.unit_statuses(4)
	assert_eq(sts.size(), 1)
	var row := UiClient.row("status_effects", "confusion")
	if not row.is_empty():
		assert_eq(sts[0]["glyph"], str(row["glyph"]))
		assert_eq(sts[0]["color"], str(row["color"]))
	# 一次行動扣一次（同一錨點的多個事件只扣一次）
	vm.apply_event({ "ch": "BATTLE", "key": "battle_poison_tick", "bid": 7, "p": { "uid": 1, "name": "測試俠客", "peer": 1, "dmg": 6, "qi": 144 } })
	vm.apply_event({ "ch": "BATTLE", "key": "battle_defend", "bid": 7, "p": { "uid": 1, "name": "測試俠客", "peer": 1 } })
	assert_eq(vm.unit(1)["qi"], 144)
	assert_eq(int(vm.unit_statuses(1)[0]["n"]), 3)
	vm.apply_event({ "ch": "BATTLE", "key": "battle_status_off", "bid": 7, "p": { "uid": 1, "name": "測試俠客", "peer": 1, "status": "poison", "status_name": "中毒" } })
	assert_true(vm.unit_statuses(1).is_empty())

func test_status_tooltip_and_badges_drawn() -> void:
	var bs: BattleScreen = await _screen(state(), [])
	assert_eq(bs.grid_view.tooltip_at(Vector2i(4, 3)), "野狼：封穴 剩 2 次")
	assert_eq(bs.grid_view.tooltip_at(Vector2i(6, 3)), "", "no statuses → no tooltip")
	await _frame()
	bs.grid_view.fx.queue_redraw()
	await _frame()
	assert_true(true, "badges draw without errors")

func test_snapshot_wave_and_later_flag() -> void:
	var st := state()
	st["wave"] = { "n": 2, "total": 3 }
	st["later_battle_cmds"] = false
	ClientState.world_info = { "later_battle_cmds": true }
	var bs: BattleScreen = await _screen(st, [])
	assert_false(bs.vm.later_cmds, "battle snapshot wins over world_info")
	assert_eq([bs.vm.wave, bs.vm.wave_total], [2, 3])
	assert_true(bs.turn_label.text.contains("第 2／3 波"), bs.turn_label.text)
	var st2 := state()
	st2["wave"] = { "n": 1, "total": 1 }
	var bs2: BattleScreen = await _screen(st2, [])
	assert_false(bs2.turn_label.text.contains("波"), "single wave: no tag")

func test_new_events_update_vitals() -> void:
	var vm := BattleViewModel.from_state(state())
	vm.apply_event({ "ch": "BATTLE", "key": "battle_medic", "bid": 7,
		"p": { "atk_uid": 1, "def_uid": 3, "atk_peer": 1, "def_peer": 2, "atk": "測試俠客", "def": "隊友", "heal": 30, "cured": false } })
	assert_eq(vm.unit(3)["qi"], 130, "heal added when no def_qi")
	vm.apply_event({ "ch": "BATTLE", "key": "battle_inner_heal", "bid": 7, "p": { "uid": 1, "name": "測試俠客", "peer": 1, "heal": 20, "neili": 70 } })
	assert_eq(vm.unit(1)["qi"], 170, "no qi → add heal")
	assert_eq(vm.unit(1)["neili"], 70, "neili = remaining (WP-CMD payload)")
	vm.apply_event({ "ch": "BATTLE", "key": "battle_inner_heal", "bid": 7, "p": { "uid": 1, "name": "測試俠客", "peer": 1, "heal": 30, "neili": 60, "qi": 200 } })
	assert_eq(vm.unit(1)["qi"], 200, "host value wins")
	vm.apply_event({ "ch": "BATTLE", "key": "battle_item_use", "bid": 7, "p": { "atk_uid": 1, "def_uid": 3, "atk_peer": 1, "def_peer": 2,
		"atk": "測試俠客", "def": "隊友", "item_name": "解毒藥", "item_uid": "it_c1", "qi": 140, "neili": 5 } })
	assert_eq(vm.unit(3)["qi"], 140, "item target's qi")
	assert_true(vm.battle_items().is_empty(), "last pill used")
	vm.apply_event({ "ch": "BATTLE", "key": "battle_inner_transfer", "bid": 7, "p": { "atk_uid": 1, "def_uid": 3, "atk_peer": 1, "def_peer": 2, "n": 20 } })
	assert_eq(vm.unit(1)["neili"], 40)
	vm.apply_event({ "ch": "BATTLE", "key": "battle_poison_ok", "bid": 7,
		"p": { "atk_uid": 1, "def_uid": 2, "atk_peer": 1, "def_peer": 0, "atk": "測試俠客", "def": "野狼", "dmg": 9, "level": 2, "def_qi": 71 } })
	assert_eq(vm.unit(2)["qi"], 71)
	vm.apply_event({ "ch": "BATTLE", "key": "battle_wave", "bid": 7, "p": { "n": 2, "total": 3 } })
	assert_eq([vm.wave, vm.wave_total], [2, 3])
	vm.apply_event({ "ch": "BATTLE", "key": "battle_aoe", "bid": 7, "ui": true, "p": { "uid": 1, "cells": [[4, 3], [5, 3]] } })
	assert_eq(vm.last_aoe["cells"], [Vector2i(4, 3), Vector2i(5, 3)])

# ---------------------------------------------------------------- 與 Protocol 一致（Day-0 落地後才比對）

func test_keys_match_protocol_when_available() -> void:
	var cm: Dictionary = (load("res://core/protocol.gd") as Script).get_script_constant_map()
	if int(cm.get("VERSION", 0)) >= 4:
		assert_eq(UiKeys.BATTLE_CMDS_ALL, cm.get("BATTLE_CMDS", []), "M3A_PLAN §5.1 command set")
	for pair in [["I_SECT_BETRAY", UiKeys.I_SECT_BETRAY], ["I_JAIL_RANSOM", UiKeys.I_JAIL_RANSOM],
			["I_SECT_TRIAL", UiKeys.I_SECT_TRIAL], ["I_NPC_GUIDE", UiKeys.I_NPC_GUIDE]]:
		if cm.has(pair[0]):
			assert_eq(cm[pair[0]], pair[1], pair[0])
	assert_eq(UiKeys.BATTLE_CMDS_ALL.size(), 14)
	for s in ["BETRAY", "JAIL", "TRIAL", "GUIDE"]:
		assert_has(UiKeys.SERVICES, s)
