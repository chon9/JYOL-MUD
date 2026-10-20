extends "res://tests/unit/test_world_fixture.gd"
## M3C2_PLAN §5.8、§5.2、§5.7（WP-CARRY）：角色選擇畫面 × 真主機 —— 匯入鈕（允許／灰掉）、匯入對話框（資料夾清單、預覽、
## 改名重送、同世界提示）、匯出（寫檔、顯示路徑）、外來標記、Steam 角色分組與確認框。

const SCENE := "res://ui/game/char/char_select.tscn"
const OTHER_WORLD := "w_ui_friend"
const FOREIGN_IDENT := "local_cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"
const STEAM_IDENT := "steam_76561190000000001"

var screen: Node = null
var _old_mode := 0

func before_each() -> void:
	world_name = "w_ui_m3c2_import"
	UiSettings.reset_for_tests(true)
	super.before_each()
	_old_mode = NetworkManager.mode
	NetworkManager.mode = NetworkManager.Mode.OFFLINE
	cs.world_info = ws.world_info()

func after_each() -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
		await tree.process_frame
	screen = null
	if ws.game != null:
		ws.game.test_steam_id = ""
	NetworkManager.mode = _old_mode
	super.after_each()

func open_screen() -> void:
	screen = (load(SCENE) as PackedScene).instantiate()
	tree.root.add_child(screen)
	await tree.process_frame
	screen._leaving = true   # 測試中不換場景（選角成功後 go("main") 直接略過）
	screen.gate.set_sender(func(kind: String, args: Dictionary) -> int:
		seq += 1
		ws.handle_intent(1, seq, kind, args)
		return seq)
	ws.flush()
	screen.apply_list(cs.char_list)

