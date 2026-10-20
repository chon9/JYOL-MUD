extends UiScreen
## 角色選擇（M1_PLAN 3.12）：讀 ClientState.char_list；進場送 char_list；選角 → char_select；
## 刪除需輸入角色名確認 → char_delete；建立新角色（已有 3 個時灰色）→ 創角。
## 收到 sheet_changed 且 sheet.char_id != "" → 主畫面。
## M2：「護照」→ PassportDialog（列出本機護照、用護照還原 passport_restore）。
## M3c：每列左邊是角色的小立繪（summary.look；舊主機沒有 → 依性別 0 號布衣）。
## M3c2 WP-CARRY（M3C2_PLAN §5.2、§5.7、§5.8）：
## - 「匯入角色」→ ImportDialog（主機不允許外來角色時灰掉）；每列「匯出」→ <資料根目錄>/exports/<名>_<世界>_<時間>.jychar.json
##   （本機護照是最新的就直接寫，否則先 passport_request、收到 passport 事件再寫），顯示路徑與「開啟資料夾」。
## - 外來角色名字後「（外來）」。
## - 單機時清單分組「本機角色」「Steam 角色（steam_7656…1234）」：選別的身分的角色送 char_select { char_id, identity }；
##   needs_confirm（Steam 沒開、角色屬於某個 Steam 帳號）先跳確認。

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
# ---- M3c2 WP-CARRY ----
var btn_import: Button
var import_dialog: ImportDialog
var export_row: HBoxContainer
var export_label: Label
var alt_panel: PanelContainer
var alt_label: Label
var _alt_target: Dictionary = {}
var _pending_export := ""          # 等 passport 事件的角色 id
var last_export_path := ""
const ALT_CONFIRM := "這個角色屬於另一個 Steam 帳號（%s）。用單機玩會直接改動這份存檔，之後用 Steam 開房也是這份。確定？"
## M3c2 審查：角色清單可捲動（世界裡有幾個 Steam 帳號的角色時，按鈕列不會被擠出畫面）
const LIST_MIN_H := 200.0
const LIST_MAX_H := 330.0
const ROW_LABEL_MIN_W := 300.0
## M3c2 第二輪審查：框上緣的位置、每列右邊按鈕欄的寬度（Steam 列沒有匯出／刪除也對齊）、遮罩
const FRAME_TOP := 48.0
const ENTER_W := 110.0
const SMALL_W := 70.0
const ROW_SEP := 12
const ACTIONS_W := ENTER_W + SMALL_W * 2 + ROW_SEP * 2
const MODAL_DIM := Color(0, 0, 0, 0.55)
var modal_dim: ColorRect
var list_scroll: ScrollContainer
enum StatusKind { ERROR, OK, INFO }
const IMPORT_DISABLED_TIP := "主機沒有開放外來角色"

func _ready() -> void:
	_build()
	_entry_char_id = str(UiClient.sheet().get("char_id", ""))
	UiClient.connect_signal("char_list_changed", _on_char_list)
	UiClient.connect_signal("sheet_changed", _on_sheet)
	UiClient.connect_signal("welcomed", _on_welcomed)
	UiClient.connect_signal("events_received", _on_events)
	UiClient.connect_signal("foreign_imported", _on_foreign_imported)
	UiClient.connect_signal("world_info_changed", _on_world_info_changed)
	var msg := take_router_message()
	if msg != "":
		_set_status(msg)
	apply_list(UiClient.char_list())
	if UiClient.in_world():
		request_list()
	else:
		_set_status("正在等待主機回應……", StatusKind.INFO)

func _exit_tree() -> void:
	super._exit_tree()
	UiClient.disconnect_signal("char_list_changed", _on_char_list)
	UiClient.disconnect_signal("sheet_changed", _on_sheet)
	UiClient.disconnect_signal("welcomed", _on_welcomed)
	UiClient.disconnect_signal("events_received", _on_events)
	UiClient.disconnect_signal("foreign_imported", _on_foreign_imported)
	UiClient.disconnect_signal("world_info_changed", _on_world_info_changed)

