class_name ImportDialog
extends UiDialog
## 匯入角色（M3C2_PLAN §5.8、§5.1、§5.4；M2 P2 passport_import）：角色選擇畫面「匯入角色」打開。
## 1. 選檔：清單預設列出 <資料根目錄>/passports/ 底下的護照；快捷「護照資料夾」「匯出資料夾」「瀏覽…」（FileDialog，*.json）。
## 2. 預覽：用和主機同一個 ForeignImport.sanitize 算出名字、性別、門派、實戰、主要技能、銀兩、物品數、會被拿掉的東西；
##    神兵預設拿掉（主機 allow_foreign_divine 打開才照登記）。
## 3. 「確定匯入」→ passport_import { passport[, new_name] }；名字被佔用（passport_name_taken）或不合法 → 顯示改名欄再送一次；
##    foreign_same_world → 提示改用「護照 → 用護照還原」。
## 誠實說明：別的世界的角色無法驗證，只會把數值截到本世界的合法範圍；匯入是複製，原世界的角色照舊在。

signal imported(p: Dictionary)

const NOTE := "把朋友世界的角色帶進這個世界（複製一份；原本世界的角色照舊在）。別的世界的存檔無法驗證，" \
	+ "所以匯入時會把數值截到本世界的合法範圍，錢莊、組織、進行中的任務等留在原世界。"
const SRC_PASSPORTS := "passports"
const SRC_EXPORTS := "exports"
const SAME_WORLD_HINT := "這個角色來自本世界，不能用匯入：請改用「護照 → 用護照還原」。"
const UNREADABLE := "檔案無法讀取。"
## M3c2 審查：讀不了的原因（ForeignImport.parse_text／SaveManager.read_import_file 的 error）
const UNREADABLE_WHY := {
	"too_large": "檔案無法讀取：檔案太大（超過 256 KB）。",
	"passport_too_large": "檔案無法讀取：角色資料太大（超過 64 KB），主機不會接受。",
	"not_json": "檔案無法讀取：不是 JSON 格式的檔案（可能已損壞）。",
	"not_char": "檔案無法讀取：這不是角色檔（.jychar.json）或護照。",
	"unreadable": "檔案無法讀取：打不開這個檔案。",
}
const FILE_ROWS := 3                 # 檔案清單一次顯示幾列（高度對齊整列，不切到字）
const PREVIEW_PAD := 10.0            # 預覽捲到底時最後一行下面留的空間
const PREVIEW_H := 230.0             # M3c2 第二輪審查：200 → 250（拿掉的清單常常被切掉）；第三輪：上緣固定後 230（整個視窗放得進 720 高）
const MORE_HINT := "清單較長，往下捲動可以看全部。"
const PICK_OTHER := "請選別的檔案：朋友按「匯出」做出來的 .jychar.json，或護照資料夾裡的護照。"
var file_count_label: Label
var preview_scroll: ScrollContainer
var more_hint: Label

var source_label: Label
var file_list: VBoxContainer
var file_scroll: ScrollContainer
var preview_box: VBoxContainer
var preview_title: Label
var rename_row: HBoxContainer
var rename_edit: LineEdit
var btn_confirm: Button
var file_dialog: FileDialog
var source := SRC_PASSPORTS
var files: Array = []            # 目前清單中的絕對路徑
var current: Dictionary = {}     # { path, passport, world_name, san }

func dialog_size() -> Vector2:
	return Vector2(720, 0)

