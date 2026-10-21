extends "res://tests/test_case.gd"
## M3D_PLAN §3.5、§10.1（WP-COMBAT）test_ui_m3d_night：夜晚變暗（場景圖、小地圖、區域圖蓋深藍半透明，小地圖只亮目前房間
## 與相鄰房間）、背包有夜明珠（LIGHT）不變暗、設定 ui.night_dim 關掉不變暗；另含燈籠「默契」與合體默契視窗的接線。
## 有視窗時另存截圖到 K:/Project/JY-Mini-OL-Work/shots/m3d/WP-COMBAT/。

const SHOTS_DIR := "K:/Project/JY-Mini-OL-Work/shots/m3d/WP-COMBAT"
const Scenes := preload("res://tests/unit/test_ui_scenes.gd")

var _nodes: Array = []
var _saved_sheet: Variant = null
var _saved_view: Variant = null

func before_each() -> void:
	UiSettings.reset_for_tests(true)

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	var cs := tree.root.get_node_or_null("ClientState")
	if cs != null and _saved_sheet != null:
		cs.set("sheet", _saved_sheet)
	if cs != null and _saved_view != null:
		cs.set("region_view", _saved_view)
	_saved_sheet = null
	_saved_view = null
	await tree.process_frame

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _fake(s: Dictionary, v: Dictionary = {}) -> void:
	var cs := tree.root.get_node_or_null("ClientState")
	if cs == null:
		return
	if _saved_sheet == null:
		_saved_sheet = cs.get("sheet")
		_saved_view = cs.get("region_view")
	cs.set("sheet", s)
	if not v.is_empty():
		cs.set("region_view", v)

static func sheet(night: bool, items: Array = [], combo: Dictionary = { "partner_name": "", "moqi": 0, "peihe": 0, "era_on": true }) -> Dictionary:
	var s: Dictionary = Scenes.fake_sheet()
	var inv: Array = []
	var i := 0
	for id in items:
		i += 1
		inv.append({ "uid": "it_m3d_%d" % i, "id": id, "name": id, "n": 1, "tab": "OTHER" })
	var base: Array = (s.get("inventory", []) as Array).duplicate(true)
	s["inventory"] = base + inv
	var clk: Dictionary = (s.get("clock", {}) as Dictionary).duplicate()
	clk["night"] = night
	clk["text"] = "戌時一刻" if night else "午時一刻"
	s["clock"] = clk
	s["combo"] = combo
	return s

static func view() -> Dictionary:
	var v: Dictionary = Scenes.fake_view()
	v["players"] = [ { "peer": 2, "name": "古墓少女", "char_id": "ch_her", "align": "GOOD", "in_battle": false } ]
	return v

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for i in 3:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := tree.root.get_texture().get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	img.save_png(SHOTS_DIR.path_join(name + ".png"))

func _main() -> Control:
	var main: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	main.gate.set_sender(func(_kind, _args): return -1)
	return main

func test_rule_static() -> void:
	var s: Script = load("res://ui/game/main/main_screen.gd")
	assert_true(s.call("night_dim_on", sheet(true)), "夜裡變暗")
	assert_false(s.call("night_dim_on", sheet(false)), "白天不變暗")
	assert_false(s.call("night_dim_on", sheet(true, ["i_cb_yemingzhu"])), "有夜明珠不變暗")
	assert_true(s.call("has_light", sheet(false, ["c_mantou", "i_cb_yemingzhu"])))
	assert_false(s.call("has_light", sheet(false, ["c_mantou"])))
	UiSettings.set_value(UiKeys.SETTING_NIGHT_DIM, false)
	assert_false(s.call("night_dim_on", sheet(true)), "設定關掉")