func _build() -> void:
	# M3c2 第二輪審查：框的上緣固定（原本整個置中，內容一變框就上下跳、按鈕跑到滑鼠底下）；左右仍置中
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)
	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0, FRAME_TOP)
	outer.add_child(top_pad)
	var center := CenterContainer.new()
	center.name = "FrameCenter"
	center.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	outer.add_child(center)
	var frame := UiBuild.framed(center, UiFrame.Kind.JADE)   # AUTHENTIC_UI_SPEC §14：玉石框選角
	frame.name = "CharSelectFrame"
	var col := UiBuild.vbox(frame, 10)
	col.custom_minimum_size = Vector2(760, 0)
	UiBuild.title(col, "選擇角色")

	UiBuild.muted(UiBuild.label(col, "每個身分在這個世界最多 %d 個角色。" % UiKeys.MAX_CHARS, 15))
	col.add_child(HSeparator.new())
	list_scroll = UiBuild.scroll(col, LIST_MIN_H)
	list_scroll.name = "CharListScroll"
	list_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	list_box = UiBuild.vbox(list_scroll, 8)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(HSeparator.new())
	var row := UiBuild.hbox(col, 10)
	btn_create = UiBuild.button(row, "建立新角色", func(): go("char_create"), 160)
	btn_passport = UiBuild.button(row, "護照", open_passports, 90)
	btn_passport.tooltip_text = "角色護照：主機的角色檔遺失時用本機備份還原"
	btn_import = UiBuild.button(row, "匯入角色", open_import, 120)
	btn_import.name = "ImportChar"
	btn_back = UiBuild.button(row, "離開世界", _on_back, 120)
	status_label = UiBuild.label(col, "", 16, true)
	status_label.add_theme_color_override("font_color", UiTheme.JY_ERROR_LIGHT)
	status_label.visible = false   # M3c2 第三輪審查：空的時候不佔位（按鈕列和匯出訊息之間空了約 40 px）
	export_row = UiBuild.hbox(col, 8)
	export_row.name = "ExportRow"
	export_label = UiBuild.label(export_row, "", 15, true)
	export_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ob := UiBuild.button(export_row, "開啟資料夾", open_exports_folder, 120)
	ob.name = "OpenExports"
	ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # M3c2 第二輪審查：不跟著三行的路徑撐高
	export_row.visible = false
	_refresh_import_button()

	# M3c2 第二輪審查：彈出視窗（刪除確認、護照、匯入、Steam 確認）後面蓋一層半透明遮罩，擋住底下的按鈕
	modal_dim = ColorRect.new()
	modal_dim.name = "ModalDim"
	modal_dim.color = MODAL_DIM
	modal_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_dim.visible = false
	add_child(modal_dim)

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
	import_dialog = ImportDialog.new()
	import_dialog.name = "ImportDialog"
	import_dialog.gate = gate
	import_dialog.visible = false
	# M3c2 第三輪審查：匯入視窗的上緣固定（和選角框一樣在 FRAME_TOP）——置中的話出現改名欄時整個框往上跳
	var ic := VBoxContainer.new()
	ic.name = "ImportHolder"
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ic)
	var ipad := Control.new()
	ipad.custom_minimum_size = Vector2(0, FRAME_TOP)
	ipad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.add_child(ipad)
	import_dialog.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	import_dialog.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ic.add_child(import_dialog)

	# M3c2：換用別的身分（Steam 角色）的確認
	var af := UiBuild.popup_frame("另一個身分的角色", Vector2(520, 0))
	alt_panel = af["panel"]
	alt_panel.name = "AltConfirm"
	alt_panel.visible = false
	alt_panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(alt_panel)
	(af["close"] as Button).pressed.connect(func(): alt_panel.visible = false)
	alt_label = UiBuild.label(af["body"], "", 16, true)
	alt_label.custom_minimum_size = Vector2(480, 0)   # 自動換行要有寬度，否則一個字一行、框被撐得很高
	var arow := UiBuild.hbox(af["body"])
	UiBuild.button(arow, "確定", _on_alt_confirm).name = "AltConfirmOk"
	UiBuild.button(arow, "取消", func(): alt_panel.visible = false)
	for pnl in [confirm_panel, passport_dialog, import_dialog, alt_panel]:
		(pnl as Control).visibility_changed.connect(_update_modal_dim)

## 有任何彈出視窗開著 → 顯示遮罩
func _update_modal_dim() -> void:
	if modal_dim == null:
		return
	modal_dim.visible = [confirm_panel, passport_dialog, import_dialog, alt_panel].any(
		func(p): return p != null and (p as Control).visible)

func open_passports() -> void:
	passport_dialog.open_list()

func request_list() -> void:
	_requested_list = true
	send(UiKeys.I_CHAR_LIST)

