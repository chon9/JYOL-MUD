extends "res://tests/test_case.gd"
## M3c WP-LOOKS 介面（M3C_PLAN §3.4）：LookPicker 依性別過濾、鍵盤；創角 build_args 帶 look、性別切換重設；
## 屬性視窗頭像區與「更換造型」；LookDialog 送出的 set_look 形狀；主畫面接線；選角列表立繪；對話框剪影後援。

const Scenes := preload("res://tests/unit/test_ui_scenes.gd")

var _nodes: Array = []
var _saved_sheet: Variant = null

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
	_saved_sheet = null
	await tree.process_frame

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _fake_sheet(s: Dictionary) -> void:
	var cs := tree.root.get_node_or_null("ClientState")
	if cs == null:
		return
	if _saved_sheet == null:
		_saved_sheet = cs.get("sheet")
	cs.set("sheet", s)

func _gate(sent: Array, ok := true, reason := "") -> IntentGate:
	var g := IntentGate.new()
	_add(g)
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		var seq := sent.size()
		g.resolve.call_deferred(seq, ok, reason)
		return seq)
	return g

func _frames(n := 2) -> void:
	for i in n:
		await tree.process_frame

# ---------------------------------------------------------------- LookPicker

func test_picker_filters_by_gender() -> void:
	var p := LookPicker.new()
	_add(p)
	await _frames()
	assert_eq(p.cells.size(), 9, "9 格（0 號布衣＋8 種）")
	assert_eq(p.cells.map(func(c): return c.look_name), Looks.NAMES_M)
	assert_eq(p.cells[0].art, "player_m")
	assert_eq(p.cells[5].art, "look_m05")
	p.set_gender("F")
	assert_eq(p.cells.map(func(c): return c.look_name), Looks.NAMES_F, "切換性別換成女性的 9 種")
	assert_eq(p.cells.map(func(c): return c.art), ["player_f", "look_f01", "look_f02", "look_f03", "look_f04", "look_f05", "look_f06", "look_f07", "look_f08"])
	for c in p.cells:
		assert_true(c.texture != null, "%s 有 idle 立繪" % c.art)
	# 每格 ≥ 150×150 的立繪
	for c in p.cells:
		var pr: Rect2 = c.portrait_rect()
		assert_true(pr.size.x >= 150.0 and pr.size.y >= 150.0, "portrait %s" % str(pr.size))
	assert_eq(p.columns, 3, "3×3")

func test_picker_selection_and_keyboard() -> void:
	var p := LookPicker.new()
	_add(p)
	await _frames()
	var got: Array = []
	p.look_selected.connect(func(i): got.append(i))
	p.set_selected(4)
	assert_eq(p.selected, 4)
	assert_true(p.cells[4].is_selected and not p.cells[0].is_selected, "選中框")
	assert_eq(got, [], "程式設定不發訊號")
	p.cells[7].pressed.emit(7)
	assert_eq(p.selected, 7)
	assert_eq(got, [7], "點選發 look_selected")
	assert_true(p.handle_key(KEY_1))
	assert_eq(p.selected, 0, "1 → 第 1 格")
	assert_true(p.handle_key(KEY_9))
	assert_eq(p.selected, 8)
	assert_true(p.handle_key(KEY_UP))
	assert_eq(p.selected, 5, "上移一列")
	assert_true(p.handle_key(KEY_LEFT))
	assert_eq(p.selected, 4)
	assert_true(p.handle_key(KEY_DOWN))
	assert_eq(p.selected, 7)
	assert_true(p.handle_key(KEY_DOWN))
	assert_eq(p.selected, 7, "最下列不再往下")
	assert_true(p.handle_key(KEY_RIGHT))
	assert_eq(p.selected, 8)
	assert_true(p.handle_key(KEY_RIGHT))
	assert_eq(p.selected, 0, "循環")
	assert_false(p.handle_key(KEY_A))
	p.set_selected(42)
	assert_eq(p.selected, 0, "不合法 → 0")

func test_picker_static_helpers() -> void:
	assert_eq(LookPicker.sheet_look_ref({ "look": "look_f02", "gender": "F" }), "look_f02")
	assert_eq(LookPicker.sheet_look_ref({ "gender": "F" }), "player_f", "舊主機沒有 look")
	assert_eq(LookPicker.sheet_look_ref({}), "player_m")
	assert_true(LookPicker.sheet_look_texture({ "look": "zzz_unknown" }) != null, "找不到 → player_m")

# ---------------------------------------------------------------- 創角

