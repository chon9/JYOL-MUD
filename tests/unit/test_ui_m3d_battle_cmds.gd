extends "res://tests/test_case.gd"
## M3D_PLAN §3.1–3.4、§10.1（WP-COMBAT）test_ui_m3d_battle_cmds：圓盤的「閃」「輕」——啟用與提示（dodge_cmd、later_battle_cmds、
## 內力）、送出的 battle_cmd 形狀、輕功小選單與飛身落點、快捷鍵 Shift+4／Shift+5、烙跑鞋的「逃」、VM 與戰場對新事件的反應
## （閃、飛身、脫身、合體金字與光帶）。有視窗時另存截圖到 K:/Project/JY-Mini-OL-Work/shots/m3d/WP-COMBAT/。

const SHOTS_DIR := "K:/Project/JY-Mini-OL-Work/shots/m3d/WP-COMBAT"
const M3A := preload("res://tests/unit/test_ui_m3a_battle.gd")

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

## M3a 的假快照（我在 (3,3)、野狼 (4,3)、隊友 (3,4)、山賊 (6,3)）加上 M3d 欄位
static func state(extra_me: Dictionary = {}, top: Dictionary = {}) -> Dictionary:
	var me := { "cmd_avail": { "POISON": true, "MEDIC": true, "HIDDEN": true, "FORMATION": true,
		"INNER": ["HEAL", "TRANSFER"], "ACUPOINT": true, "ITEM": true, "DODGE": true, "QING": ["JUMP", "ESCAPE"] } }
	me.merge(extra_me, true)
	var st := M3A.state(me)
	st.merge(top, true)
	return st

func _screen(st: Dictionary, sent: Array) -> BattleScreen:
	var bs: BattleScreen = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
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