## list = 3.9.5 的陣列（M3c2：別的身分的列依身分分組）
func apply_list(list: Array) -> void:
	UiBuild.clear(list_box)
	var own := own_rows(list)
	var groups := alt_groups(list)
	if own.is_empty():
		UiBuild.muted(UiBuild.label(list_box, "（還沒有角色，建立一個踏入江湖吧）", 18))
	var ordered: Array = []
	if not groups.is_empty():
		ordered.append({ "header": group_header(own_identity(list), true) })
	ordered.append_array(own)
	for g in groups:
		ordered.append({ "header": group_header(str(g["identity"]), false) })
		ordered.append_array(g["rows"])
	for c in ordered:
		if not (c is Dictionary):
			continue
		if c.has("header"):
			var h := UiBuild.accent(UiBuild.label(list_box, str(c["header"]), 16))
			h.name = "GroupHeader"
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
		# M3c2 第二輪審查：兩行（名字一行、門派／實戰／所在一行），外來角色的房名不再被擠掉
		var line1 := "%s%s　%s" % [str(c.get("name", "?")), "（外來）" if bool(c.get("foreign", false)) else "",
			UiKeys.GENDER_LABELS.get(str(c.get("gender", "")), "")]
		var line2 := "%s　實戰 %s　%s" % [
			str(c.get("sect_name", "")) if str(c.get("sect_name", "")) != "" else "無門派",
			UiBuild.num(c.get("combat_xp", 0)), str(c.get("room_name", ""))]
		var info := line1 + "　" + line2
		var tip := info
		if bool(c.get("foreign", false)):
			tip = info + "
外來角色：來自「%s」" % str(c.get("origin_world_name", ""))
		var ib := UiBuild.vbox(row, 0)
		ib.name = "CharInfoBox"
		ib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ib.custom_minimum_size = Vector2(ROW_LABEL_MIN_W, 0)
		var l := UiBuild.label(ib, line1, 18)
		l.name = "CharInfo"
		var l2 := UiBuild.muted(UiBuild.label(ib, line2, 15))
		l2.name = "CharDetail"
		# M3c2 審查：長名字／門派／房名不把框撐寬：固定寬度、超出的字截掉，滑鼠提示看全文
		for lab in [l, l2]:
			(lab as Label).clip_text = true
			(lab as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			(lab as Label).custom_minimum_size = Vector2(ROW_LABEL_MIN_W, 0)
			(lab as Label).tooltip_text = tip
			(lab as Label).mouse_filter = Control.MOUSE_FILTER_PASS
		# 按鈕欄固定寬、靠左：每列的「進入江湖」在同一個 x
		var acts := UiBuild.hbox(row, ROW_SEP)
		acts.name = "RowActions"
		acts.custom_minimum_size = Vector2(ACTIONS_W, 0)
		acts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var b_enter := UiBuild.button(acts, "進入江湖", Callable(), ENTER_W)
		b_enter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if bool(c.get("alt", false)):
			b_enter.pressed.connect(_on_select_alt.bind(c, b_enter))
			continue   # 別的身分的角色：只能選（換身分），不在這裡匯出、刪除
		b_enter.pressed.connect(_on_select.bind(str(c.get("char_id", "")), b_enter))
		var b_exp := UiBuild.button(acts, "匯出", Callable(), SMALL_W)
		b_exp.name = "Export"
		b_exp.tooltip_text = "把角色存成檔案（.jychar.json）給朋友帶到他的世界"
		b_exp.pressed.connect(export_char.bind(c))
		b_exp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var b_del := UiBuild.button(acts, "刪除", Callable(), SMALL_W)
		b_del.pressed.connect(_on_delete.bind(c))
		b_del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_create.disabled = own.size() >= UiKeys.MAX_CHARS
	btn_create.tooltip_text = "角色已滿 %d 個" % UiKeys.MAX_CHARS if btn_create.disabled else ""
	_fit_list_height()

## 清單高度：內容多高就多高，但不超過 LIST_MAX_H（再多就捲動）
func _fit_list_height() -> void:
	if list_scroll == null:
		return
	var h := list_box.get_combined_minimum_size().y
	list_scroll.custom_minimum_size = Vector2(0, clampf(h, LIST_MIN_H, LIST_MAX_H))

func _on_char_list(list: Array) -> void:
	apply_list(list)

func _on_welcomed(_info: Dictionary) -> void:
	_set_status("")
	apply_list(UiClient.char_list())
	_refresh_import_button()
	request_list()

func _on_select(char_id: String, btn: Button) -> void:
	if char_id == "":
		return
	_awaiting_enter = true
	_set_status("進入江湖中……", StatusKind.INFO)
	send(UiKeys.I_CHAR_SELECT, { "char_id": char_id }, [btn], func(ok: bool, reason: String):
		if not ok:
			_awaiting_enter = false
			_set_status(UiClient.reason_inline(reason)))

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
			_set_status("" if ok else UiClient.reason_inline(reason)))

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