func test_main_screen_night_veil() -> void:
	var main := await _main()
	var sh := sheet(true)
	_fake(sh, view())
	main.apply_view(view())
	main.apply_sheet(sh)
	assert_true(main.night_dimmed(), "夜裡：場景圖蓋深藍")
	assert_true(main.night_scene.visible and main.night_mini.visible and main.night_map.visible, "場景圖、小地圖、區域圖都蓋")
	assert_true(main.night_mini.fog_view == main.mini_map.view, "小地圖加霧")
	# M3d 審查（第 3 輪）：目前房間的「往XXX」出區箭頭與字在亮區裡
	var lit: Rect2 = main.night_mini.lit_rect()
	for er in main.mini_map.view.out_exit_screen_rects({ main.mini_map.view.focus_id(): true }):
		assert_true(lit.grow(1.0).encloses(er as Rect2), "出區字在亮區：%s ⊄ %s" % [er, lit])
	assert_eq(main.night_scene.get_index(), main.backdrop.get_index() + 1, "只蓋背景（聊天、卷軸的字不變暗）")
	assert_true(absf(UiKeys.NIGHT_DIM_COLOR.a - 0.35) < 0.001, "alpha 0.35")
	await _shot("05_night_dim")
	var lit_sh := sheet(true, ["i_cb_yemingzhu"])
	_fake(lit_sh)
	main.apply_sheet(lit_sh)
	assert_false(main.night_dimmed(), "背包有夜明珠：不變暗")
	assert_false(main.night_mini.visible)
	await _shot("06_night_with_pearl")
	main.apply_sheet(sh)
	assert_true(main.night_dimmed())
	UiSettings.set_value(UiKeys.SETTING_NIGHT_DIM, false)
	main._on_option_changed(UiKeys.SETTING_NIGHT_DIM, false)
	assert_false(main.night_dimmed(), "設定關掉立刻生效")
	var day := sheet(false)
	UiSettings.set_value(UiKeys.SETTING_NIGHT_DIM, true)
	main.apply_sheet(day)
	assert_false(main.night_dimmed(), "白天")

func test_combo_lantern_and_dialog() -> void:
	var main := await _main()
	var sent: Array = []
	main.gate.set_sender(func(kind, args):
		sent.append([kind, args])
		return -1)
	var sh := sheet(false)
	_fake(sh, view())
	main.apply_view(view())
	main.apply_sheet(sh)
	assert_true(main.lanterns.combo_lantern.visible, "1.0B：燈籠「默契」")
	assert_true(main.combo_dialog in main._dialogs(), "默契視窗在對話框層、互斥")
	main.lanterns.combo_requested.emit()
	assert_true(main.combo_dialog.visible)
	var b: Button = main.combo_dialog.find_child("Bond_古墓少女", true, false)
	assert_true(b != null, "同房玩家各一顆「建立默契」")
	await _shot("07_combo_dialog_bond")
	b.pressed.emit()
	assert_eq(sent.back(), ["combo_bond", { "target_char": "ch_her" }])
	# 對方的請求
	main.handle_event({ "ch": "SYSTEM", "key": "cb_bond_request", "ui": true, "p": { "from_char": "ch_her", "from_name": "古墓少女", "ttl_s": 60 } })
	assert_true(main.combo_dialog.visible)
	var acc: Button = main.combo_dialog.find_child("Accept", true, false)
	assert_true(acc != null)
	# M3d 審查（第 3 輪）：請求中的人不再列一次「建立默契」；接受／拒絕旁邊有倒數
	var dup = main.combo_dialog.find_child("Bond_古墓少女", true, false)
	assert_true(dup == null or not is_instance_valid(dup) or dup.is_queued_for_deletion(), "請求者不重複列出")
	var left: Label = main.combo_dialog.find_child("RequestLeft", true, false)
	assert_true(left != null and (left.text.contains("60 秒") or left.text.contains("59 秒")), "倒數：%s" % (left.text if left != null else "null"))
	await _shot("08_combo_request")
	acc.pressed.emit()
	assert_eq(sent.back(), ["combo_reply", { "from_char": "ch_her", "accept": true }])
	# 有夥伴：狀態與按鈕
	var sh2 := sheet(false, [], { "partner_name": "古墓少女", "partner_char": "ch_her", "moqi": 25, "peihe": 100, "next_drain_day": 5, "era_on": true })
	main.apply_sheet(sh2)
	var st: Label = main.combo_dialog.find_child("Status", true, false)
	assert_eq(st.text, "默契 25／100　配合度 100／100　下次扣點：第 5 日")
	var nb: Button = main.combo_dialog.find_child("Nurture", true, false)
	assert_false(nb.disabled, "配合度 100 可以培養感情")
	await _shot("09_combo_dialog_partner")
	nb.pressed.emit()
	assert_eq(sent.back(), ["combo_nurture", {}])
	(main.combo_dialog.find_child("Cancel", true, false) as Button).pressed.emit()
	(main.combo_dialog.find_child("CancelOk", true, false) as Button).pressed.emit()
	assert_eq(sent.back(), ["combo_cancel", {}])
	# 1.0A-only：不顯示
	main.apply_sheet(sheet(false, [], { "partner_name": "", "moqi": 0, "peihe": 0, "era_on": false }))
	assert_false(main.lanterns.combo_lantern.visible, "1.0A 世界沒有「默契」燈籠")