func _all(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c.is_queued_for_deletion():
			continue
		out.append(c)
		out.append_array(_all(c))
	return out

func _texts(root: Node) -> Array:
	var out: Array = []
	for c in _all(root):
		if c is Label:
			out.append((c as Label).text)
	return out

func _buttons(root: Node, text: String) -> Array:
	var out: Array = []
	for c in _all(root):
		if c is Button and (c as Button).text == text:
			out.append(c)
	return out

func _any_contains(arr: Array, needle: String) -> bool:
	for t in arr:
		if str(t).contains(needle):
			return true
	return false

## 在測試資料根目錄的 exports/ 放一份朋友世界的匯出檔
func _plant_export(char_name: String, src_id := "ch_uifx0001", saved_s := 1000.0) -> String:
	var d: Dictionary = ch().to_dict()
	d["id"] = src_id
	d["identity"] = FOREIGN_IDENT
	d["name"] = char_name
	d["inventory"]["items"].append({ "uid": "it_uizz0001", "id": "x_unknown_thing", "n": 2, "born_s": 0.0 })
	var pp := Passport.make("friend_secret", OTHER_WORLD, d, saved_s)
	return sm.export_character(pp, { "world_name": "朋友的江湖", "content_hash": GameData.content_hash })

func test_import_flow_preview_rename_and_foreign_mark() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var path := _plant_export("本地俠")   # 同名 → 要改名
	assert_true(path != "", "planted export")
	await open_screen()
	var b_imp: Button = screen.btn_import
	assert_false(b_imp.disabled, "offline: import allowed")
	b_imp.pressed.emit()
	var dlg: ImportDialog = screen.import_dialog
	assert_true(dlg.visible, "dialog open")
	dlg.show_folder(ImportDialog.SRC_EXPORTS)
	assert_eq(dlg.files.size(), 1, "export listed")
	assert_true(_buttons(dlg.file_list, path.get_file()).size() == 1, "file button")
	_buttons(dlg.file_list, path.get_file())[0].pressed.emit()
	var tx := _texts(dlg.preview_box)
	assert_true(_any_contains(tx, "來源世界：朋友的江湖"), str(tx))
	assert_true(_any_contains(tx, "本地俠　男"), str(tx))
	assert_true(_any_contains(tx, "未知物品 x_unknown_thing ×2"), "dropped shown")
	assert_false(dlg.btn_confirm.disabled, "confirm enabled")
	# 名字被佔 → 改名欄
	dlg.btn_confirm.pressed.emit()
	ws.flush()
	assert_true(dlg.rename_row.visible, "rename row shown")
	dlg.rename_edit.text = "遠來俠"
	dlg.btn_confirm.pressed.emit()
	ws.flush()
	await tree.process_frame
	assert_false(dlg.visible, "dialog closed on success")
	assert_true(str(screen.status_label.text).contains("已匯入外來角色「遠來俠」"), screen.status_label.text)
	assert_true(str(screen.status_label.text).contains("未知物品"), "dropped summary")
	assert_true(_any_contains(_texts(screen.list_box), "遠來俠（外來）"), str(_texts(screen.list_box)))

func test_same_world_passport_hint_and_disabled_when_hosted_off() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var pp: Dictionary = host().make_passport(ch())
	await open_screen()
	var dlg: ImportDialog = screen.import_dialog
	dlg.open_dialog()
	var san := ImportDialog.preview_of(pp)
	dlg.current = { "path": "", "passport": pp, "world_name": "", "san": san }
	dlg.apply_preview(dlg.current)
	assert_true(_any_contains(_texts(dlg.preview_box), ImportDialog.SAME_WORLD_HINT), "same world hint")
	# M3c2 審查：本世界的檔案只顯示提示與一行摘要，不列「會被拿掉的東西」
	assert_false(_any_contains(_texts(dlg.preview_box), "會被拿掉"), str(_texts(dlg.preview_box)))
	assert_false(_any_contains(_texts(dlg.preview_box), "來源世界"), "no origin line")
	assert_true(dlg.btn_confirm.disabled, "cannot confirm same world")
	# M3c2 審查：讀不了的檔案 → 原因寫在預覽區，狀態列不重複
	dlg.load_file("K:/no/such/file.json")
	assert_eq(dlg.status_label.text, "")
	assert_true(_any_contains(_texts(dlg.preview_box), ImportDialog.unreadable_text("unreadable")), str(_texts(dlg.preview_box)))
	assert_false(_any_contains(_texts(dlg.preview_box), "選一個檔案看預覽"), "no empty hint")
	# 主機的 passport 太大 → 對應到「檔案無法讀取」而不是原因碼
	dlg.on_result(false, "bad_value:passport")
	assert_eq(dlg.status_label.text, ImportDialog.unreadable_text("passport_too_large"))
	# 開房且主機沒開 → 匯入鈕灰掉、提示
	NetworkManager.mode = NetworkManager.Mode.ENET_HOST
	ws.options["allow_foreign_characters"] = false
	cs.world_info = ws.world_info()
	screen._refresh_import_button()
	assert_true(screen.btn_import.disabled, "disabled")
	assert_eq(screen.btn_import.tooltip_text, "主機沒有開放外來角色")

func test_export_button_writes_file_and_shows_path() -> void:
	if not game_ok():
		return
	make_char("匯出甲")
	var cid := str(ch().id)
	await open_screen()
	var rows := _buttons(screen.list_box, "匯出")
	assert_eq(rows.size(), 1, "one export button")
	rows[0].pressed.emit()
	ws.flush()   # 沒有本機護照 → passport_request → passport 事件 → 寫檔
	await tree.process_frame
	var p: String = screen.last_export_path
	assert_true(p != "" and FileAccess.file_exists(p), "exported %s" % p)
	assert_true(p.begins_with(sm.exports_dir()), "in exports dir")
	assert_true(screen.export_row.visible, "path row visible")
	assert_true(str(screen.export_label.text).begins_with("已匯出到：\n"), screen.export_label.text)
	# M3c2 第三輪審查：路徑自己一行
	var lines := str(screen.export_label.text).split("\n")
	assert_eq(lines.size(), 3, "three lines")
	assert_eq(lines[1], screen.display_path(p), "path alone on line 2")
	assert_true(str(screen.export_label.text).contains("「匯入角色」"), "instructions")
	var r: Dictionary = sm.read_import_file(p)
	assert_eq(str(r["passport"]["char_id"]), cid)

func test_steam_group_and_confirm_dialog() -> void:
	if not game_ok():
		return
	make_char("本機俠")
	var d: Dictionary = ch().to_dict()
	d["id"] = "ch_uisteam01"
	d["identity"] = STEAM_IDENT
	d["name"] = "蒸汽俠"
	sm.save_character(ws.world_id, STEAM_IDENT, d)
	host().char_store.register_name(Character.from_dict(d))
	host().test_steam_id = "none"
	ok("char_list")
	await open_screen()
	var tx := _texts(screen.list_box)
	assert_true(_any_contains(tx, "本機角色（目前）"), str(tx))
	assert_true(_any_contains(tx, "Steam 角色（7656…0001）"), str(tx))
	assert_eq(_buttons(screen.list_box, "匯出").size(), 1, "alt rows have no export")
	assert_eq(_buttons(screen.list_box, "進入江湖").size(), 2)
	# M3c2 第二輪審查：Steam 列沒有匯出／刪除，「進入江湖」仍和本機列對齊
	await tree.process_frame
	await tree.process_frame
	var e0: Button = _buttons(screen.list_box, "進入江湖")[0]
	var e1: Button = _buttons(screen.list_box, "進入江湖")[1]
	assert_true(absf(e0.get_global_rect().position.x - e1.get_global_rect().position.x) <= 1.0, "enter buttons aligned %s / %s" % [str(e0.get_global_rect()), str(e1.get_global_rect())])
	# 選 Steam 角色 → 確認框
	var enter: Button = _buttons(screen.list_box, "進入江湖")[1]
	enter.pressed.emit()
	assert_true(screen.alt_panel.visible, "confirm shown")
	# M3c2 審查：確認框和分組標題用同一個縮寫
	assert_true(str(screen.alt_label.text).contains("（7656…0001）"), screen.alt_label.text)
	assert_true(screen.modal_dim.visible, "M3c2 第二輪審查：確認框後面有遮罩")
	assert_false(str(screen.alt_label.text).contains(STEAM_IDENT), "full id not shown")
	screen._on_alt_confirm()
	ws.flush()
	assert_eq(s().identity, STEAM_IDENT, "switched after confirm")
	assert_eq(str(ch().name), "蒸汽俠")

func test_pure_helpers() -> void:
	var CS = load("res://ui/game/char/char_select.gd")
	assert_eq(CS.short_identity("steam_76561198000001234"), "steam_7656…1234")
	assert_eq(CS.short_identity("steam_123"), "steam_123")
	assert_eq(CS.group_header("steam_76561198000001234", false), "Steam 角色（7656…1234）")
	assert_eq(CS.group_header("local_" + "a".repeat(32), true), "本機角色（目前）")
	assert_eq(CS.steam_short("steam_76561198000001234"), "7656…1234")
	var list := [{ "char_id": "a", "alt": false, "identity": "local_x" },
		{ "char_id": "b", "alt": true, "identity": "steam_1", "needs_confirm": true },
		{ "char_id": "c", "alt": true, "identity": "steam_1", "needs_confirm": true }]
	assert_eq(CS.own_rows(list).size(), 1)
	var g: Array = CS.alt_groups(list)
	assert_eq(g.size(), 1)
	assert_eq((g[0]["rows"] as Array).size(), 2)
	assert_eq(CS.foreign_imported_text({ "name": "甲", "replaced": true, "dropped": [] }), "已更新外來角色「甲」。")
	assert_eq(AttributesPanel.foreign_mark({ "foreign": true }), "（外來）")

func test_server_options_panel_has_foreign_toggle() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var dlg := ServerOptionsDialog.new()
	tree.root.add_child(dlg)
	await tree.process_frame
	dlg._gate().set_sender(func(kind: String, args: Dictionary) -> int:
		seq += 1
		ws.handle_intent(1, seq, kind, args)
		return seq)
	cs.world_info = ws.world_info()
	dlg.apply_options(host().admin.snapshot())
	var ob: OptionButton = dlg.foreign_row
	assert_true(ob != null, "row added")
	assert_eq(str(ob.get_meta("value")), "false")
	ob.select(0)
	ob.item_selected.emit(0)
	ws.flush()
	assert_eq(ws.options["allow_foreign_characters"], true, "toggled on via panel")
	dlg.queue_free()
	await tree.process_frame

# ---------------------------------------------------------------- M3c2 審查（介面）

## 審查 #1、#3：很多 Steam 角色時清單捲動、按鈕列留在畫面內；長名字不把框撐寬
func test_review_list_scrolls_and_rows_do_not_widen_frame() -> void:
	if not game_ok():
		return
	make_char("本機俠")
	var base: Dictionary = ch().to_dict()
	for a in 3:
		var ident := "steam_7656119000000%04d" % (a + 10)
		for k in 3:
			var d := base.duplicate(true)
			d["id"] = "ch_uisc%02d%02d" % [a, k]
			d["identity"] = ident
			d["name"] = "捲動俠%d%d" % [a, k]
			sm.save_character(ws.world_id, ident, d)
	host().test_steam_id = "none"
	ok("char_list")
	await open_screen()
	await tree.process_frame
	var sc: ScrollContainer = screen.list_scroll
	assert_true(sc != null and sc.is_ancestor_of(screen.list_box), "list inside scroll")
	assert_true(sc.custom_minimum_size.y <= screen.LIST_MAX_H + 0.5, "scroll height capped %s" % str(sc.custom_minimum_size))
	assert_true(screen.list_box.get_combined_minimum_size().y > sc.custom_minimum_size.y, "content taller than viewport → scrolls")
	var vp: Vector2 = screen.get_viewport_rect().size
	var back: Button = screen.btn_back
	assert_true(back.get_global_rect().end.y <= vp.y + 0.5, "back button on screen: %s / %s" % [str(back.get_global_rect()), str(vp)])
	# 長名字：列的文字截掉、有滑鼠提示，框寬不變
	var w0: float = screen.list_box.get_combined_minimum_size().x
	var rows := [{ "char_id": "x1", "name": "名".repeat(40), "gender": "M", "sect_name": "很長的門派名字" , "combat_xp": 1, "room_name": "很長很長的房間名字".repeat(3), "foreign": true, "origin_world_name": "遠方" }]
	screen.apply_list(rows)
	var info: Label = null
	for c in _all(screen.list_box):
		if c is Label and str(c.name).begins_with("CharInfo"):
			info = c
	assert_true(info != null and info.clip_text, "clip")
	assert_true(info.tooltip_text.contains("名名名名"), "tooltip has full text")
	assert_true(screen.list_box.get_combined_minimum_size().x <= maxf(w0, 760.0) + 1.0, "frame not widened")

## 審查 #7、#10：新狀態訊息把舊的匯出路徑收起；一般進度訊息不是紅字；路徑在 Windows 用反斜線
func test_review_status_colors_and_export_row_hidden() -> void:
	if not game_ok():
		return
	make_char("匯出乙")
	await open_screen()
	_buttons(screen.list_box, "匯出")[0].pressed.emit()
	ws.flush()
	await tree.process_frame
	assert_true(screen.export_row.visible, "path row visible")
	if OS.get_name() == "Windows":
		assert_false(str(screen.export_label.text).contains("/"), "backslashes: " + screen.export_label.text)
	screen._on_foreign_imported({ "name": "甲", "replaced": false, "dropped": [] })
	assert_false(screen.export_row.visible, "old export row hidden by new status")
	assert_eq(screen.status_label.get_theme_color("font_color"), UiTheme.JY_GOLD_LIGHT, "ok gold")
	screen._set_status("進入江湖中……", screen.StatusKind.INFO)
	assert_eq(screen.status_label.get_theme_color("font_color"), UiTheme.JY_MUTED_LIGHT, "info muted")
	screen._set_status("失敗")
	assert_eq(screen.status_label.get_theme_color("font_color"), UiTheme.JY_ERROR_LIGHT, "error red")

## 審查 #6：檔案清單高度對齊整列
func test_review_file_list_height_whole_rows() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	await open_screen()
	var dlg: ImportDialog = screen.import_dialog
	dlg.open_dialog()
	dlg.set_files(["K:/a/1.json", "K:/a/2.json", "K:/a/3.json", "K:/a/4.json", "K:/a/5.json"])
	var b: Button = null
	for c in dlg.file_list.get_children():
		if c is Button and b == null:
			b = c
	var bh := b.get_combined_minimum_size().y if b != null else 0.0
	var sep := float(dlg.file_list.get_theme_constant("separation"))
	assert_true(bh > 0.0, "row height")
	var want := ImportDialog.FILE_ROWS * bh + (ImportDialog.FILE_ROWS - 1) * sep
	assert_true(absf(dlg.file_scroll.custom_minimum_size.y - want) < 0.5, "whole rows %s vs %s" % [str(dlg.file_scroll.custom_minimum_size.y), str(want)])

## M3c2 第二輪審查：框上緣固定、開啟資料夾不被撐高、匯入視窗路徑分隔符、錢莊 0 的部分不寫、預覽較長時有提示
func test_review2_layout_bits() -> void:
	if not game_ok():
		return
	make_char("版面俠")
	await open_screen()
	await tree.process_frame
	var frame := screen.find_child("CharSelectFrame", true, false) as Control
	var y0 := frame.get_global_rect().position.y
	screen._set_status("很長的訊息
第二行
第三行")
	await tree.process_frame
	await tree.process_frame
	assert_true(absf(frame.get_global_rect().position.y - y0) <= 0.5, "frame top fixed %s → %s" % [str(y0), str(frame.get_global_rect().position.y)])
	var ob := screen.find_child("OpenExports", true, false) as Button
	assert_eq(ob.size_flags_vertical, Control.SIZE_SHRINK_CENTER)
	screen.open_import()
	await tree.process_frame
	assert_true(screen.modal_dim.visible, "dim behind import dialog")
	if OS.get_name() == "Windows":
		assert_false(str(screen.import_dialog.source_label.text).contains("/"), screen.import_dialog.source_label.text)
	screen.import_dialog.close()
	await tree.process_frame
	assert_false(screen.modal_dim.visible, "dim hidden after close")
	var dropped: Array = []
	var c := Character.from_dict(ch().to_dict())
	c.bank = { "money": 50, "items": [] }
	ForeignImport._reset_world_bound(c, tables(), dropped)
	assert_true(dropped.has("錢莊存款（留在原世界）：銀兩 50"), str(dropped))

## M3c2 第三輪審查（介面 #1、#5、#6）：匯出失敗是中文紅字、成功訊息路徑單獨一行；匯入視窗上緣固定、改名欄不改變高度、清單寫出檔案數
func test_review3_export_text_and_import_dialog_fixed() -> void:
	if not game_ok():
		return
	assert_eq(ImportDialog.file_count_text(0), "")
	assert_eq(ImportDialog.file_count_text(2), "共 2 個檔案。")
	assert_true(ImportDialog.file_count_text(5).contains("往下捲動"), ImportDialog.file_count_text(5))
	make_char("版面丙")
	await open_screen()
	for e in ["passport_bad_format", "commit tmp failed (File not found)", ""]:
		var t: String = screen.export_error_text(e)
		assert_true(t.begins_with("匯出失敗："), t)
		var ascii := RegEx.create_from_string("[A-Za-z]")
		assert_true(ascii.search(t) == null, "no English: " + t)
	screen.write_export({ "bad": true })
	assert_eq(str(screen.export_label.theme_type_variation), "ErrorLabel", "failure in error style")
	assert_false(str(screen.export_label.text).contains("passport_bad_format"), screen.export_label.text)
	screen.open_import()
	var dlg: ImportDialog = screen.import_dialog
	await tree.process_frame
	await tree.process_frame
	var r0 := dlg.get_global_rect()
	dlg.show_unreadable("not_json")
	dlg.rename_row.visible = true
	dlg.status_label.text = "這個名字不能用（已有人用或不合規定），請換一個名字再按「確定匯入」。"
	await tree.process_frame
	await tree.process_frame
	var r1 := dlg.get_global_rect()
	assert_true(absf(r1.position.y - r0.position.y) <= 0.5, "dialog top fixed %s → %s" % [str(r0.position.y), str(r1.position.y)])
	var btn := dlg.btn_confirm.get_global_rect().position.y
	dlg.rename_row.visible = false
	await tree.process_frame
	await tree.process_frame
	assert_true(absf(dlg.btn_confirm.get_global_rect().position.y - btn) <= 0.5, "buttons do not move with rename row")
	assert_true(r1.end.y <= 720.0 + 0.5, "dialog fits in 720 px: %s" % str(r1))
	dlg.close()