func test_char_create_sends_look_and_resets_on_gender() -> void:
	var cc = _add((load("res://ui/game/char/char_create.tscn") as PackedScene).instantiate())
	await _frames()
	assert_true(cc.picker != null and cc.picker.visible, "造型選擇器預設顯示")
	assert_false(cc.birth_map.visible, "出生地圖在第二個分頁")
	assert_eq(cc.picker.gender, "M")
	cc.apply_roll({ "str": 20, "guts": 19, "wit": 21, "luck": 19, "cal": 19, "agi": 20, "con": 20, "total": 138 })
	cc.name_edit.text = "造型俠客"
	for i in 5:
		cc._on_alloc("str", 1)
	cc.picker.cells[5].pressed.emit(5)
	assert_eq(cc.look_label.text, "造型：壯漢")
	var a: Dictionary = cc.build_args()
	assert_eq(a["look"], 5, "char_create 帶 look")
	assert_type(a["look"], TYPE_INT)
	assert_eq(a["gender"], "M")
	# 性別切換：選項換成女性的 9 張、選擇重設為 0
	cc.gender_opt.select(1)
	cc.gender_opt.item_selected.emit(1)
	assert_eq(cc.picker.gender, "F")
	assert_eq(cc.picker.selected, 0, "重設為布衣")
	assert_eq(cc.picker.cells[3].look_name, "千金小姐")
	assert_eq(cc.look_label.text, "造型：布衣")
	cc.picker.pick(7)
	a = cc.build_args()
	assert_eq(a["gender"], "F")
	assert_eq(a["look"], 7)
	assert_eq(Protocol.validate_args("char_create", a), "", "協定接受 look")
	# 分頁切換
	cc.show_tab("map")
	assert_true(cc.birth_map.visible and not cc.picker.visible)
	cc.show_tab("looks")
	assert_true(cc.picker.visible and not cc.birth_map.visible)

func test_char_create_picker_takes_right_half_at_1280() -> void:
	var cc = _add((load("res://ui/game/char/char_create.tscn") as PackedScene).instantiate())
	await _frames(3)
	# 整個創角框（玉石框）在 1280×720 放得下；選擇器在框的右半邊、寬度 ≥ 600
	# 整合者：不要靠子節點索引（全套測試時基底類別可能先加了別的子節點）；從選擇器往上找 CenterContainer 底下那一層
	var frame: Control = cc.picker
	while frame.get_parent() != null and not (frame.get_parent() is CenterContainer):
		frame = frame.get_parent() as Control
	assert_true(frame != null and frame.get_parent() is CenterContainer, "找得到玉石框")
	var need := frame.get_combined_minimum_size()
	assert_true(need.x <= 1280.0 and need.y <= 720.0, "frame min size %s fits 1280×720" % str(need))
	var fr := frame.get_global_rect()
	var r: Rect2 = cc.picker.get_global_rect()
	assert_true(r.size.x >= 600.0, "picker width %s" % str(r.size))
	assert_true(r.position.x - fr.position.x >= fr.size.x * 0.45, "picker on the right half: %s in %s" % [str(r), str(fr)])
	cc.show_tab("map")
	await _frames(2)
	assert_eq(frame.get_combined_minimum_size(), need, "切到出生地圖時框不變大小")

# ---------------------------------------------------------------- 選角

func test_char_select_shows_summary_look() -> void:
	var cs = _add((load("res://ui/game/char/char_select.tscn") as PackedScene).instantiate())
	await _frames()
	cs.apply_list([
		{ "char_id": "ch_1", "name": "甲", "gender": "M", "sect_name": "", "combat_xp": 0, "room_name": "西夏", "look": "look_m05" },
		{ "char_id": "ch_2", "name": "乙", "gender": "F", "sect_name": "", "combat_xp": 0, "room_name": "大理" },
	])
	var pics: Array = []
	_collect(cs.list_box, func(n): return n is TextureRect and n.name.begins_with("LookPortrait"), pics)
	assert_eq(pics.size(), 2)
	assert_eq(pics[0].get_meta("look"), "look_m05")
	assert_eq(pics[1].get_meta("look"), "player_f", "舊主機沒有 summary.look → 0 號")
	assert_true(pics[0].texture != null and pics[1].texture != null)

func _collect(n: Node, pred: Callable, out: Array) -> void:
	for c in n.get_children():
		if pred.call(c):
			out.append(c)
		_collect(c, pred, out)

# ---------------------------------------------------------------- 屬性視窗、LookDialog

