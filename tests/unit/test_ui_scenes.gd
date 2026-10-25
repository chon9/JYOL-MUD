extends "res://tests/test_case.gd"
## WP-UI：每個 ui/game/**/*.tscn 都能 instantiate、加進樹、餵假資料（假 sheet、view、battle_state、事件）後
## 一幀內無錯誤，再釋放（M1_PLAN 6.1）。另測 UiKeys 的值、IntentGate 的鎖定與 intent 參數形狀。

const SCENES := [
	"res://ui/game/title/title_screen.tscn",
	"res://ui/game/char/char_select.tscn",
	"res://ui/game/char/char_create.tscn",
	"res://ui/game/main/main_screen.tscn",
	"res://ui/game/battle/battle_screen.tscn",
	"res://ui/game/rogue/rogue_screen.tscn",   # 江湖試煉（ROGUE_PLAN §5；整合者）
]

var _nodes: Array = []

func before_each() -> void:
	UiSettings.reset_for_tests(true)   # 介面設定只放記憶體，不碰使用者的 settings.json

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

func _frame() -> void:
	await tree.process_frame

static func fake_sheet() -> Dictionary:
	return {
		"char_id": "ch_1a2b3c4d", "name": "測試俠客", "gender": "M", "birth_month": 3, "birth_city": "xixia",
		"sect": "shaolin", "sect_name": "少林",
		"attrs": { "str": 22, "guts": 19, "wit": 26, "luck": 18, "cal": 19, "agi": 20, "con": 20 },
		"attrs_base": { "str": 22, "guts": 19, "wit": 24, "luck": 18, "cal": 19, "agi": 20, "con": 20 },
		"vitals": { "jing": 80, "jing_max": 92, "qi": 170, "qi_max": 180, "shen": 88, "shen_max": 88,
			"neili": 25, "neili_max": 50, "food": 96, "water": 94 },
		"carry": 14, "carry_max": 160,
		"combat_xp": 250, "learn_points": 40, "learn_points_cap": 65200, "lili": 0, "fame": 0,
		"morality": 0, "killing_intent": 0, "pk": 0, "money": 180,
		"art_level_cap": 10, "special_arts": 1, "special_arts_max": 16,
		"skills": [
			{ "id": "foxa", "name": "佛法", "kind": "SECT", "category": "", "level": 10, "prof": 1000, "next_prof": 1331 },
			{ "id": "sl_changquan", "name": "少林長拳", "kind": "ART", "category": "FIST", "level": 3, "prof": 30, "next_prof": 58 },
			{ "id": "basic_inner", "name": "基本內功", "kind": "BASIC", "category": "", "level": 2, "prof": 13, "next_prof": 65 },
			{ "id": "life_cooking", "name": "廚師", "kind": "LIFE", "category": "", "level": 1, "prof": 2, "next_prof": 8 },
			{ "id": "life_fishing", "name": "釣魚", "kind": "LIFE", "category": "", "level": 1, "prof": 2, "next_prof": 8 },
		],
		"inventory": [
			{ "uid": "it_0001", "id": "w_mudao", "name": "木刀", "tab": "WEAPON", "n": 1, "weight": 2,
			  "equipped_slot": "WEAPON", "usable": false, "equippable": true },
			{ "uid": "it_0002", "id": "a_bupao", "name": "布衣", "tab": "ARMOR", "n": 1, "weight": 2,
			  "equipped_slot": "ARMOR", "usable": false, "equippable": true },
			{ "uid": "it_0003", "id": "c_jingyao", "name": "精藥水", "tab": "OTHER", "n": 5, "weight": 1,
			  "equipped_slot": "", "usable": true, "equippable": false },
			{ "uid": "it_0004", "id": "w_chaidao", "name": "柴刀", "tab": "WEAPON", "n": 1, "weight": 3,
			  "equipped_slot": "", "usable": false, "equippable": true },
		],
		"equipped": { "WEAPON": "it_0001", "ARMOR": "it_0002" },
		"quests": [ { "id": "q_rabbit", "name": "狩獵事件：大兔皮", "giver_name": "武介山",
			"steps": [ { "text": "交給武介山 1 張大兔皮", "have": 0, "need": 1, "done": false } ] } ],
		"quests_done": ["q_rice"],
		"location": { "region": "xixia", "region_name": "西夏", "room": "xx_square", "room_name": "西夏廣場" },
		"respawn": { "room": "xx_gate_e", "room_name": "西夏東門" },
		"clock": { "text": "辰時三刻", "night": false, "day": 1 },
		"in_battle": false, "battle_id": 0,
	}