func _build_body() -> void:
	title_label.text = "匯入角色"
	UiBuild.muted(UiBuild.label(body, NOTE, 14, true))
	var qrow := UiBuild.hbox(body, 8)
	UiBuild.button(qrow, "護照資料夾", func(): show_folder(SRC_PASSPORTS), 120).name = "SrcPassports"
	UiBuild.button(qrow, "匯出資料夾", func(): show_folder(SRC_EXPORTS), 120).name = "SrcExports"
	UiBuild.button(qrow, "瀏覽…", browse, 90).name = "Browse"
	source_label = UiBuild.muted(UiBuild.label(qrow, "", 13))
	source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_label.clip_text = true
	var fsc := UiBuild.scroll(body, 110)
	fsc.name = "FileScroll"
	fsc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	file_scroll = fsc
	file_list = UiBuild.vbox(fsc, 2)
	file_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# M3c2 第三輪審查：清單超過 3 列時，第 4 個檔案只能靠細捲軸找到 → 寫出共幾個、要往下捲
	file_count_label = UiBuild.muted(UiBuild.label(body, "", 13))
	file_count_label.name = "FileCountHint"
	body.add_child(HSeparator.new())
	preview_title = UiBuild.accent(UiBuild.label(body, "預覽", 16))
	var psc := UiBuild.scroll(body, PREVIEW_H)
	psc.name = "PreviewScroll"
	preview_scroll = psc
	preview_box = UiBuild.vbox(psc, 2)
	preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	more_hint = UiBuild.muted(UiBuild.label(body, MORE_HINT, 13))
	more_hint.name = "PreviewMoreHint"
	more_hint.visible = false
	# M3c2 第三輪審查：改名欄放在按鈕列右邊（出現時視窗高度不變、按鈕不移動；整個視窗才放得進 720 高的畫面）
	var brow := UiBuild.hbox(body, 10)
	btn_confirm = UiBuild.button(brow, "確定匯入", confirm, 130)
	btn_confirm.name = "ConfirmImport"
	btn_confirm.disabled = true
	UiBuild.button(brow, "取消", close, 90)
	rename_row = UiBuild.hbox(brow, 8)
	rename_row.name = "RenameRow"
	rename_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiBuild.label(rename_row, "改用名字", 15)
	rename_edit = UiBuild.line_edit(rename_row, "", "這個世界已有同名角色，請換一個名字", UiKeys.NAME_MAX_LEN)
	rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_row.visible = false

func open_dialog() -> void:
	ensure_built()
	status_label.text = ""
	current = {}
	rename_row.visible = false
	rename_edit.text = ""
	show_folder(source)
	_show_preview_empty()
	visible = true

# ---------------------------------------------------------------- 檔案

## 給人看的路徑：Windows 用反斜線（玩家在檔案總管找得到）
static func display_path(path: String) -> String:
	return path.replace("/", "\\") if OS.get_name() == "Windows" else path

static func _sm() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("SaveManager") if loop != null else null

static func folder_path(which: String) -> String:
	var sm := _sm()
	if sm == null:
		return ""
	if which == SRC_EXPORTS and sm.has_method("exports_dir"):
		return str(sm.call("exports_dir"))
	if sm.has_method("passports_dir"):
		return str(sm.call("passports_dir"))
	return ""

## 資料夾底下（含一層子資料夾：passports/<世界>/）的 *.json，排除 .bak、.tmp；新到舊
static func list_json(dir: String) -> Array:
	var out: Array = []
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return out
	var dirs: Array = [dir]
	for sub in DirAccess.get_directories_at(dir):
		dirs.append(dir.path_join(sub))
	for d in dirs:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".json"):
				out.append(str(d).path_join(f))
	out.sort_custom(func(a, b): return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b) \
		or (FileAccess.get_modified_time(a) == FileAccess.get_modified_time(b) and str(a) < str(b)))
	return out

func show_folder(which: String) -> void:
	ensure_built()
	source = which
	var dir := folder_path(which)
	source_label.text = display_path(dir)    # M3c2 第二輪審查：和匯出訊息一樣用反斜線
	source_label.tooltip_text = display_path(dir)
	set_files(list_json(dir))

func set_files(list: Array) -> void:
	files = list
	UiBuild.clear(file_list)
	if file_count_label != null:
		file_count_label.text = file_count_text(list.size())
	if list.is_empty():
		UiBuild.muted(UiBuild.label(file_list, "（這個資料夾沒有角色檔。朋友給你的 .jychar.json 可以放進「匯出資料夾」，或按「瀏覽…」）", 14, true))
		return
	var base := folder_path(source)
	var row_h := 0.0
	for p in list:
		var rel := str(p).trim_prefix(base).trim_prefix("/")
		var b := UiBuild.button(file_list, rel, Callable())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = str(p)
		b.pressed.connect(load_file.bind(str(p)))
		row_h = maxf(row_h, b.get_combined_minimum_size().y)
	_fit_file_rows(row_h)

## 檔案清單下面的一行（超過 FILE_ROWS 列要提醒往下捲）
static func file_count_text(n: int) -> String:
	if n <= 0:
		return ""
	if n > FILE_ROWS:
		return "共 %d 個檔案，清單往下捲動可以看全部。" % n
	return "共 %d 個檔案。" % n