## M3d 審查：「默契」燈籠跟其他燈籠一樣高（60 px）
func test_combo_lantern_full_height() -> void:
	var lm := LanternMenu.new()
	_add(lm)
	await tree.process_frame
	assert_eq(lm.combo_lantern.custom_minimum_size.y, LanternMenu.LANTERN_SIZE.y)

## M3d 審查：懸賞名單與消災視窗進主畫面的視窗清單（Esc 關）；賞金獵人橫幅在視窗底下、甩掉／開打就收起、只有一條倒數
func test_law_windows_and_banner() -> void:
	var main := await _main()
	main.handle_event({ "key": UiKeys.E_BOUNTY_BOARD, "p": { "rows": [], "enabled": true, "npc_service": "BOARD" } })
	assert_true(main.bounty_dialog != null and main.bounty_dialog.visible, "名單打開")
	assert_true(main._dialogs().has(main.bounty_dialog), "在視窗清單裡")
	assert_true(main._close_dialogs(), "Esc 關得掉")
	assert_false(main.bounty_dialog.visible)
	main.handle_event({ "key": UiKeys.E_LAW_HUNTER_WARN, "p": { "npc_name": "捕頭", "warn_s": 3 } })
	assert_true(main.law_banner != null and main.law_banner.visible, "橫幅出現")
	assert_true(main.law_banner.get_index() < main.dialog_layer.get_index(), "橫幅在對話框層底下")
	var g: int = main._law_banner_gen
	main.handle_event({ "key": UiKeys.E_LAW_HUNTER_WARN, "p": { "npc_name": "捕頭", "warn_s": 3 } })
	assert_eq(main._law_banner_gen, g + 1, "新的警告換一代（舊的倒數停掉）")
	main.handle_event({ "key": UiKeys.E_LAW_HUNTER_ESCAPED, "p": { "npc_name": "捕頭" } })
	assert_false(main.law_banner.visible, "甩掉 → 收起")
	main.handle_event({ "key": UiKeys.E_LAW_HUNTER_WARN, "p": { "npc_name": "捕頭", "warn_s": 3 } })
	main.handle_event({ "key": UiKeys.E_LAW_HUNTER_ATTACK, "p": { "npc_name": "捕頭" } })
	assert_false(main.law_banner.visible, "追上開打 → 收起")

## M3d 審查（第 3 輪）：八卦泥陣（hide_exit_names）的小地圖不畫相鄰沒去過的「？」（原本畫在真正的方向上＝洩漏解法）；
## 一般房間照舊
func test_maze_minimap_no_question_marks() -> void:
	var model := { "by_id": {
		"m1": { "id": "m1", "exits": [{ "dir": "S", "to": "m2" }] },
		"m2": { "id": "m2", "hide_exit_names": true, "exits": [{ "dir": "N", "to": "m1" }, { "dir": "E", "to": "m3" },
			{ "dir": "W", "to": "m1", "oneway": true }] },
		"m3": { "id": "m3", "hide_exit_names": true, "exits": [{ "dir": "W", "to": "m2" }] } } }
	var f := MapData.fog(model, { "m2": true })
	assert_false((f["unknown"] as Dictionary).has("m3"), "陣裡：真正的下一間不畫「？」")
	var f2 := MapData.fog(model, { "m1": true })
	assert_true((f2["unknown"] as Dictionary).has("m2"), "陣口外：陣口照常畫「？」")
	var f3 := MapData.fog(model, { "m2": true, "m3": true })
	assert_true((f3["visible"] as Dictionary).has("m3"), "走過的照畫")