static func fake_view() -> Dictionary:
	return {
		"region": "xixia_wild", "region_name": "西夏郊外", "room": "xw_creek", "room_name": "小溪邊",
		"desc": "溪水潺潺。", "clock": "辰時三刻", "night": false,
		"exits": [ { "dir": "N", "label": "北", "to": "xw_grass", "to_name": "荒草坡", "locked": false },
			{ "dir": "IN", "label": "進", "to": "hs_hall", "to_name": "正氣堂", "locked": true } ],
		"npcs": [ { "id": "n_xw_fisher", "name": "漁夫", "kind": "FUNC", "services": ["TEACH"], "closed": false } ],
		"players": [ { "peer": 1, "name": "測試俠客", "char_id": "ch_1a2b3c4d" } ],
		"features": ["WATER", "STOVE"],
		"corpses": [ { "id": "cp_00aa11bb", "owner_name": "測試俠客", "mine": true, "n_items": 2 } ],
		"danger": true, "safe": false,
	}

func test_all_scenes_instantiate() -> void:
	for path in SCENES:
		assert_true(ResourceLoader.exists(path), "exists " + path)
		var ps := load(path) as PackedScene
		if not assert_true(ps != null, "load " + path):
			continue
		var n := ps.instantiate()
		assert_true(n is Control, "root is Control " + path)
		_add(n)
		await _frame()
		await _frame()
		assert_true(is_instance_valid(n) and n.is_inside_tree(), "alive " + path)
		n.queue_free()
		await _frame()

func test_router_scene_paths() -> void:
	var sr = tree.root.get_node("SceneRouter")
	for k in ["title", "char_select", "char_create", "main"]:
		assert_has(sr.SCENES, k)
		assert_true(ResourceLoader.exists(sr.SCENES[k]), k)