## 清單高度對齊整列（M3c2 審查：第 4 個按鈕被切在字中間）
func _fit_file_rows(row_h: float) -> void:
	if file_scroll == null or row_h <= 0.0:
		return
	var sep := float(file_list.get_theme_constant("separation"))
	file_scroll.custom_minimum_size = Vector2(0, FILE_ROWS * row_h + (FILE_ROWS - 1) * sep)

func browse() -> void:
	if file_dialog == null:
		file_dialog = FileDialog.new()
		file_dialog.name = "ImportFileDialog"
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.filters = PackedStringArray(["*.json ; 角色檔、護照"])
		file_dialog.title = "選擇角色檔"
		file_dialog.use_native_dialog = false
		file_dialog.file_selected.connect(load_file)
		add_child(file_dialog)
	var start := folder_path(SRC_PASSPORTS)
	if start != "" and DirAccess.dir_exists_absolute(start):
		file_dialog.current_dir = start
	file_dialog.popup_centered_ratio(0.7)

# ---------------------------------------------------------------- 預覽

func load_file(path: String) -> void:
	ensure_built()
	status_label.text = ""
	rename_row.visible = false
	var sm := _sm()
	var r: Dictionary = sm.call("read_import_file", path) if sm != null and sm.has_method("read_import_file") else {}
	if not bool(r.get("ok", false)):
		current = {}
		show_unreadable(str(r.get("error", "unreadable")))
		return
	var pp: Dictionary = r["passport"]
	var san := preview_of(pp)
	current = { "path": path, "passport": pp, "world_name": str(r.get("world_name", "")), "san": san }
	apply_preview(current)

## 客戶端預覽：同一個 sanitize（GameData.tables、rules；伺服器選項用預設值）
static func preview_of(pp: Dictionary) -> Dictionary:
	var loop := Engine.get_main_loop() as SceneTree
	var gd: Node = loop.root.get_node_or_null("GameData") if loop != null else null
	var tables: Dictionary = gd.get("tables") if gd != null else {}
	var rules: Dictionary = gd.get("rules") if gd != null else {}
	var opts: Dictionary = gd.call("default_server_options") if gd != null and gd.has_method("default_server_options") else {}
	return ForeignImport.sanitize(pp, tables, rules, opts)

## 讀不了的檔案：原因寫在預覽區（M3c2 審查：原本只在按鈕下面寫「檔案無法讀取。」、預覽還說「選一個檔案看預覽」）
static func unreadable_text(err: String) -> String:
	return str(UNREADABLE_WHY.get(err, UNREADABLE_WHY["unreadable"]))

func show_unreadable(err: String) -> void:
	ensure_built()
	UiBuild.clear(preview_box)
	var l := UiBuild.error(UiBuild.label(preview_box, unreadable_text(err), 15, true))
	l.name = "UnreadableLine"
	UiBuild.muted(UiBuild.label(preview_box, PICK_OTHER, 14, true))
	btn_confirm.disabled = true
	status_label.text = ""

## 這份護照是不是本世界出去的（world_id 或角色的來源鏈；主機另外比對簽章）
static func is_same_world(pp: Dictionary, my_world_id: String) -> bool:
	return my_world_id != "" and ForeignImport.is_from_world(pp, my_world_id)