func _shot(name: String, wait_s := 0.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if wait_s > 0.0:
		await tree.create_timer(wait_s).timeout
	for i in 3:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := tree.root.get_texture().get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	img.save_png(SHOTS_DIR.path_join(name + ".png"))

# ---------------------------------------------------------------- 圓盤

func test_disc_layout_and_glyphs() -> void:
	assert_eq(UiKeys.CMD_DISC_ROWS[0].slice(0, 3), ["防", "閃", "內"], "閃在防後面")
	assert_eq(UiKeys.CMD_BY_GLYPH["閃"], UiKeys.CMD_DODGE)
	assert_eq(UiKeys.CMD_BY_GLYPH["輕"], UiKeys.CMD_QING)
	assert_false("輕" in UiKeys.CMD_LOCKED_LABELS, "輕不再鎖住")
	var cb := CommandBar.new()
	_add(cb)
	await tree.process_frame
	assert_true(cb.buttons.has(UiKeys.CMD_DODGE) and cb.buttons.has(UiKeys.CMD_QING))
	assert_true((cb.discs["閃"] as Button).tooltip_text.contains("Shift+4"))

func test_enabled_and_tips() -> void:
	ClientState.world_info = { "later_battle_cmds": true }
	var bs: BattleScreen = await _screen(state(), [])
	assert_true(bs.command_bar.is_enabled(UiKeys.CMD_DODGE), "閃")
	assert_true(bs.command_bar.is_enabled(UiKeys.CMD_QING), "輕")
	await _shot("01_disc_dodge_qing")
	# 規則 dodge_cmd 關（later_official）
	var bs2: BattleScreen = await _screen(state({}, { "dodge_cmd": false }), [])
	assert_false(bs2.command_bar.is_enabled(UiKeys.CMD_DODGE))
	assert_true((bs2.command_bar.buttons[UiKeys.CMD_DODGE] as Button).tooltip_text.contains(UiKeys.DODGE_OFF_TIP))
	# later_battle_cmds 關（classic_strict）
	var bs3: BattleScreen = await _screen(state({}, { "later_battle_cmds": false }), [])
	assert_false(bs3.command_bar.is_enabled(UiKeys.CMD_QING))
	assert_true((bs3.command_bar.buttons[UiKeys.CMD_QING] as Button).tooltip_text.contains(UiKeys.LATER_CMDS_TIP))
	assert_true(bs3.command_bar.is_enabled(UiKeys.CMD_DODGE), "閃是 2001 的，不受 later_battle_cmds 影響")
	# 內力不夠：cmd_avail.QING 空
	var st4 := state()
	st4.units[0].cmd_avail.QING = []
	var bs4: BattleScreen = await _screen(st4, [])
	assert_false(bs4.command_bar.is_enabled(UiKeys.CMD_QING))
	assert_true((bs4.command_bar.buttons[UiKeys.CMD_QING] as Button).tooltip_text.contains("內力不足"))

func test_dodge_sends() -> void:
	var sent: Array = []
	var bs: BattleScreen = await _screen(state(), sent)
	(bs.command_bar.buttons[UiKeys.CMD_DODGE] as Button).pressed.emit()
	assert_eq(sent.back(), ["battle_cmd", { "battle_id": 7, "cmd": "DODGE" }])

func test_qing_menu_jump_and_escape() -> void:
	var sent: Array = []
	var bs: BattleScreen = await _screen(state(), sent)
	(bs.command_bar.buttons[UiKeys.CMD_QING] as Button).pressed.emit()
	assert_true(bs.cmd_menu.visible, "輕功小選單")
	# M3d 審查第三輪：可用時也寫出耗多少內力（飛身越敵 10 + 2 × 移動範圍 2 = 14）
	assert_eq(bs.menu_texts(), ["飛身越敵（耗內力 14）", "輕功脫身（耗內力 30）"])
	# 小選單開在「輕」鈕附近、不蓋戰鬥訊息框
	var qb := bs.cmd_button_rect(UiKeys.CMD_QING)
	var mr := Rect2(bs.cmd_menu.position, bs.cmd_menu.size)
	assert_true(qb.has_area(), "找得到輕鈕")
	assert_true(mr.get_center().distance_to(qb.get_center()) < 420.0, "選單 %s 離輕鈕 %s 不遠" % [mr, qb])
	var lr := Rect2(bs.log_text.global_position - bs.global_position, bs.log_text.size)
	assert_false(mr.intersects(lr), "選單 %s 不蓋戰鬥訊息 %s" % [mr, lr])
	await _shot("02_qing_menu")
	bs._qing_chosen("JUMP")
	assert_eq(bs.mode, UiKeys.CMD_QING)
	var hl: Array = bs.grid_view.highlight
	assert_true(hl.has(Vector2i(5, 3)), "越過野狼落在 (5,3)")
	assert_true(hl.has(Vector2i(5, 4)), "距離 3（移動範圍 2 + 1）")
	assert_false(hl.has(Vector2i(6, 3)), "有人的格子不行")
	assert_false(hl.has(Vector2i(7, 3)), "距離 4 不行")
	await _shot("03_qing_jump_targets")
	bs._on_cell(Vector2i(5, 3))
	assert_eq(sent.back(), ["battle_cmd", { "battle_id": 7, "cmd": "QING", "mode": "JUMP", "target": [5, 3] }])
	_my_turn(bs)
	bs._qing_chosen("ESCAPE")
	assert_eq(sent.back(), ["battle_cmd", { "battle_id": 7, "cmd": "QING", "mode": "ESCAPE" }])

func test_qing_menu_blocks() -> void:
	var st := state()
	st.units[0].cmd_avail.QING = ["JUMP"]
	var bs: BattleScreen = await _screen(st, [])
	assert_eq(bs.qing_block("JUMP"), "")
	assert_eq(bs.qing_block("ESCAPE"), UiKeys.QING_NO_ESCAPE_TIP, "內力夠但這場不能脫身（任務戰、試煉）")
	st.units[0].neili = 10
	var bs2: BattleScreen = await _screen(st, [])
	assert_eq(bs2.qing_block("ESCAPE"), "內力不足，需 %d" % UiKeys.QING_ESCAPE_COST, "M3d 審查：寫出需要的內力")

func test_hotkeys() -> void:
	for pair in [[KEY_4, UiKeys.CMD_DODGE], [KEY_5, UiKeys.CMD_QING]]:
		var k := InputEventKey.new()
		k.pressed = true
		k.shift_pressed = true
		k.keycode = pair[0]
		assert_eq(BattleScreen.hotkey_cmd(k), pair[1])
	var d := InputEventKey.new()
	d.pressed = true
	d.shift_pressed = true
	d.keycode = KEY_DOLLAR
	assert_eq(BattleScreen.hotkey_cmd(d), UiKeys.CMD_DODGE, "Shift+4 打出 $ 的鍵盤")

func test_flee_anywhere() -> void:
	var bs: BattleScreen = await _screen(state(), [])
	assert_false(bs.command_bar.is_enabled(UiKeys.CMD_FLEE), "沒穿鞋要站逃跑格")
	var bs2: BattleScreen = await _screen(state({ "flee_anywhere": true }), [])
	assert_true(bs2.command_bar.is_enabled(UiKeys.CMD_FLEE), "穿烙跑鞋任何格子都能逃")

# ---------------------------------------------------------------- 事件

func test_vm_events() -> void:
	var bs: BattleScreen = await _screen(state(), [])
	var vm := bs.vm
	bs.apply_event({ "ch": "BATTLE", "key": "battle_dodge", "bid": 7, "p": { "uid": 1, "name": "測試俠客", "peer": 1 } })
	assert_true(vm.is_dodging(1))
	bs.apply_event({ "ch": "BATTLE", "key": "battle_defend", "bid": 7, "p": { "uid": 1, "name": "測試俠客", "peer": 1 } })
	assert_false(vm.is_dodging(1), "下次行動就不閃了")
	bs.apply_event({ "ch": "BATTLE", "key": "battle_qing_jump", "bid": 7,
		"p": { "uid": 1, "name": "測試俠客", "peer": 1, "from": [3, 3], "to": [5, 3], "neili": 66 } })
	assert_eq(vm.unit(1).pos, Vector2i(5, 3))
	assert_eq(int(vm.unit(1).neili), 66)
	bs.apply_event({ "ch": "BATTLE", "key": "battle_combo", "bid": 7, "p": { "a": "測試俠客", "b": "隊友", "a_uid": 1, "b_uid": 3,
		"a_peer": 1, "b_peer": 2, "art_name": "玉女素心劍法", "dmg": 40, "atk_uid": 1, "atk": "測試俠客", "atk_peer": 1,
		"def_uid": 2, "def": "野狼", "def_peer": 0, "def_qi": 40, "cat": "SWORD" } })
	assert_eq(int(vm.unit(2).qi), 40, "合體一擊扣氣")
	assert_eq(str(vm.last_combo.get("art_name", "")), "玉女素心劍法")
	var found := false
	for it in bs.grid_view.fx.items:
		if str(it.get("type", "")) == "combo" and str(it.get("text", "")) == UiKeys.COMBO_BANNER_FMT % "玉女素心劍法":
			found = true
	assert_true(found, "金色大字「合體技・玉女素心劍法！」與光帶")
	assert_true(bs.log_plain_lines().size() >= 1)
	bs.apply_event({ "ch": "BATTLE", "key": "battle_qing_escape", "bid": 7, "p": { "uid": 3, "name": "隊友", "peer": 2, "neili": 10 } })
	assert_eq(str(vm.unit(3).state), "FLED", "脫身＝離場")

func test_combo_banner_text_template() -> void:
	var tpl: Dictionary = UiClient.templates().get("battle_combo", {})
	assert_true(str(tpl.get("self", "")).contains("{art_name}"), "battle_combo 模板")
	var e := { "ch": "BATTLE", "key": "battle_combo", "bid": 7, "p": { "a": "甲", "b": "乙", "art_name": "玉女素心劍法", "dmg": 40,
		"atk_peer": 99, "def_peer": 0, "def": "野狼" } }
	assert_true(TextRenderer.render_plain(e, 1, UiClient.templates()).contains("合體技「玉女素心劍法」"))

## 合體一擊：金色大字＋光帶（只送這一個事件，動畫不排在別的後面）
func test_combo_banner_draws() -> void:
	var st := state()
	st.units[1].pos = [4, 3]
	var bs: BattleScreen = await _screen(st, [])
	bs.apply_event({ "ch": "BATTLE", "key": "battle_combo", "bid": 7, "p": { "a": "測試俠客", "b": "隊友", "a_uid": 1, "b_uid": 3,
		"a_peer": 1, "b_peer": 2, "art_name": "玉女素心劍法", "dmg": 40, "atk_uid": 1, "atk": "測試俠客", "atk_peer": 1,
		"def_uid": 2, "def": "野狼", "def_peer": 0, "def_qi": 40, "cat": "SWORD" } })
	await tree.create_timer(0.35).timeout
	assert_eq(bs.grid_view.fx.combo_banners(), [UiKeys.COMBO_BANNER_FMT % "玉女素心劍法"], "畫面上有金字")
	await _shot("04_combo_banner")