func test_main_screen_with_fake_data() -> void:
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.apply_sheet(fake_sheet())
	main.apply_view(fake_view())
	await _frame()
	assert_eq(main.scene_panel.room_label.text, "小溪邊")
	assert_true(main.status_bar.icon_text("money").contains("180"))
	assert_true(main.status_bar.bar_texts["qi"].text == "170/180")
	# 生活技能按鈕：WATER→垂釣、STOVE→烹煮（兩者都已學）
	var verbs: Array = []
	for b in main.scene_panel.life_box.get_children():
		if b is Button:
			verbs.append(b.text)
	assert_has(verbs, "垂釣")
	assert_has(verbs, "烹煮")
	# 面板切換
	for pid in UiKeys.PANELS:
		main.open_panel(pid)
		await _frame()
		assert_true(main.panels[pid].visible, pid)
	main.close_panel()
	assert_false(main.panel_frame.visible)
	# UI-only 事件開對話框
	main.handle_event({ "ch": "SCENE", "key": "talk_n_xw_fisher", "p": { "npc_name": "漁夫", "name": "測試俠客", "peer": 1 } })
	main.handle_event({ "ch": "SYSTEM", "key": "npc_menu", "ui": true, "p": { "npc": "n_xw_fisher", "npc_name": "漁夫",
		"services": ["TEACH", "SHOP", "INN", "TRAVEL", "QUEST", "JOIN"], "closed": false,
		"quests": [ { "id": "q_rabbit", "name": "大兔皮", "state": "AVAILABLE" } ],
		"routes": [ { "to_room": "jc_station", "to_name": "京城驛站", "price": 30 } ],
		"inn_price": 20, "join_sect": "shaolin", "sect_name": "少林" } })
	assert_true(main.npc_dialog.visible)
	assert_eq(main.npc_dialog.service_buttons.size(), 6)
	main.npc_dialog.show_routes()
	main.npc_dialog.show_quests()
	main.npc_dialog.show_join()
	main.handle_event({ "ch": "SYSTEM", "key": "shop_list", "ui": true, "p": { "npc": "n_x", "npc_name": "店小二",
		"items": [ { "id": "c_mantou", "name": "饅頭", "tab": "OTHER", "price": 5 } ],
		"sellable": [ { "uid": "it_0003", "id": "c_jingyao", "name": "精藥水", "n": 5, "price": 9 } ] } })
	assert_true(main.shop_dialog.visible)
	assert_false(main.npc_dialog.visible, "only one dialog")
	main.handle_event({ "ch": "SYSTEM", "key": "teach_list", "ui": true, "p": { "npc": "n_sl_huizhen", "npc_name": "慧真",
		"entries": [ { "skill": "sl_changquan", "name": "少林長拳", "kind": "ART", "cap": 100, "level": 0, "ok": false, "reason": "req_skill_min", "price": 0 },
			{ "skill": "basic_inner", "name": "基本內功", "kind": "BASIC", "cap": 140, "level": 2, "ok": true, "reason": "", "price": 0 },
			{ "skill": "life_fishing", "name": "釣魚", "kind": "LIFE", "cap": 100, "level": 0, "ok": true, "reason": "", "price": 50 } ] } })
	assert_true(main.learn_dialog.visible)
	await _frame()
	# 戰鬥疊層
	main.open_battle(_battle_state())
	await _frame()
	assert_true(main.battle != null and main.battle.is_inside_tree())
	main.close_battle({ "bid": 3, "result": "VICTORY", "you_died": false,
		"rewards": { "combat_xp": 5, "learn_points": 2, "money": 1, "items": [ { "id": "r_rabbitskin", "name": "兔皮", "n": 1 } ] }, "death": {} })
	await _frame()   # M3c 審查：結果晚一拍顯示（先讓同一輪的最後一批戰鬥事件進來）
	assert_true(main.battle.result_panel.visible)
	assert_true(main.battle.return_at_ms > 0, "auto return armed")
	assert_true(main.battle.result_detail.text.contains("兔皮"))
	main.battle.finished.emit()
	await _frame()
	assert_true(main.battle == null)

static func _battle_state() -> Dictionary:
	return {
		"bid": 3, "w": 12, "h": 8, "tick": 0, "wait_mode": true, "my_uid": 1,
		"escape": [[0, 6], [5, 0]],
		"units": [
			{ "uid": 1, "name": "測試俠客", "side": 0, "kind": "PLAYER", "peer": 1, "pos": [1, 3],
			  "qi": 180, "qi_max": 180, "neili": 20, "neili_max": 50, "jing": 92, "jing_max": 92,
			  "gauge": 0.0, "rate": 7.0, "state": "CHARGING", "move_range": 2,
			  "weapon": { "uid": "it_0001", "name": "木刀", "weapon_type": "BLADE" },
			  "weapon_options": [ { "uid": "it_0001", "name": "木刀", "weapon_type": "BLADE" } ],
			  "arts": [ { "id": "sl_changquan", "name": "少林長拳", "category": "FIST", "level": 10,
				"moves": [ { "id": "sl_cq_1", "name": "黑虎掏心", "unlock_level": 1, "range": 1, "cost_inner": 0, "cost_jing": 0, "usable": true },
					{ "id": "sl_cq_2", "name": "雙龍搶珠", "unlock_level": 30, "range": 1, "cost_inner": 5, "cost_jing": 0, "usable": false } ] } ] },
			{ "uid": 2, "name": "野兔", "side": 1, "kind": "MONSTER", "peer": 0, "pos": [2, 3],
			  "qi": 60, "qi_max": 60, "gauge": 0.0, "rate": 6.25, "state": "CHARGING" },
		],
	}