# ---------------------------------------------------------------- M3c2 WP-CARRY

## 本身分的列（alt != true）
static func own_rows(list: Array) -> Array:
	var out: Array = []
	for c in list:
		if c is Dictionary and not bool(c.get("alt", false)):
			out.append(c)
	return out

## 別的身分的列依身分分組（保持主機給的順序）：[{ identity, kind, needs_confirm, rows }]
static func alt_groups(list: Array) -> Array:
	var out: Array = []
	var idx := {}
	for c in list:
		if not (c is Dictionary) or not bool(c.get("alt", false)):
			continue
		var ident := str(c.get("identity", ""))
		if not idx.has(ident):
			idx[ident] = out.size()
			out.append({ "identity": ident, "kind": "steam" if ident.begins_with("steam_") else "local",
				"needs_confirm": bool(c.get("needs_confirm", false)), "rows": [] })
		(out[idx[ident]]["rows"] as Array).append(c)
	return out

static func own_identity(list: Array) -> String:
	for c in list:
		if c is Dictionary and not bool(c.get("alt", false)) and str(c.get("identity", "")) != "":
			return str(c["identity"])
	return UiClient.identity()

## steam_76561198000001234 → steam_7656…1234
static func short_identity(ident: String) -> String:
	var pre := "steam_" if ident.begins_with("steam_") else ("local_" if ident.begins_with("local_") else "")
	var rest := ident.substr(pre.length())
	if rest.length() <= 8:
		return ident
	return pre + rest.substr(0, 4) + "…" + rest.substr(rest.length() - 4)

## 給人看的 Steam 帳號縮寫（不帶內部前綴）：steam_76561198000001234 → 7656…1234（M3c2 第二輪審查）
static func steam_short(ident: String) -> String:
	return short_identity(ident).trim_prefix("steam_")

## 分組標題：「本機角色」「Steam 角色（7656…1234）」；目前用的身分加「（目前）」
static func group_header(ident: String, current: bool) -> String:
	var t := ("Steam 角色（%s）" % steam_short(ident)) if ident.begins_with("steam_") else "本機角色"
	return t + ("（目前）" if current else "")

func _on_select_alt(c: Dictionary, btn: Button) -> void:
	if bool(c.get("needs_confirm", false)):
		_alt_target = c
		alt_label.text = ALT_CONFIRM % steam_short(str(c.get("identity", "")))
		alt_panel.visible = true
		alt_panel.reset_size()
		alt_panel.position = (size - alt_panel.get_combined_minimum_size()) / 2.0
		return
	_select_alt(c, btn)

func _on_alt_confirm() -> void:
	alt_panel.visible = false
	if not _alt_target.is_empty():
		_select_alt(_alt_target, null)
	_alt_target = {}

func _select_alt(c: Dictionary, btn: Button) -> void:
	_awaiting_enter = true
	_set_status("進入江湖中……", StatusKind.INFO)
	send(UiKeys.I_CHAR_SELECT, { "char_id": str(c.get("char_id", "")), "identity": str(c.get("identity", "")) },
		[btn] if btn != null else [], func(ok: bool, reason: String):
			if not ok:
				_awaiting_enter = false
				_set_status(UiClient.reason_inline(reason)))

# ---- 匯入 ----
func _on_world_info_changed(_info: Dictionary) -> void:
	_refresh_import_button()

func _refresh_import_button() -> void:
	if btn_import == null:
		return
	var ok := ImportDialog.allowed()
	btn_import.disabled = not ok
	btn_import.tooltip_text = "從朋友的世界帶角色進來（匯出檔或護照）" if ok else IMPORT_DISABLED_TIP

func open_import() -> void:
	# M3c2 審查：視窗後面的匯出路徑列與狀態列先收起來（長路徑會從視窗左右露出來）
	export_row.visible = false
	_set_status("")
	import_dialog.open_dialog()

func _on_foreign_imported(p: Dictionary) -> void:
	_set_status(foreign_imported_text(p), StatusKind.OK)