func _look_sheet(sect := "") -> Dictionary:
	var s := Scenes.fake_sheet()
	s["sect"] = sect
	s["sect_name"] = "少林" if sect != "" else ""
	s["gender"] = "M"
	s["appearance"] = 2
	s["look"] = "look_m02" if sect == "" else sect + "_m"
	return s

func test_attributes_panel_portrait_and_button() -> void:
	var p := AttributesPanel.new()
	_add(p)
	await _frames()
	var got: Array = []
	p.look_change_requested.connect(func(): got.append(true))
	p.apply_sheet(_look_sheet())
	assert_eq(p.look_label.text, "造型：獵戶")
	assert_eq(p.portrait.texture, ArtRegistry.unit_texture("look_m02", "PLAYER", "idle"), "立繪＝sheet.look")
	assert_false(p.btn_look.disabled)
	p.btn_look.pressed.emit()
	assert_eq(got.size(), 1, "更換造型 → look_change_requested")
	p.apply_sheet(_look_sheet("shaolin"))
	assert_true(p.look_label.text.begins_with("造型：獵戶") and p.look_label.text.contains("門派服裝"), p.look_label.text)
	var bs := _look_sheet()
	bs["in_battle"] = true
	p.apply_sheet(bs)
	assert_true(p.btn_look.disabled, "戰鬥中唯讀")
	var old := Scenes.fake_sheet()
	old.erase("look")
	old.erase("appearance")
	old["sect"] = ""
	p.apply_sheet(old)
	assert_eq(p.look_label.text, "造型：布衣", "舊主機")
	assert_true(p.portrait.texture != null)

func test_look_dialog_sends_set_look() -> void:
	var sent: Array = []
	var d := LookDialog.new()
	d.gate = _gate(sent)
	_add(d)
	await _frames()
	d.open_for(_look_sheet())
	assert_true(d.visible)
	assert_eq(d.picker.gender, "M")
	assert_eq(d.picker.selected, 2, "開啟時選目前造型")
	assert_eq(d.hint_label.text, "", "未入派沒有提示")
	var r := d.picker.get_combined_minimum_size()
	assert_true(r.y <= 400.0, "5×2 fits under the HUD: %s" % str(r))
	for c in d.picker.cells:
		var pr: Rect2 = c.portrait_rect()
		assert_true(pr.size.x >= 150.0 and pr.size.y >= 150.0, "dialog portrait %s" % str(pr.size))
	d.confirm()
	assert_eq(sent.size(), 0, "沒換就不送")
	assert_false(d.visible)
	d.open_for(_look_sheet())
	d.picker.pick(6)
	d.confirm()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0], ["set_look", { "look": 6 }], "intent 形狀")
	assert_eq(Protocol.validate_args(sent[0][0], sent[0][1]), "", "協定接受")
	await _frames()
	assert_false(d.visible, "成功後關閉")
	d.open_for(_look_sheet("shaolin"))
	assert_eq(d.hint_label.text, LookDialog.SECT_HINT, "入派中提示")

func test_look_dialog_failure_keeps_open() -> void:
	var sent: Array = []
	var d := LookDialog.new()
	d.gate = _gate(sent, false, "in_battle")
	_add(d)
	await _frames()
	d.open_for(_look_sheet())
	d.picker.pick(3)
	d.confirm()
	await _frames()
	assert_true(d.visible, "失敗不關")
	assert_true(d.status_label.text != "", "顯示原因")

func test_main_screen_wiring() -> void:
	var main: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	var sent: Array = []
	main.gate.set_sender(func(kind, args):
		sent.append([kind, args])
		return -1)
	var sh := _look_sheet()
	_fake_sheet(sh)
	main.apply_sheet(sh)
	assert_true(main.look_dialog != null and main.look_dialog.get_parent() != null, "look_dialog 在對話框層")
	assert_true(main.look_dialog in main._dialogs())
	(main.panels["attributes"] as AttributesPanel).look_change_requested.emit()
	assert_true(main.look_dialog.visible, "屬性視窗 → 開更換造型")
	assert_eq(main.look_dialog.picker.selected, 2)
	main.look_dialog.picker.pick(1)
	main.look_dialog.confirm()
	assert_eq(sent.back(), ["set_look", { "look": 1 }])

func test_dialog_silhouette_uses_own_look() -> void:
	var sh := _look_sheet()
	_fake_sheet(sh)
	var d := StoryDialog.new()
	_add(d)
	await _frames()
	d._set_portrait("n_definitely_no_art_here")
	assert_eq(d.portrait.texture, ArtRegistry.unit_texture("look_m02", "PLAYER", "idle"), "剪影用自己的外觀")