func test_battle_screen_commands_and_args() -> void:
	var bs = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	await _frame()
	bs.setup(_battle_state())
	var sent: Array = []
	bs.gate.set_sender(func(kind: String, args: Dictionary) -> int:
		sent.append([kind, args])
		return 1000 + sent.size())
	await _frame()
	assert_false(bs.command_bar.is_enabled(UiKeys.CMD_DEFEND), "not my turn yet")
	bs.apply_event({ "ch": "BATTLE", "key": "battle_await", "bid": 3, "ui": true, "p": { "units": [1], "deadline_tick": 200 } })
	bs.apply_event({ "ch": "BATTLE", "key": "battle_gauges", "bid": 3, "ui": true,
		"p": { "tick": 10, "units": [[1, 100.0, 7.0, false], [2, 60.0, 6.25, false]] } })
	bs._refresh()
	assert_true(bs.command_bar.is_enabled(UiKeys.CMD_DEFEND), "my turn")
	assert_true(bs.command_bar.is_enabled(UiKeys.CMD_ATTACK), "enemy adjacent")
	assert_false(bs.command_bar.is_enabled(UiKeys.CMD_FLEE), "not on escape tile")
	# 攻：點相鄰敵人
	bs._on_command(UiKeys.CMD_ATTACK)
	assert_eq(bs.grid_view.highlight, [Vector2i(2, 3)])
	bs._on_cell(Vector2i(2, 3))
	assert_eq(sent.size(), 1)
	assert_eq(sent[0][0], "battle_cmd")
	assert_eq(sent[0][1], { "battle_id": 3, "cmd": "ATTACK", "target": [2, 3] })
	bs.gate.resolve(1001, true, "")
	assert_false(bs.vm.is_my_turn(10.0), "submitted")
	# 新一輪：武 → 招式 → 目標
	bs.apply_event({ "ch": "BATTLE", "key": "battle_await", "bid": 3, "ui": true, "p": { "units": [1], "deadline_tick": 400 } })
	bs._on_command(UiKeys.CMD_ART)
	assert_true(bs.art_picker.visible)
	assert_eq(str(bs.art_picker.sel_move.get("id", "")), "sl_cq_1", "highest unlocked move preselected")
	bs.art_picker.slider.value = 7
	bs.art_picker._on_ok()
	assert_eq(bs.mode, UiKeys.CMD_ART)
	bs._on_cell(Vector2i(2, 3))
	assert_eq(sent.size(), 2)
	assert_eq(sent[1][1], { "battle_id": 3, "cmd": "ART", "art": "sl_changquan", "move": "sl_cq_1", "power_tenths": 7, "target": [2, 3] })
	bs.gate.resolve(1002, false, "not_ready")
	assert_true(bs.vm.is_my_turn(10.0), "failure keeps turn")
	# 防
	bs._on_command(UiKeys.CMD_DEFEND)
	assert_eq(sent[2][1], { "battle_id": 3, "cmd": "DEFEND" })
	bs.gate.resolve(1003, true, "")
	# 戰報顯示命中事件
	bs.apply_event({ "ch": "BATTLE", "key": "battle_kill", "bid": 3, "p": { "uid": 2, "name": "野兔", "peer": 0, "by": 1 } })
	assert_false(bs.vm.is_active(2))
	bs.show_result({ "bid": 3, "result": "DEFEAT", "you_died": true, "rewards": {},
		"death": { "rule": "STANDARD", "skill_losses": [ { "skill": "sl_changquan", "name": "少林長拳", "from": 10, "to": 9 } ],
			"n_items": 2, "money_lost": 0, "respawn_room_name": "少林山門" } })
	assert_eq(bs.result_label.text, "戰敗")
	assert_true(bs.result_detail.text.contains("少林長拳"))