static func foreign_imported_text(p: Dictionary) -> String:
	var t := "已%s外來角色「%s」。" % ["更新" if bool(p.get("replaced", false)) else "匯入", str(p.get("name", ""))]
	var dropped: Array = p.get("dropped", []) if p.get("dropped") is Array else []
	if not dropped.is_empty():
		var shown: Array = dropped.slice(0, 6)
		t += "拿掉或調整了：" + "；".join(shown) + ("……等 %d 項" % dropped.size() if dropped.size() > 6 else "")
	return t

# ---- 匯出 ----
## 本機護照是最新的（online_s 與清單一致）就直接寫；否則送 passport_request，收到 passport 事件再寫
func export_char(c: Dictionary) -> void:
	var cid := str(c.get("char_id", ""))
	var wid := str(UiClient.world_info().get("world_id", ""))
	var sm := get_node_or_null("/root/SaveManager")
	if cid == "" or sm == null:
		return
	if c.has("online_s") and wid != "":
		var r: Dictionary = sm.call("load_passport", wid, cid)
		var pp: Variant = r.get("data", {})
		if bool(r.get("ok", false)) and pp is Dictionary and (pp as Dictionary).get("char") is Dictionary \
				and absf(float(pp["char"].get("online_s", -1.0)) - float(c["online_s"])) < 0.01:
			write_export(pp)
			return
	_pending_export = cid
	_set_status("")
	export_label.text = "正在向主機要最新的角色資料……"
	export_row.visible = true
	send(UiKeys.I_PASSPORT_REQUEST, { "char_id": cid }, [], func(ok: bool, reason: String):
		if not ok:
			_pending_export = ""
			export_label.text = UiClient.reason_inline(reason))

func _on_events(batch: Array) -> void:
	if _pending_export == "":
		return
	for e in batch:
		if e is Dictionary and str(e.get("key", "")) == UiKeys.E_PASSPORT:
			var pp: Dictionary = (e.get("p", {}) as Dictionary).duplicate(true)
			pp.erase("peer")
			if str(pp.get("char_id", "")) == _pending_export:
				_pending_export = ""
				write_export(pp)
				return

func write_export(pp: Dictionary) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	var gd := get_node_or_null("/root/GameData")
	var meta := { "world_name": str(UiClient.world_info().get("world_name", "")),
		"content_hash": str(gd.get("content_hash")) if gd != null else "" }
	var path := str(sm.call("export_character", pp, meta)) if sm != null else ""
	_set_status("")
	export_row.visible = true
	if path == "":
		last_export_path = ""
		# M3c2 第三輪審查：原因用中文、紅字（原本直接顯示 passport_bad_format、commit tmp failed (…)）
		export_label.text = export_error_text(str(sm.get("last_error")) if sm != null else "")
		UiBuild.error(export_label)
		return
	last_export_path = path
	export_label.theme_type_variation = ""
	# M3c2 第三輪審查：路徑自己一行（原本在檔名中間換行、最後一行只剩「色」。」）
	export_label.text = export_ok_text(path)

## 匯出成功的訊息：路徑單獨一行
static func export_ok_text(path: String) -> String:
	return "已匯出到：\n%s\n把這個檔案給朋友，他在自己的世界按「匯入角色」。" % display_path(path)

## 匯出失敗的原因（SaveManager.last_error → 中文）
static func export_error_text(last_error: String) -> String:
	if last_error == "passport_bad_format":
		return "匯出失敗：角色資料格式不對。請重新進入世界後再匯出一次。"
	return "匯出失敗：無法寫入檔案。請確認資料夾可以寫入、磁碟還有空間。"

## 給人看的路徑：Windows 用反斜線（玩家在檔案總管找得到；和匯入視窗共用 ImportDialog.display_path）
static func display_path(path: String) -> String:
	return ImportDialog.display_path(path)

func open_exports_folder() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("exports_dir"):
		OS.shell_open(str(sm.call("exports_dir")))

## 狀態列：錯誤（預設）紅字；成功（例：匯入完成）金色；一般進度訊息（進入江湖中、等待主機）淡色（M3c2 審查）。
## 有新的狀態訊息時，舊的匯出路徑列收起來（不疊在一起）
func _set_status(text: String, kind: int = StatusKind.ERROR) -> void:
	status_label.text = text
	status_label.visible = text != ""
	var col: Color = UiTheme.JY_ERROR_LIGHT
	if kind == StatusKind.OK:
		col = UiTheme.JY_GOLD_LIGHT
	elif kind == StatusKind.INFO:
		col = UiTheme.JY_MUTED_LIGHT
	status_label.add_theme_color_override("font_color", col)
	if text != "" and export_row != null:
		export_row.visible = false