## 預覽的文字列（純函式，測試用）
static func preview_lines(pp: Dictionary, san: Dictionary, world_name: String, my_world_id: String) -> Array:
	var out: Array = []
	if not bool(san.get("ok", false)):
		out.append("這個檔案不是可以匯入的角色（格式不對）。")
		return out
	var sm: Dictionary = san.get("summary", {})
	var wn := world_name if world_name != "" else str(pp.get("world_name", pp.get("world_id", "")))
	var who := "%s　%s　%s　實戰 %d" % [str(sm.get("name", "?")), UiKeys.GENDER_LABELS.get(str(sm.get("gender", "")), ""),
		str(sm.get("sect_name", "")) if str(sm.get("sect_name", "")) != "" else "無門派", int(sm.get("combat_xp", 0))]
	# M3c2 審查：本世界的檔案不能匯入 → 只顯示提示與一行摘要（不列「會被拿掉的東西」）
	if is_same_world(pp, my_world_id):
		out.append(SAME_WORLD_HINT)
		out.append(who)
		return out
	out.append("來源世界：%s" % wn)
	out.append(who)
	var sk: Array = []
	for t in sm.get("top_skills", []):
		if t is Array and t.size() >= 2:
			sk.append("%s %d" % [str(t[0]), int(t[1])])
	out.append("主要技能：" + ("、".join(sk) if not sk.is_empty() else "（無）"))
	out.append("銀兩 %d　物品 %d 件" % [int(sm.get("money", 0)), int(sm.get("items_n", 0))])
	var dn: Array = sm.get("divine_names", [])
	if not dn.is_empty():
		out.append("神兵：%s（主機預設不接受外來神兵，會拿掉）" % "、".join(dn))
	var dropped: Array = san.get("dropped", [])
	if dropped.is_empty():
		out.append("會被拿掉的東西：（無）")
	else:
		out.append("會被拿掉或調整的東西：")
		for d in dropped:
			out.append("・" + str(d))
	return out

func apply_preview(cur: Dictionary) -> void:
	ensure_built()
	UiBuild.clear(preview_box)
	var my_world := str(UiClient.world_info().get("world_id", ""))
	var lines := preview_lines(cur.get("passport", {}), cur.get("san", {}), str(cur.get("world_name", "")), my_world)
	for t in lines:
		var l := UiBuild.label(preview_box, str(t), 15, true)
		if str(t) == SAME_WORLD_HINT:
			UiBuild.error(l)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, PREVIEW_PAD)
	preview_box.add_child(pad)
	_refresh_more_hint.call_deferred()
	var same := is_same_world(cur.get("passport", {}), my_world)
	btn_confirm.disabled = not bool((cur.get("san", {}) as Dictionary).get("ok", false)) or same or not allowed()
	if not allowed():
		status_label.text = "主機沒有開放外來角色"

## 預覽內容比看得到的高 → 下面寫「往下捲動可以看全部」（版面排好之後才量得到）
func _refresh_more_hint() -> void:
	if preview_scroll == null or more_hint == null or not is_instance_valid(preview_scroll):
		return
	if not preview_scroll.is_inside_tree():
		more_hint.visible = false
		return
	await get_tree().process_frame
	if not is_instance_valid(preview_scroll):
		return
	var sb := preview_scroll.get_v_scroll_bar()
	more_hint.visible = sb != null and sb.max_value - sb.page > 1.0

func _show_preview_empty() -> void:
	UiBuild.clear(preview_box)
	UiBuild.muted(UiBuild.label(preview_box, "（選一個檔案看預覽）", 15))
	btn_confirm.disabled = true

## 主機允許外來角色嗎（world_info.foreign_allowed；舊主機沒有這個欄位 → 依選項，沒有就當不允許）
static func allowed() -> bool:
	var wi := UiClient.world_info()
	if wi.has("foreign_allowed"):
		return bool(wi["foreign_allowed"])
	return bool(wi.get("allow_foreign_characters", false))

# ---------------------------------------------------------------- 送出

func confirm() -> void:
	if current.is_empty():
		return
	var args := { "passport": current["passport"] }
	if rename_row.visible and rename_edit.text.strip_edges() != "":
		args["new_name"] = rename_edit.text.strip_edges()
	status_label.text = ""
	_gate().send(UiKeys.I_PASSPORT_IMPORT, args, [btn_confirm], func(ok: bool, reason: String):
		if not is_instance_valid(self):
			return
		on_result(ok, reason))

func on_result(ok: bool, reason: String) -> void:
	if ok:
		status_label.text = ""
		imported.emit(current)
		close()
		return
	match reason:
		UiKeys.R_PASSPORT_NAME_TAKEN, "bad_value:new_name":
			rename_row.visible = true
			status_label.text = "這個名字不能用（已有人用或不合規定），請換一個名字再按「確定匯入」。"
			rename_edit.grab_focus.call_deferred()
		UiKeys.R_FOREIGN_SAME_WORLD:
			status_label.text = SAME_WORLD_HINT
		"bad_value:passport":
			status_label.text = unreadable_text("passport_too_large")
		_:
			status_label.text = UiClient.reason_inline(reason)