## 戰場上每一格的中心點，滑鼠都要落到戰場本身：不能被戰報浮層、資訊列等蓋在上面的控制項吃掉
## （開場玩家站左上角，戰報浮層也在左上；以前戰報是 MOUSE_FILTER_PASS，點左上角的敵人沒反應）
func test_battle_cells_are_not_covered_by_overlays() -> void:
	# 主畫面上戰鬥只蓋 HUD 以上（1280×720 時約 1280×552）
	var holder := Control.new()
	holder.size = Vector2(1280, 552)
	_add(holder)
	var bs = (load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate()
	holder.add_child(bs)
	await _frame()
	bs.setup(_battle_state())
	bs.apply_event({ "ch": "BATTLE", "key": "battle_await", "bid": 3, "ui": true, "p": { "units": [1], "deadline_tick": 200 } })
	bs._refresh()
	# 戰報寫到出現捲軸（捲軸在浮層右緣，曾經擋住 (2,3) 那格）
	for i in 60:
		bs._log_plain("第 %d 行戰報" % i)
	await _frame()
	await _frame()
	assert_true(bs.log_text.get_v_scroll_bar().visible, "log long enough to show its scroll bar")
	# 審查：內建捲軸在右緣（一根貫穿戰場的棕色長條）→ 藏起來，改用左緣 6 px 細捲軸（§9.1）
	var lb: VScrollBar = bs.get_node("LeftScroll")
	assert_true(lb.visible, "thin left scroll bar shows when the log overflows")
	assert_true(lb.position.x < 10.0 and lb.size.x <= 6.0, "scroll bar sits on the left edge: %s %s" % [lb.position, lb.size])
	assert_eq(bs.log_text.get_v_scroll_bar().modulate.a, 0.0, "built-in right-edge bar is hidden")
	var gv: Control = bs.grid_view
	var blockers: Array = []
	_collect_mouse_controls(bs, gv, blockers)
	var grid_idx := _tree_order(bs, gv)
	var bad: PackedStringArray = []
	for x in 12:
		for y in 8:
			var at: Vector2 = gv.get_global_transform() * gv.cell_center(Vector2i(x, y))
			for c in blockers:
				if _tree_order(bs, c) > grid_idx and (c as Control).get_global_rect().has_point(at):
					bad.append("%s at %s" % [str(c.name if c.name != "" else c.get_class()), str(Vector2i(x, y))])
					break
	assert_eq(bad.size(), 0, ", ".join(bad.slice(0, 8)))

func _collect_mouse_controls(n: Node, skip: Node, out: Array) -> void:
	for c in n.get_children(true):   # 含內部子節點（RichTextLabel 的捲軸）
		if c == skip:
			continue
		if c is Control and (c as Control).is_visible_in_tree() and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			out.append(c)
		_collect_mouse_controls(c, skip, out)

## 繪製順序（樹的前序走訪序號）：大的畫在上面、先收到滑鼠
func _tree_order(root: Node, target: Node) -> int:
	var st: Array = [root]
	var i := 0
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n == target:
			return i
		i += 1
		var kids := n.get_children(true)
		kids.reverse()
		st.append_array(kids)
	return -1

func test_battle_hotkeys_ignore_modifiers() -> void:
	var bs = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	await _frame()
	bs.setup(_battle_state())
	bs.gate.set_sender(func(_kind: String, _args: Dictionary) -> int: return 2001)
	bs.apply_event({ "ch": "BATTLE", "key": "battle_await", "bid": 3, "ui": true, "p": { "units": [1], "deadline_tick": 200 } })
	bs._refresh()
	assert_true(bs.command_bar.is_enabled(UiKeys.CMD_MOVE), "my turn")
	var k := InputEventKey.new()
	k.keycode = KEY_1
	k.pressed = true
	k.ctrl_pressed = true
	bs._shortcut_input(k)
	assert_eq(bs.mode, "", "Ctrl+1 (屬性 shortcut) must not enter 移 mode")
	k.ctrl_pressed = false
	k.alt_pressed = true
	bs._shortcut_input(k)
	assert_eq(bs.mode, "", "Alt+1 ignored")
	k.alt_pressed = false
	bs._shortcut_input(k)
	assert_eq(bs.mode, UiKeys.CMD_MOVE, "plain 1 = 移")

func test_battle_result_hides_zero_rewards() -> void:
	assert_eq(BattleScreen.reward_line({ "combat_xp": 0, "learn_points": 0, "money": 0, "items": [] }), "")
	assert_eq(BattleScreen.reward_line({ "combat_xp": 5, "learn_points": 0, "money": 2 }), "實戰經驗 +5　銀兩 +2")
	var bs = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	await _frame()
	bs.setup(_battle_state())
	bs.show_result({ "bid": 3, "result": "DEFEAT", "you_died": true,
		"rewards": { "combat_xp": 0, "learn_points": 0, "money": 0, "items": [] },
		"death": { "rule": "STANDARD", "skill_losses": [], "n_items": 0, "money_lost": 0, "respawn_room_name": "西夏廣場" } })
	assert_false(bs.result_detail.text.contains("+0"), bs.result_detail.text)
	assert_true(bs.result_detail.text.begins_with("你死了。"), bs.result_detail.text)

func _npc_menu_event(refresh := false) -> Dictionary:
	var p := { "npc": "n_xw_fisher", "npc_name": "漁夫", "services": ["QUEST"], "closed": false,
		"quests": [ { "id": "q_rabbit", "name": "大兔皮", "state": "ACTIVE" } ], "routes": [], "inn_price": 0,
		"join_sect": "", "sect_name": "" }
	if refresh:
		p["refresh"] = true
	return { "ch": "SYSTEM", "key": "npc_menu", "ui": true, "p": p }

func _key(code: int, ctrl := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	return k

func test_main_screen_panels_and_dialogs_are_exclusive() -> void:
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.apply_sheet(fake_sheet())
	main.apply_view(fake_view())
	main.handle_event(_npc_menu_event())
	assert_true(main.npc_dialog.visible)
	# 對話框開著時點「屬性」：對話框關掉、面板打開（不會疊在對話框下面）
	main.toggle_panel("attributes")
	assert_true(main.panel_frame.visible)
	assert_false(main.npc_dialog.visible, "dialog closed when a panel opens")
	# 面板開著時開對話框：面板關掉
	main.handle_event(_npc_menu_event())
	assert_true(main.npc_dialog.visible)
	assert_false(main.panel_frame.visible, "panel closed when a dialog opens")
	# ACTIVE 任務沒有交付鈕
	main.npc_dialog.show_quests()
	var turn_in := false
	for c in main.npc_dialog.detail_box.find_children("*", "Button", true, false):
		if (c as Button).text == "交付":
			turn_in = true
	assert_false(turn_in, "no 交付 for an ACTIVE quest")
	# Esc 關最上面的對話框
	main._shortcut_input(_key(KEY_ESCAPE))
	assert_false(main.npc_dialog.visible)
	# refresh 的選單不會重開已關的對話框
	main.handle_event(_npc_menu_event(true))
	assert_false(main.npc_dialog.visible, "refresh does not reopen")
	# 戰鬥中 Ctrl+N／M 不開面板
	main.open_battle(_battle_state())
	await _frame()
	main._shortcut_input(_key(KEY_1, true))
	main._shortcut_input(_key(KEY_M))
	assert_false(main.panel_frame.visible, "no panels during battle")

func test_main_screen_esc_releases_chat_focus() -> void:
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.apply_sheet(fake_sheet())
	main.apply_view(fake_view())
	var input: LineEdit = main.message_log.input
	input.grab_focus()
	await _frame()
	assert_true(input.has_focus())
	main._shortcut_input(_key(KEY_M))
	assert_false(main.panel_frame.visible, "typing: M does not open the map")
	main._shortcut_input(_key(KEY_ESCAPE))
	assert_false(input.has_focus(), "Esc releases the chat box")
	main._shortcut_input(_key(KEY_M))
	assert_true(main.panel_frame.visible and main.map_panel.visible, "M works after Esc")
	main._shortcut_input(_key(KEY_ESCAPE))
	assert_false(main.panel_frame.visible)
	# 聊天框自己收到 Esc 也放開焦點
	input.grab_focus()
	await _frame()
	input.gui_input.emit(_key(KEY_ESCAPE))
	assert_false(input.has_focus(), "LineEdit Esc handler")

func test_main_screen_has_mini_map() -> void:
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.apply_sheet(fake_sheet())
	main.apply_view(fake_view())
	await _frame()
	assert_true(main.mini_map != null and main.mini_map.is_visible_in_tree(), "mini map on the main screen")
	assert_eq(main.mini_map.view.current, str(fake_view().get("room", "")))
	# AUTHENTIC_UI_SPEC §10：右上、燈籠左邊；房間圖至少 120 高（UI driver 也要求）
	assert_true(main.mini_map.size.x >= 200.0 and main.mini_map.view.size.y >= 120.0, "mini map size %s view %s" % [str(main.mini_map.size), str(main.mini_map.view.size)])
	assert_true(main.mini_map.position.x > main.size.x * 0.6 and main.mini_map.position.y < 20.0, "top right")
	main.mini_map.open_requested.emit()
	assert_true(main.panel_frame.visible and main.map_panel.visible, "大地圖(M) button opens the map panel")

func test_char_create_alloc_and_args() -> void:
	var cc = _add((load("res://ui/game/char/char_create.tscn") as PackedScene).instantiate())
	await _frame()
	assert_true(cc.btn_create.disabled, "no roll yet")
	assert_true(cc.city_opt.item_count >= 1, "birth cities")
	cc.apply_roll({ "str": 20, "guts": 19, "wit": 21, "luck": 19, "cal": 19, "agi": 20, "con": 20, "total": 138, "peer": 1 })
	cc.name_edit.text = "測試俠客"
	for i in 6:
		cc._on_alloc("wit", 1)   # 第 6 次超過 5 點被擋
	assert_eq(cc.remaining(), 0)
	assert_eq(int(cc.alloc["wit"]), 5)
	cc.refresh()
	assert_false(cc.btn_create.disabled)
	var a: Dictionary = cc.build_args()
	assert_eq(a["alloc"], { "wit": 5 })
	assert_eq(a["gender"], "M")
	assert_eq(a["birth_month"], 1)
	assert_type(a["birth_month"], TYPE_INT)
	assert_true(a["birth_city"] != "" and a["birth_city"] != "jingcheng")
	cc._on_alloc("wit", -1)
	assert_true(cc.btn_create.disabled, "sum must be 5")

func test_char_select_list() -> void:
	var cs = _add((load("res://ui/game/char/char_select.tscn") as PackedScene).instantiate())
	await _frame()
	cs.apply_list([
		{ "char_id": "ch_1", "name": "甲", "gender": "M", "sect_name": "少林", "combat_xp": 250, "room_name": "少林山門" },
		{ "char_id": "ch_2", "name": "乙", "gender": "F", "sect_name": "", "combat_xp": 0, "room_name": "大理" },
		{ "char_id": "ch_3", "name": "丙", "gender": "F", "sect_name": "", "combat_xp": 0, "room_name": "大理" },
	])
	assert_true(cs.btn_create.disabled, "3 chars → create disabled")
	cs.apply_list([])
	assert_false(cs.btn_create.disabled)

## AUTHENTIC_UI_SPEC §9：分頁拿掉，改成頻道開關（千里傳音關掉時聊天不顯示）；500 則上限；清除
func test_message_log_channels_and_limit() -> void:
	var ml := MessageLog.new()
	_add(ml)
	await _frame()
	var base := ml.entries.size()
	# 測試環境沒有 session（my_peer 0），用別的 peer 讓 TextRenderer 選 other 變體
	ml.add_event({ "ch": "BATTLE", "key": "battle_kill", "p": { "uid": 2, "name": "野兔", "peer": 7 } })
	ml.add_event({ "ch": "SYSTEM", "key": "npc_menu", "p": {}, "ui": true })   # UI-only：不顯示
	ml.add_system("系統訊息")
	ml.add_event({ "ch": "CHAT_WORLD", "key": "chat", "p": { "from": "某俠客", "from_peer": 9, "text": "有人組隊嗎" } })
	assert_eq(ml.entries.size(), base + 3)
	assert_eq(ml.visible_lines(), ml.entries.size())
	assert_eq(MessageLog.CHANNELS.size(), 13, "13 original channels")
	assert_false(ml.channel_enabled("拍賣資訊"), "auction off by default")
	ml.set_channel_enabled("千里傳音", false)
	assert_eq(ml.visible_lines(), ml.entries.size() - 1, "world chat hidden when 千里傳音 is off")
	assert_false(ml.text.get_parsed_text().contains("有人組隊嗎"))
	ml.set_channel_enabled("千里傳音", true)
	assert_true(ml.text.get_parsed_text().contains("有人組隊嗎"))
	for i in 600:
		ml.add_system("第 %d 行" % i)
	assert_eq(ml.entries.size(), UiKeys.LOG_MAX_LINES)
	ml.clear()
	assert_eq(ml.visible_lines(), 0, "螢幕對話清除")


func test_intent_gate_locks_until_result() -> void:
	var g := IntentGate.new()
	_add(g)
	var b := Button.new()
	_add(b)
	var results: Array = []
	g.set_sender(func(_k, _a): return 77)
	var seq := g.send("look", {}, [b], func(ok, reason): results.append([ok, reason]))
	assert_eq(seq, 77)
	assert_true(b.disabled, "locked")
	assert_true(g.is_pending("look"))
	g._on_intent_result(78, true, "")
	assert_true(b.disabled, "other seq ignored")
	g._on_intent_result(77, false, "not_here")
	assert_false(b.disabled, "unlocked")
	assert_eq(results, [[false, "not_here"]])
	# 沒有連線
	g.set_sender(func(_k, _a): return -1)
	g.send("look", {}, [b], func(ok, reason): results.append([ok, reason]))
	assert_false(b.disabled)
	assert_eq(results[1], [false, "not_connected"])

func test_intent_gate_timeout() -> void:
	var g := IntentGate.new()
	_add(g)
	var b := Button.new()
	_add(b)
	g.set_sender(func(_k, _a): return 5)
	g.send("look", {}, [b])
	g._pending[5]["deadline_ms"] = Time.get_ticks_msec() - 1
	await _frame()
	await _frame()
	assert_false(b.disabled, "timeout unlocks")
	assert_eq(g.pending_count(), 0)

func test_ui_keys_match_contract() -> void:
	assert_eq(UiKeys.ALL_INTENTS.size(), 34)
	for k in ["char_list", "char_roll", "char_create", "char_select", "char_delete", "look", "move", "travel", "talk",
			"shop_list", "buy", "sell", "learn_list", "learn", "self_study", "join_sect", "inn_rest", "set_respawn",
			"meal", "fight", "use_item", "equip", "unequip", "drop_item", "meditate", "exert", "work",
			"quest_accept", "quest_turn_in", "quest_abandon", "loot_corpse", "battle_cmd"]:
		assert_has(UiKeys.ALL_INTENTS, k)
	assert_eq(UiKeys.SERVICE_LABELS["SHOP"], "交易")
	assert_eq(UiKeys.SERVICE_LABELS["TEACH"], "請教")
	assert_eq(UiKeys.SERVICE_LABELS["INN"], "住宿")
	assert_eq(UiKeys.SERVICE_LABELS["RESPAWN"], "記錄")
	assert_eq(UiKeys.SERVICE_LABELS["TRAVEL"], "驛站")
	assert_eq(UiKeys.SERVICE_LABELS["JOIN"], "拜師")
	assert_eq(UiKeys.SERVICE_LABELS["QUEST"], "任務")
	assert_eq(UiKeys.SERVICE_LABELS["MEAL"], "用齋")
	assert_eq(UiKeys.SERVICE_LABELS["FIGHT"], "切磋")
	assert_eq(UiKeys.DIRS.size(), 12)
	for d in UiKeys.DIRS:
		assert_has(UiKeys.DIR_LABELS, d)
	assert_eq(UiKeys.dir_label("NE"), "東北")
	assert_eq(UiKeys.dir_label("OUT"), "出")
	assert_eq(UiKeys.BATTLE_CMDS, ["MOVE", "ATTACK", "ART", "DEFEND", "REST", "EQUIP", "FLEE"])

func test_scene_panel_sends_intents() -> void:
	var sp := ScenePanel.new()
	_add(sp)
	await _frame()
	var g := IntentGate.new()
	_add(g)
	var sent: Array = []
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		return -1)
	sp.gate = g
	sp.apply_sheet(fake_sheet())
	sp.apply_view(fake_view())
	var b := Button.new()
	_add(b)
	sp._on_move("N", b)
	sp._on_talk("n_xw_fisher", b)
	sp._on_loot("cp_00aa11bb", b)
	sp._on_work("life_fishing", "", b)
	sp._on_work("life_cooking", "rc_baifan", b)
	assert_eq(sent[0], ["move", { "dir": "N" }])
	assert_eq(sent[1], ["talk", { "npc": "n_xw_fisher" }])
	assert_eq(sent[2], ["loot_corpse", { "corpse_id": "cp_00aa11bb" }])
	assert_eq(sent[3], ["work", { "skill": "life_fishing" }])
	assert_eq(sent[4], ["work", { "skill": "life_cooking", "recipe": "rc_baifan" }])
	sp._open_recipes(1)
	assert_true(sp.recipe_panel.visible)
