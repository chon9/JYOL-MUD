extends UiScreen
## 角色選擇（M1_PLAN 3.12）：讀 ClientState.char_list；進場送 char_list；選角 → char_select；
## 刪除需輸入角色名確認 → char_delete；建立新角色（已有 3 個時灰色）→ 創角。
## 收到 sheet_changed 且 sheet.char_id != "" → 主畫面。
## M2：「護照」→ PassportDialog（列出本機護照、用護照還原 passport_restore）。
## M3c：每列左邊是角色的小立繪（summary.look；舊主機沒有 → 依性別 0 號布衣）。

const PORTRAIT := Vector2(56, 66)

var list_box: VBoxContainer
var status_label: Label
var btn_create: Button
var btn_back: Button
var btn_passport: Button
var passport_dialog: PassportDialog
var confirm_panel: PanelContainer
var confirm_edit: LineEdit
var confirm_label: Label
var _confirm_target: Dictionary = {}
var _entry_char_id := ""
var _awaiting_enter := false
var _requested_list := false

func _ready() -> void:
	_build()
	_entry_char_id = str(UiClient.sheet().get("char_id", ""))
	UiClient.connect_signal("char_list_changed", _on_char_list)
	UiClient.connect_signal("sheet_changed", _on_sheet)
	UiClient.connect_signal("welcomed", _on_welcomed)
	var msg := take_router_message()
	if msg != "":
		status_label.text = msg
	apply_list(UiClient.char_list())
	if UiClient.in_world():
		request_list()
	else:
		status_label.text = "正在等待主機回應……"

func _exit_tree() -> void:
	super._exit_tree()
	UiClient.disconnect_signal("char_list_changed", _on_char_list)
	UiClient.disconnect_signal("sheet_changed", _on_sheet)
	UiClient.disconnect_signal("welcomed", _on_welcomed)

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var frame := UiBuild.framed(center, UiFrame.Kind.JADE)   # AUTHENTIC_UI_SPEC §14：玉石框選角
	var col := UiBuild.vbox(frame, 10)
	col.custom_minimum_size = Vector2(760, 0)
	UiBuild.title(col, "選擇角色")

	UiBuild.muted(UiBuild.label(col, "每個身分在這個世界最多 %d 個角色。" % UiKeys.MAX_CHARS, 15))
	col.add_child(HSeparator.new())
	list_box = UiBuild.vbox(col, 8)
	list_box.custom_minimum_size = Vector2(0, 200)
	col.add_child(HSeparator.new())
	var row := UiBuild.hbox(col, 10)
	btn_create = UiBuild.button(row, "建立新角色", func(): go("char_create"), 160)
	btn_passport = UiBuild.button(row, "護照", open_passports, 90)
	btn_passport.tooltip_text = "角色護照：主機的角色檔遺失時用本機備份還原"
	btn_back = UiBuild.button(row, "離開世界", _on_back, 120)
	status_label = UiBuild.label(col, "", 16, true)
	status_label.add_theme_color_override("font_color", UiTheme.JY_ERROR_LIGHT)

	# 刪除確認
	var f := UiBuild.popup_frame("刪除角色", Vector2(460, 0))
	confirm_panel = f["panel"]
	confirm_panel.visible = false
	confirm_panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(confirm_panel)
	(f["close"] as Button).pressed.connect(func(): confirm_panel.visible = false)
	confirm_label = UiBuild.label(f["body"], "", 16, true)
	confirm_edit = UiBuild.line_edit(f["body"], "", "輸入角色名稱以確認", 16)
	var crow := UiBuild.hbox(f["body"])
	UiBuild.button(crow, "確定刪除", _on_confirm_delete)
	UiBuild.button(crow, "取消", func(): confirm_panel.visible = false)

	var pc := CenterContainer.new()
	pc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pc)
	passport_dialog = PassportDialog.new()
	passport_dialog.gate = gate
	passport_dialog.visible = false
	pc.add_child(passport_dialog)

func open_passports() -> void:
	passport_dialog.open_list()

func request_list() -> void:
	_requested_list = true
	send(UiKeys.I_CHAR_LIST)

## list = 3.9.5 的陣列
func apply_list(list: Array) -> void:
	UiBuild.clear(list_box)
	if list.is_empty():
		UiBuild.muted(UiBuild.label(list_box, "（還沒有角色，建立一個踏入江湖吧）", 18))
	for c in list:
		if not (c is Dictionary):
			continue
		var row := UiBuild.hbox(list_box, 12)
		var pic := TextureRect.new()
		pic.name = "LookPortrait"
		pic.custom_minimum_size = PORTRAIT
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture = LookPicker.sheet_look_texture(c)
		pic.set_meta("look", LookPicker.sheet_look_ref(c))
		row.add_child(pic)
		var info := "%s　%s　%s　實戰 %d　%s" % [
			str(c.get("name", "?")), UiKeys.GENDER_LABELS.get(str(c.get("gender", "")), ""),
			str(c.get("sect_name", "")) if str(c.get("sect_name", "")) != "" else "無門派",
			UiBuild.num(c.get("combat_xp", 0)), str(c.get("room_name", ""))]
		var l := UiBuild.label(row, info, 18)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var b_enter := UiBuild.button(row, "進入江湖", Callable(), 110)
		b_enter.pressed.connect(_on_select.bind(str(c.get("char_id", "")), b_enter))
		var b_del := UiBuild.button(row, "刪除", Callable(), 70)
		b_del.pressed.connect(_on_delete.bind(c))
		b_enter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b_del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_create.disabled = list.size() >= UiKeys.MAX_CHARS
	btn_create.tooltip_text = "角色已滿 %d 個" % UiKeys.MAX_CHARS if btn_create.disabled else ""

func _on_char_list(list: Array) -> void:
	apply_list(list)

func _on_welcomed(_info: Dictionary) -> void:
	status_label.text = ""
	apply_list(UiClient.char_list())
	request_list()

func _on_select(char_id: String, btn: Button) -> void:
	if char_id == "":
		return
	_awaiting_enter = true
	status_label.text = "進入江湖中……"
	send(UiKeys.I_CHAR_SELECT, { "char_id": char_id }, [btn], func(ok: bool, reason: String):
		if not ok:
			_awaiting_enter = false
			status_label.text = UiClient.reason_inline(reason))

func _on_delete(c: Dictionary) -> void:
	_confirm_target = c
	confirm_label.text = "確定要刪除「%s」嗎？請輸入角色名稱確認。" % str(c.get("name", ""))
	confirm_edit.text = ""
	confirm_panel.visible = true
	confirm_panel.position = (size - confirm_panel.get_combined_minimum_size()) / 2.0

func _on_confirm_delete() -> void:
	var c := _confirm_target
	confirm_panel.visible = false
	send(UiKeys.I_CHAR_DELETE, { "char_id": str(c.get("char_id", "")), "confirm_name": confirm_edit.text.strip_edges() },
		[], func(ok: bool, reason: String):
			status_label.text = "" if ok else UiClient.reason_inline(reason))

func _on_sheet(sheet: Dictionary) -> void:
	var cid := str(sheet.get("char_id", ""))
	if cid == "":
		return
	# 從主畫面回來時，已選中的角色會持續推送角色表；只有剛選角或換了角色才進主畫面
	if _awaiting_enter or cid != _entry_char_id:
		go("main")

func _on_back() -> void:
	var nm := _nm()
	_leaving = true
	if nm:
		nm.leave()
	_leaving = false
	go("title")
